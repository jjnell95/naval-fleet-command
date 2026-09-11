"""Import the public-domain Natural Earth 1:10m land dataset (not 10 m resolution).

Build-only dependencies: shapely==2.1.2, pyshp==3.1.6.
Usage: python import_coastlines.py /path/to/ne_10m_land.zip
The checked-in regional extraction lets normal scenario builds run offline once Shapely is installed.
"""
import hashlib
import json
import sys
import zipfile
from pathlib import Path

import shapefile
from shapely.geometry import box, shape
from shapely.ops import unary_union


def polygons(geometry):
    if geometry.geom_type == "Polygon":
        yield geometry
    elif hasattr(geometry, "geoms"):
        for part in geometry.geoms:
            yield from polygons(part)


def main(archive):
    archive = Path(archive)
    region = box(-46, 52, 55, 81)
    with zipfile.ZipFile(archive) as z:
        import io
        reader = shapefile.Reader(shp=io.BytesIO(z.read("ne_10m_land.shp")),
                                  shx=io.BytesIO(z.read("ne_10m_land.shx")),
                                  dbf=io.BytesIO(z.read("ne_10m_land.dbf")))
        parts = [shape(s.__geo_interface__).intersection(region) for s in reader.shapes()]
        version = z.read("ne_10m_land.VERSION.txt").decode().strip()
    merged = unary_union(parts)
    # Preserve separate islands and straits. Inland lake holes are outside this sea game.
    rings = [[[round(x, 6), round(y, 6)] for x, y in p.exterior.coords]
             for p in polygons(merged) if not p.is_empty]
    result = {"source": "Natural Earth 1:10m land", "version": version,
              "url": "https://naturalearth.s3.amazonaws.com/10m_physical/ne_10m_land.zip",
              "license": "Public domain", "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
              "bounds_lon_lat": [-46, 52, 55, 81], "rings_lon_lat": rings}
    path = Path(__file__).with_name("coastlines.json")
    path.write_text(json.dumps(result, separators=(",", ":")) + "\n")
    print(f"{len(rings)} islands / mainland polygons; {path.stat().st_size:,} bytes; version {version}")


if __name__ == "__main__":
    main(sys.argv[1])
