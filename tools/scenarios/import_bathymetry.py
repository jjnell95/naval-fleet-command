"""Build the regional sea-floor raster from Natural Earth 1:10m bathymetry (public domain).

Natural Earth publishes bathymetry as nested depth-band polygons: everything deeper than 0 m,
200 m, 1000 m, 2000 m and so on. That is a contour chart, not a depth grid, so this script
interpolates between contours to give a continuous floor the simulation can query anywhere:

1. Clip each band to the same region as the coastline extraction and project it into an oblique
   stereographic plane centred on the Norwegian Sea. Stereographic is conformal, so a distance
   transform in that plane measures the same distance north-south as east-west.
2. Rasterise the bands at 1 nm and give every water cell the index of the deepest band it lies in.
3. Inside a band, depth runs linearly from the shallower contour to the deeper one by relative
   distance: D = D_k + (D_k+1 - D_k) * d_up / (d_up + d_down). The coastline is the 0 m contour.
   A deeper contour more than CAP_NM away is treated as CAP_NM away, so the middle of a wide
   shallow sea still deepens away from its coasts instead of staying pinned near the shoreline.
4. Resample into a regular latitude/longitude grid and encode as 8-bit greyscale:
   value = round(255 * sqrt(depth / DEPTH_SCALE_M)); 0 is land. The square root spends
   resolution where it matters: a metre or two near the surface, tens of metres in the abyss.
5. Bake a hill-shade of the full-precision field into a second 8-bit raster for the chart. Relief
   computed from the quantised depth would show every encoding step as a terrace; computed here,
   before quantisation, it is smooth. It is presentation only and the simulation never reads it.
6. Write a half-float copy at half resolution for the chart shader. At 1000-3000 m one 8-bit step
   is 20-33 m, enough to make a contour on a gentle slope wander by a pixel or two; half floats
   hold a metre or two there. Two-mile cells are still finer than the 1:10m source supports.

The contours honour the source exactly; everything between them is interpolation. It is a
1:10 million chart. It is good enough to tell a continental shelf from an ocean basin, a ridge
from a trench, and whether a submarine has room to go deep. It says nothing about a shoal, a
channel, a wreck or under-keel clearance, and must never be read as a navigation chart.

Build-only dependencies: pyshp==3.1.6, shapely==2.1.2, numpy, scipy, pillow, OpenEXR.
Usage:
    python import_bathymetry.py /path/to/ne_10m_bathymetry_all   # directory of .shp/.shx/.dbf
    python import_bathymetry.py /path/to/ne_10m_bathymetry_all.zip
The source is the official Natural Earth 5.1.1 release, identical to the v5.1.1 tag of
github.com/nvkelso/natural-earth-vector (10m_physical/ne_10m_bathymetry_all).
"""
import hashlib
import io
import json
import math
import sys
import zipfile
from pathlib import Path

import numpy as np
import OpenEXR
import shapefile
from PIL import Image, ImageDraw
from scipy import ndimage
from shapely import segmentize
from shapely.geometry import box, shape
from shapely.ops import transform

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "data" / "bathymetry"
NAME = "north_atlantic"

# Same region as tools/scenarios/coastlines.json, so every chart that has land has a floor.
LON_MIN, LAT_MIN, LON_MAX, LAT_MAX = -46.0, 52.0, 55.0, 81.0
DLAT = 1.0 / 60.0  # one nautical mile north-south
DLON = 1.0 / 30.0  # 0.3 to 1.2 nm east-west across the region
LAYERS = [("L_0", 0), ("K_200", 200), ("J_1000", 1000), ("I_2000", 2000),
          ("H_3000", 3000), ("G_4000", 4000), ("F_5000", 5000)]
DEPTHS = [d for _, d in LAYERS] + [6000]
DEPTH_SCALE_M = 6000.0
CAP_NM = 40.0
PROJ_CELL_NM = 1.0
SMOOTH_SIGMA_NM = 2.0  # Natural Earth's polygons are partly raster-derived; soften their steps
RELIEF_EXAGGERATION = 24.0  # sea-floor slopes are gentle; shading needs a vertical exaggeration
RELIEF_AZIMUTH_DEG, RELIEF_ALTITUDE_DEG = 315.0, 45.0
EARTH_R_NM = 3440.065
LAT0, LON0 = math.radians(66.5), math.radians(4.5)


def stereo(lon, lat):
    """Oblique stereographic projection to nautical miles about (LAT0, LON0)."""
    lam = np.radians(lon) - LON0
    phi = np.radians(lat)
    k = 2.0 * EARTH_R_NM / (1.0 + math.sin(LAT0) * np.sin(phi) + math.cos(LAT0) * np.cos(phi) * np.cos(lam))
    x = k * np.cos(phi) * np.sin(lam)
    y = k * (math.cos(LAT0) * np.sin(phi) - math.sin(LAT0) * np.cos(phi) * np.cos(lam))
    return x, y


def readers(source):
    source = Path(source)
    out = {}
    if source.suffix == ".zip":
        z = zipfile.ZipFile(source)
        names = z.namelist()

        def member(stem, ext):
            match = [n for n in names if n.endswith(f"{stem}.{ext}")]
            return io.BytesIO(z.read(match[0]))
        for layer, _ in LAYERS:
            stem = f"ne_10m_bathymetry_{layer}"
            out[layer] = (shapefile.Reader(shp=member(stem, "shp"), shx=member(stem, "shx"), dbf=member(stem, "dbf")),
                          hashlib.sha256(member(stem, "shp").getvalue()).hexdigest())
    else:
        for layer, _ in LAYERS:
            stem = source / f"ne_10m_bathymetry_{layer}"
            out[layer] = (shapefile.Reader(str(stem)), hashlib.sha256(stem.with_suffix(".shp").read_bytes()).hexdigest())
    return out


def polygons(geometry):
    if geometry.geom_type == "Polygon":
        yield geometry
    elif hasattr(geometry, "geoms"):
        for part in geometry.geoms:
            yield from polygons(part)


def main(source):
    region = box(LON_MIN, LAT_MIN, LON_MAX, LAT_MAX)
    # Projected raster covering the region, with a margin so distances near the edge are sane.
    edge_lon = np.concatenate([np.linspace(LON_MIN, LON_MAX, 400), np.full(200, LON_MAX),
                               np.linspace(LON_MAX, LON_MIN, 400), np.full(200, LON_MIN)])
    edge_lat = np.concatenate([np.full(400, LAT_MIN), np.linspace(LAT_MIN, LAT_MAX, 200),
                               np.full(400, LAT_MAX), np.linspace(LAT_MAX, LAT_MIN, 200)])
    ex, ey = stereo(edge_lon, edge_lat)
    margin = 60.0
    px0, px1 = ex.min() - margin, ex.max() + margin
    py0, py1 = ey.min() - margin, ey.max() + margin
    pw = int(math.ceil((px1 - px0) / PROJ_CELL_NM))
    ph = int(math.ceil((py1 - py0) / PROJ_CELL_NM))
    print(f"projected grid {pw} x {ph}")

    def to_pixels(x, y):
        return (x - px0) / PROJ_CELL_NM, (py1 - y) / PROJ_CELL_NM

    band = np.full((ph, pw), -1, dtype=np.int8)
    hashes = {}
    sources = readers(source)
    for index, (layer, depth) in enumerate(LAYERS):
        reader, digest = sources[layer]
        hashes[layer] = digest
        mask_img = Image.new("1", (pw, ph), 0)
        draw = ImageDraw.Draw(mask_img)
        count = 0
        for rec in reader.shapes():
            geom = shape(rec.__geo_interface__)
            if not geom.intersects(region):
                continue
            clipped = segmentize(geom.intersection(region), 0.2)
            for poly in polygons(clipped):
                if poly.is_empty:
                    continue
                proj = transform(lambda x, y: to_pixels(*stereo(np.asarray(x), np.asarray(y))), poly)
                # Exterior filled, holes cut, one polygon at a time so a hole never erases a
                # separate island of the same band sitting inside it.
                minx, miny, maxx, maxy = proj.bounds
                ox, oy = int(math.floor(minx)) - 1, int(math.floor(miny)) - 1
                w, h = int(math.ceil(maxx)) - ox + 2, int(math.ceil(maxy)) - oy + 2
                tile = Image.new("1", (w, h), 0)
                tdraw = ImageDraw.Draw(tile)
                tdraw.polygon([(x - ox, y - oy) for x, y in proj.exterior.coords], fill=1)
                for hole in proj.interiors:
                    tdraw.polygon([(x - ox, y - oy) for x, y in hole.coords], fill=0)
                mask_img.paste(1, (ox, oy), tile)
                count += 1
        mask = np.array(mask_img, dtype=bool)
        # Bands are nested; a cell counts as this band only if it is also in every shallower one.
        band[(band == index - 1) & mask] = index
        print(f"{layer}: {count} polygons, {int((band >= index).sum()):,} cells at or below {depth} m")

    depth_field = np.zeros((ph, pw), dtype=np.float64)
    for k in range(len(LAYERS)):
        inside = band == k
        if not inside.any():
            continue
        d_up = ndimage.distance_transform_edt(band >= k, sampling=PROJ_CELL_NM)
        deeper = band > k
        if deeper.any():
            d_down = ndimage.distance_transform_edt(~deeper, sampling=PROJ_CELL_NM)
        else:
            d_down = np.full((ph, pw), CAP_NM)
        d_down = np.minimum(d_down, CAP_NM)
        # Distances are measured from cell centres, so the boundary sits half a cell out.
        up = d_up[inside] - 0.5 * PROJ_CELL_NM
        down = d_down[inside] + 0.5 * PROJ_CELL_NM
        up = np.maximum(up, 0.25 * PROJ_CELL_NM)
        depth_field[inside] = DEPTHS[k] + (DEPTHS[k + 1] - DEPTHS[k]) * up / (up + down)
    water = band >= 0
    smoothed = ndimage.gaussian_filter(depth_field, sigma=SMOOTH_SIGMA_NM / PROJ_CELL_NM)
    weight = ndimage.gaussian_filter(water.astype(np.float64), sigma=SMOOTH_SIGMA_NM / PROJ_CELL_NM)
    depth_field = np.where(water, smoothed / np.maximum(weight, 1e-6), 0.0)

    # Resample into the regular latitude/longitude grid the game reads.
    width = int(round((LON_MAX - LON_MIN) / DLON))
    height = int(round((LAT_MAX - LAT_MIN) / DLAT))
    lons = LON_MIN + (np.arange(width) + 0.5) * DLON
    lats = LAT_MAX - (np.arange(height) + 0.5) * DLAT
    glon, glat = np.meshgrid(lons, lats)
    gx, gy = stereo(glon, glat)
    col, row = to_pixels(gx, gy)
    coords = np.vstack([row.ravel() - 0.5, col.ravel() - 0.5])
    grid = ndimage.map_coordinates(depth_field, coords, order=1, mode="nearest").reshape(height, width)
    is_water = ndimage.map_coordinates(water.astype(np.float64), coords, order=1, mode="nearest").reshape(height, width) >= 0.5
    grid = np.where(is_water, np.maximum(grid, 1.0), 0.0)
    encoded = np.where(is_water, np.clip(np.round(255.0 * np.sqrt(grid / DEPTH_SCALE_M)), 1, 255), 0).astype(np.uint8)

    # Hill-shade in the output grid, so the light comes from the chart's north-west everywhere.
    # Gradients in metres per metre: rows are 1 nm apart, columns cos(lat) * 2 nm.
    dy_m = DLAT * 60.0 * 1852.0
    dx_m = (DLON * 60.0 * 1852.0) * np.cos(np.radians(lats))[:, None]
    gy, gx = np.gradient(grid)
    dzdx = gx / dx_m * RELIEF_EXAGGERATION
    dzdy = -gy / dy_m * RELIEF_EXAGGERATION  # row index runs south; flip to northward
    # The floor goes down as depth goes up: height is -depth.
    slope = np.arctan(np.hypot(dzdx, dzdy))
    aspect = np.arctan2(dzdx, dzdy)  # downhill-of-depth = uphill-of-height direction
    zen = math.radians(90.0 - RELIEF_ALTITUDE_DEG)
    azi = math.radians(RELIEF_AZIMUTH_DEG)
    shade = np.cos(zen) * np.cos(slope) + np.sin(zen) * np.sin(slope) * np.cos(azi - aspect)
    relief = np.clip(128.0 + (shade - math.cos(zen)) * 300.0, 0, 255)
    relief = np.where(is_water, relief, 128.0).astype(np.uint8)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    png = OUT_DIR / f"{NAME}_depth.png"
    Image.fromarray(encoded, mode="L").save(png, optimize=True)
    relief_png = OUT_DIR / f"{NAME}_relief.png"
    Image.fromarray(relief, mode="L").save(relief_png, optimize=True)
    chart = grid.reshape(height // 2, 2, width // 2, 2).mean(axis=(1, 3)).astype(np.float16)
    chart_exr = OUT_DIR / f"{NAME}_chart.exr"
    with OpenEXR.File({"compression": OpenEXR.ZIP_COMPRESSION, "type": OpenEXR.scanlineimage},
                      {"R": np.ascontiguousarray(chart)}) as exr:
        exr.write(str(chart_exr))
    meta = {
        "source": "Natural Earth 1:10m physical vectors, bathymetry (all depths)",
        "version": "5.1.1",
        "url": "https://github.com/nvkelso/natural-earth-vector/tree/v5.1.1/10m_physical/ne_10m_bathymetry_all",
        "license": "Public domain",
        "shp_sha256": hashes,
        "bounds_lon_lat": [LON_MIN, LAT_MIN, LON_MAX, LAT_MAX],
        "size_px": [width, height],
        "cell_deg": [DLON, DLAT],
        "row_order": "north_to_south",
        "encoding": "depth_m = depth_scale_m * (value / 255)^2; 0 is land",
        "depth_scale_m": DEPTH_SCALE_M,
        "contours_m": DEPTHS[:-1],
        "interpolation": ("linear in relative distance between Natural Earth contours in an oblique "
                          "stereographic plane at 1 nm; deeper contour capped at %d nm; gaussian sigma %.1f nm"
                          % (CAP_NM, SMOOTH_SIGMA_NM)),
        "chart": {"file": f"{NAME}_chart.exr", "size_px": [width // 2, height // 2],
                  "encoding": "half-float metres, 2x2 cell mean; presentation only"},
        "relief": {"file": f"{NAME}_relief.png", "azimuth_deg": RELIEF_AZIMUTH_DEG,
                   "altitude_deg": RELIEF_ALTITUDE_DEG, "vertical_exaggeration": RELIEF_EXAGGERATION,
                   "encoding": "128 is flat; presentation only"},
        "note": "Generalised 1:10m cartography. Not a hydrographic or navigation chart.",
    }
    (OUT_DIR / f"{NAME}_depth.json").write_text(json.dumps(meta, indent=1) + "\n")
    print(f"{relief_png.name}: {relief_png.stat().st_size:,} bytes; {chart_exr.name}: {chart_exr.stat().st_size:,} bytes")
    print(f"{png.name}: {width} x {height}, {png.stat().st_size:,} bytes; "
          f"max {grid.max():.0f} m, water {is_water.mean() * 100:.1f}% of cells")


if __name__ == "__main__":
    main(sys.argv[1])
