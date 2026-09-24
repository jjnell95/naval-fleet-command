"""Geographic chart construction in a local equirectangular nautical-mile plane.

Coastlines come from the checked-in Natural Earth 5.1.1 extraction. One minute
of latitude is one nm; longitude uses the anchor latitude. This is a local game
projection, not a geodesic solver: east-west scale varies away from the anchor.
Build dependencies: shapely==2.1.2. No runtime network requests.
"""
import json
import math
from functools import lru_cache
from pathlib import Path
from shapely.geometry import Polygon, box
from shapely.affinity import scale, translate

NM_PER_DEG_LAT = 60.0

def project(lat, lon, lat0, lon0):
    return (round((lon-lon0)*60*math.cos(math.radians(lat0)), 4), round((lat-lat0)*60, 4))

def pos(lat, lon, lat0, lon0):
    return list(project(lat, lon, lat0, lon0))

def at(place, lat0, lon0, bearing_deg=None, offset_nm=0.0):
    x,y = project(*PLACES[place], lat0, lon0)
    if bearing_deg is not None:
        x += math.sin(math.radians(bearing_deg))*offset_nm
        y += math.cos(math.radians(bearing_deg))*offset_nm
    return [round(x,4), round(y,4)]

PLACES = {
    # Norway
    "andoya":        (69.293, 16.144),   # Andoya, Vesteralen
    "evenes":        (68.491, 16.678),   # Evenes, Ofoten
    "bodo":          (67.269, 14.365),
    "bardufoss":     (69.056, 18.540),
    "banak":         (70.069, 24.973),   # Lakselv, Porsangerfjord
    "tromso":        (69.683, 18.918),
    "orland":        (63.699, 9.604),
    "haakonsvern":   (60.345, 5.244),    # Bergen naval base
    "vardo":         (70.370, 31.108),
    # Iceland, Faroes, United Kingdom
    "keflavik":      (63.985, -22.605),
    "reykjavik":     (64.146, -21.942),
    "vagar":         (62.064, -7.277),   # Faroe Islands
    "lossiemouth":   (57.705, -3.339),
    "scapa":         (58.900, -3.150),   # Orkney
    "stornoway":     (58.215, -6.319),
    "faslane":       (56.068, -4.820),
    # Baltic
    "karlskrona":    (56.161, 15.586),
    "visby":         (57.634, 18.299),   # Gotland
    "ronne":         (55.099, 14.700),   # Bornholm
    "rostock":       (54.145, 12.101),
    "gdynia":        (54.519, 18.551),
    "tallinn":       (59.437, 24.754),
    "liepaja":       (56.512, 21.013),
    "baltiysk":      (54.651, 19.910),   # Kaliningrad oblast
    # Russia, Northern Fleet
    "severomorsk":   (69.075, 33.416),
    "murmansk":      (68.970, 33.075),
    "polyarny":      (69.199, 33.451),
    "gadzhiyevo":    (69.256, 33.331),
    "olenya":        (68.152, 33.463),   # Olenegorsk airfield
    "monchegorsk":   (67.984, 32.833),
    "kipelovo":      (59.293, 39.481),   # Fedotovo, Vologda oblast
    "besovets":      (61.885, 34.154),   # Petrozavodsk, Karelia
    "severomorsk_1": (69.032, 33.297),
    "teriberka":     (69.164, 35.133),
    "rogachevo":     (71.617, 52.478),   # Novaya Zemlya
}



# Label locations are cartographic annotations, not force intelligence.
LABELS = [
    ("NORWEGIAN SEA", 68.0, 4.0, "water"), ("BARENTS SEA", 73.0, 33.0, "water"),
    ("NORTH ATLANTIC", 59.6, -13.0, "water"), ("GOTLAND BASIN", 57.0, 20.0, "water"),
    ("VESTFJORDEN", 67.55, 13.8, "water"), ("FAROE–SHETLAND CHANNEL", 61.0, -4.3, "water"),
    ("ICELAND–FAROE RIDGE", 63.1, -12.0, "water"),
    ("ICELAND", 64.9, -19.0, "land"), ("FAROE ISLANDS", 62.6, -7.0, "land"),
    ("SHETLAND", 60.8, -1.3, "land"), ("ORKNEY", 59.35, -3.0, "land"),
    ("SCOTLAND", 57.5, -4.3, "land"), ("NORWAY", 66.1, 14.7, "land"),
    ("LOFOTEN", 68.15, 14.0, "land"), ("NORTH CAPE", 71.5, 25.7, "land"),
    ("KOLA PENINSULA", 67.7, 35.5, "land"), ("SWEDEN", 57.3, 15.0, "land"),
    ("GOTLAND", 57.5, 18.5, "land"), ("ÖLAND", 56.8, 16.6, "land"),
    ("BORNHOLM", 55.4, 14.95, "land"), ("LATVIA", 57.0, 23.0, "land"),
    ("ESTONIA", 58.7, 25.0, "land"), ("POLAND", 53.8, 17.4, "land"),
    ("BJØRNØYA", 74.7, 19.0, "land"),
]

@lru_cache(maxsize=1)
def dataset():
    return json.loads(Path(__file__).with_name("coastlines.json").read_text())

def polygons(geometry):
    if geometry.geom_type == "Polygon":
        yield geometry
    elif hasattr(geometry, "geoms"):
        for part in geometry.geoms:
            yield from polygons(part)

def charted_box(center, extent):
    """The square the coastline polygons are clipped to: the playable chart plus 100 nm."""
    half = extent/2 + 100
    return [round(center[0]-half, 4), round(center[1]-half, 4), round(center[0]+half, 4), round(center[1]+half, 4)]

def chart(lat0, lon0, center, extent):
    """Clip outside the authored chart, retaining islands and polygon topology.

    0.2 nm generalization is for performance; Natural Earth itself is 1:10m.
    It does not support harbour navigation or a claim of sub-mile accuracy.
    Heights are uniform gameplay masking plateaus, not measured terrain.
    """
    view = box(*charted_box(center, extent))
    result=[]
    for ring in dataset()["rings_lon_lat"]:
        source=Polygon(ring)
        local=translate(scale(source, xfact=60*math.cos(math.radians(lat0)), yfact=60, origin=(lon0,lat0)), xoff=-lon0,yoff=-lat0)
        if not local.intersects(view): continue
        clipped=local.intersection(view).simplify(.2, preserve_topology=True)
        for part in polygons(clipped):
            if part.area < .035: continue
            pts=[[round(x,4),round(y,4)] for x,y in part.exterior.coords][:-1]
            # Keep the rendered ring and collision ring identical and valid after rounding.
            if len(pts)<3 or not Polygon(pts).is_valid: raise ValueError("Invalid coastline ring")
            height = 80 if lat0 < 60 and lon0 > 10 else 450
            result.append({"id": "ne_%04d" % len(result), "name": "",
                           "elevation_m":height, "points_nm":pts})
    labels=[{"text":name,"position_nm":pos(lat,lon,lat0,lon0),"kind":kind}
            for name,lat,lon,kind in LABELS]
    return result, labels
