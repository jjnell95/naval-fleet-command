"""Import the public-domain Natural Earth 1:10m land dataset (not 10 m resolution).

Build-only dependencies: shapely==2.1.2, pyshp==3.1.6.
Usage: python import_coastlines.py /path/to/ne_10m_land.zip [region ...]
Writes one regional extraction per chart region (tools/scenarios/coastlines/<region>.json), so
normal scenario builds run offline once Shapely is installed. With no region named, every region
in regions.py is written.
"""
import hashlib
import io
import json
import sys
import zipfile
from pathlib import Path

import shapefile
from shapely.geometry import box, shape
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).resolve().parent))
from regions import REGIONS


def polygons(geometry):
    if geometry.geom_type == "Polygon":
        yield geometry
    elif hasattr(geometry, "geoms"):
        for part in geometry.geoms:
            yield from polygons(part)


def main(archive, names):
    archive = Path(archive)
    with zipfile.ZipFile(archive) as z:
        reader = shapefile.Reader(shp=io.BytesIO(z.read("ne_10m_land.shp")),
                                  shx=io.BytesIO(z.read("ne_10m_land.shx")),
                                  dbf=io.BytesIO(z.read("ne_10m_land.dbf")))
        shapes = [shape(s.__geo_interface__) for s in reader.shapes()]
        version = z.read("ne_10m_land.VERSION.txt").decode().strip()
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    out_dir = Path(__file__).with_name("coastlines")
    out_dir.mkdir(exist_ok=True)
    for name in names or REGIONS:
        bounds = REGIONS[name]["bounds"]
        region = box(*bounds)
        parts = [s.intersection(region) for s in shapes if s.intersects(region)]
        merged = unary_union(parts)
        # Preserve separate islands and straits. Inland lake holes are outside this sea game.
        rings = [[[round(x, 6), round(y, 6)] for x, y in p.exterior.coords]
                 for p in polygons(merged) if not p.is_empty]
        result = {"source": "Natural Earth 1:10m land", "version": version,
                  "url": "https://naturalearth.s3.amazonaws.com/10m_physical/ne_10m_land.zip",
                  "license": "Public domain", "sha256": digest, "region": name,
                  "bounds_lon_lat": list(bounds), "rings_lon_lat": rings}
        path = out_dir / (name + ".json")
        path.write_text(json.dumps(result, separators=(",", ":")) + "\n")
        print(f"{name}: {len(rings)} islands / mainland polygons; {path.stat().st_size:,} bytes; version {version}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
