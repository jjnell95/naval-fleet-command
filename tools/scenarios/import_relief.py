"""Build the regional land-relief rasters for the chart: elevation and hill-shade ashore.

The sea-floor rasters (import_bathymetry.py) stop at the coast: every land cell is 0. The chart's
land is painted the way a late-1990s fleet-command map painted it, as a hypsometric tint with
relief shading, so it needs heights. This script supplies them on exactly the same grid as the
sea floor, so one texture transform serves both.

Source: the AWS Open Data "Terrain Tiles" (Tilezen/Mapzen, Terrarium encoding). At zoom 6 their
land is GMTED2010 (USGS) and their sea ETOPO1 (NOAA), both public domain; see
https://github.com/tilezen/joerd/blob/master/docs/data-sources.md. Only land heights are kept: the
sea is still Natural Earth's, because the simulation reads Natural Earth and the chart must agree
with it. Heights are presentation only. Nothing in the simulation reads these files.

1. Fetch every zoom-6 Terrarium tile over the region (cached, so a rebuild is offline) and mosaic
   them in Web Mercator. Terrarium: metres = R * 256 + G + B / 256 - 32768.
2. Low-pass the mosaic to the output cell so a coarse cell is an average, not an alias.
3. Sample it at the centre of every cell of the region's latitude/longitude grid (the grid of
   <region>_depth.png, north row first) and keep land only: heights at or below sea level are 0.
4. Encode heights as 8-bit greyscale, value = round(255 * sqrt(height / HEIGHT_SCALE_M)), the same
   square-root curve the sea floor uses, spending resolution on coastal lowland.
5. Bake a hill-shade of the full-precision heights, north-west light, into a second 8-bit raster
   (128 is flat). Computed before quantisation, so gentle ground does not terrace.

Build-only dependencies: numpy, scipy, pillow.
Usage:
    python import_relief.py [region ...]     # every region in regions.py with none named
Tiles are cached in $NFC_TILE_CACHE, default ~/.cache/nfc-terrain.
"""
import concurrent.futures
import hashlib
import io
import json
import math
import os
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from regions import REGIONS

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "data" / "bathymetry"
CACHE = Path(os.environ.get("NFC_TILE_CACHE", Path.home() / ".cache" / "nfc-terrain"))
TILE_URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
ZOOM = 6
TILE = 256
HEIGHT_SCALE_M = 6000.0
RELIEF_EXAGGERATION = 7.0  # 1-2 nm cells flatten real slopes; this restores a readable relief
RELIEF_AZIMUTH_DEG, RELIEF_ALTITUDE_DEG = 315.0, 45.0


def tile_x(lon, z):
    return (lon + 180.0) / 360.0 * (1 << z)


def tile_y(lat, z):
    phi = math.radians(lat)
    return (1.0 - math.log(math.tan(phi) + 1.0 / math.cos(phi)) / math.pi) / 2.0 * (1 << z)


def fetch(z, x, y):
    path = CACHE / str(z) / str(x) / f"{y}.png"
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(TILE_URL.format(z=z, x=x, y=y), headers={"User-Agent": "naval-fleet-command build"})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        tmp = path.with_suffix(".part")
        tmp.write_bytes(data)
        tmp.replace(path)
    return path


def decode(path):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    return a[..., 0] * 256.0 + a[..., 1] + a[..., 2] / 256.0 - 32768.0


def build(name):
    r = REGIONS[name]
    lon_min, lat_min, lon_max, lat_max = r["bounds"]
    dlon, dlat = r["dlon"], r["dlat"]
    width = int(round((lon_max - lon_min) / dlon))
    height = int(round((lat_max - lat_min) / dlat))

    x0 = int(math.floor(tile_x(lon_min, ZOOM))) - 1
    x1 = int(math.floor(tile_x(lon_max, ZOOM))) + 1
    y0 = max(int(math.floor(tile_y(lat_max, ZOOM))) - 1, 0)
    y1 = min(int(math.floor(tile_y(lat_min, ZOOM))) + 1, (1 << ZOOM) - 1)
    coords = [(x % (1 << ZOOM), x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]
    print(f"{len(coords)} zoom-{ZOOM} tiles, x {x0}..{x1}, y {y0}..{y1}")
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        paths = list(pool.map(lambda c: fetch(ZOOM, c[0], c[2]), coords))

    mosaic = np.zeros(((y1 - y0 + 1) * TILE, (x1 - x0 + 1) * TILE), dtype=np.float32)
    digest = hashlib.sha256()
    for (_, x, y), path in zip(coords, paths):
        digest.update(path.read_bytes())
        oy, ox = (y - y0) * TILE, (x - x0) * TILE
        mosaic[oy:oy + TILE, ox:ox + TILE] = decode(path)

    # Output cell size in mosaic pixels, at the region's mid latitude; blur by half of it.
    mid = math.radians(0.5 * (lat_min + lat_max))
    px_per_deg_lon = TILE * (1 << ZOOM) / 360.0
    cell_px = max(dlon * px_per_deg_lon, dlat * px_per_deg_lon / math.cos(mid))
    land = np.maximum(mosaic, 0.0)
    if cell_px > 1.0:
        land = ndimage.gaussian_filter(land, sigma=0.5 * cell_px)

    lons = lon_min + (np.arange(width) + 0.5) * dlon
    lats = lat_max - (np.arange(height) + 0.5) * dlat
    cols = np.array([tile_x(v, ZOOM) for v in lons]) * TILE - x0 * TILE
    rows = np.array([tile_y(v, ZOOM) for v in lats]) * TILE - y0 * TILE
    grow, gcol = np.meshgrid(rows - 0.5, cols - 0.5, indexing="ij")
    grid = ndimage.map_coordinates(land, [grow.ravel(), gcol.ravel()], order=1, mode="nearest").reshape(height, width)
    grid = np.clip(grid, 0.0, HEIGHT_SCALE_M)
    encoded = np.clip(np.round(255.0 * np.sqrt(grid / HEIGHT_SCALE_M)), 0, 255).astype(np.uint8)

    dy_m = dlat * 60.0 * 1852.0
    dx_m = (dlon * 60.0 * 1852.0) * np.cos(np.radians(lats))[:, None]
    gy, gx = np.gradient(grid.astype(np.float64))
    dzdx = gx / dx_m * RELIEF_EXAGGERATION
    dzdy = -gy / dy_m * RELIEF_EXAGGERATION
    slope = np.arctan(np.hypot(dzdx, dzdy))
    aspect = np.arctan2(-dzdx, -dzdy)  # the direction the ground faces, downhill
    zen = math.radians(90.0 - RELIEF_ALTITUDE_DEG)
    azi = math.radians(RELIEF_AZIMUTH_DEG)
    shade = np.cos(zen) * np.cos(slope) + np.sin(zen) * np.sin(slope) * np.cos(azi - aspect)
    relief = np.clip(128.0 + (shade - math.cos(zen)) * 300.0, 0, 255).astype(np.uint8)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    land_png = OUT_DIR / f"{name}_land.png"
    Image.fromarray(encoded, mode="L").save(land_png, optimize=True)
    relief_png = OUT_DIR / f"{name}_land_relief.png"
    Image.fromarray(relief, mode="L").save(relief_png, optimize=True)
    meta = {
        "region": name,
        "source": "AWS Open Data Terrain Tiles (Tilezen), Terrarium encoding, zoom %d: GMTED2010 on land" % ZOOM,
        "url": "https://registry.opendata.aws/terrain-tiles/",
        "credit": "GMTED2010 terrain data courtesy of the U.S. Geological Survey",
        "license": "Public domain (U.S. Government work)",
        "tiles": len(coords),
        "tiles_sha256": digest.hexdigest(),
        "bounds_lon_lat": [lon_min, lat_min, lon_max, lat_max],
        "size_px": [width, height],
        "cell_deg": [dlon, dlat],
        "row_order": "north_to_south",
        "encoding": "height_m = height_scale_m * (value / 255)^2; 0 is sea level or below",
        "height_scale_m": HEIGHT_SCALE_M,
        "relief": {"file": relief_png.name, "azimuth_deg": RELIEF_AZIMUTH_DEG, "altitude_deg": RELIEF_ALTITUDE_DEG,
                   "vertical_exaggeration": RELIEF_EXAGGERATION, "encoding": "128 is flat"},
        "note": "Presentation only: the chart's land tint and relief. The simulation never reads it.",
    }
    (OUT_DIR / f"{name}_land.json").write_text(json.dumps(meta, indent=1) + "\n")
    print(f"{land_png.name}: {width} x {height}, {land_png.stat().st_size:,} bytes, max {grid.max():.0f} m; "
          f"{relief_png.name}: {relief_png.stat().st_size:,} bytes")


if __name__ == "__main__":
    for region in sys.argv[1:] or list(REGIONS):
        print(f"== {region}: {REGIONS[region]['title']}")
        build(region)
