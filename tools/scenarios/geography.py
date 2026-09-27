"""Geographic chart construction in a local equirectangular nautical-mile plane.

Coastlines come from the checked-in Natural Earth 5.1.1 extractions, one per chart region in
regions.py; the region is chosen by the chart anchor. One minute of latitude is one nm;
longitude uses the anchor latitude. This is a local game projection, not a geodesic solver:
east-west scale varies away from the anchor. Build dependencies: shapely==2.1.2. No runtime
network requests.
"""
import json
import math
import sys
from functools import lru_cache
from pathlib import Path
from shapely.geometry import Polygon, box
from shapely.affinity import scale, translate

sys.path.insert(0, str(Path(__file__).resolve().parent))
from regions import REGIONS, region_for

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
    # Western Pacific: Japan, Korea, Russian Far East
    "yokosuka":      (35.293, 139.662),
    "sasebo":        (33.163, 129.720),
    "kure":          (34.240, 132.555),
    "maizuru":       (35.480, 135.390),
    "atsugi":        (35.455, 139.450),
    "hachinohe":     (40.556, 141.466),
    "kanoya":        (31.368, 130.845),
    "naha":          (26.196, 127.646),
    "kadena":        (26.356, 127.768),
    "misawa":        (40.703, 141.368),
    "chitose":       (42.795, 141.666),
    "komatsu":       (36.394, 136.407),
    "iwakuni":       (34.144, 132.236),
    "vladivostok":   (43.115, 131.885),
    "fokino":        (42.970, 132.410),   # Pacific Fleet, Strelok Bay
    "kamenny_ruchey": (49.235, 140.194),  # naval aviation, Sovetskaya Gavan
    "knevichi":      (43.399, 132.148),   # Vladivostok airfield
    "busan":         (35.100, 129.040),
    # Western Pacific: China and Taiwan
    "fuzhou":        (25.935, 119.663),   # Fuzhou Changle
    "huian":         (25.033, 118.821),   # Huian air base, Fujian
    "zhangzhou":     (24.567, 117.659),
    "leiyang":       (26.400, 112.870),   # naval aviation bomber base, Hunan
    "shantou":       (23.427, 116.762),
    "zhanjiang":     (21.190, 110.410),   # South Sea Fleet
    "sanya":         (18.220, 109.530),   # Yulin, Hainan
    "lingshui":      (18.506, 110.045),   # Hainan naval air base
    "ningbo":        (29.940, 121.930),   # Zhoushan / East Sea Fleet
    "hualien":       (23.975, 121.618),
    "suao":          (24.590, 121.870),   # Su-ao naval base
    "kaohsiung":     (22.610, 120.280),   # Zuoying
    "taitung":       (22.755, 121.102),
    "fiery_cross":   (9.550, 112.890),    # Fiery Cross Reef, Spratlys
    "subi":          (10.920, 114.080),
    "mischief":      (9.900, 115.530),
    "woody_island":  (16.834, 112.339),   # Paracels
    # Western Pacific: Philippines and Guam
    "clark":         (15.186, 120.560),
    "basa":          (14.987, 120.492),
    "puerto_princesa": (9.742, 118.759),
    "subic":         (14.794, 120.271),
    "andersen":      (13.584, 144.930),   # Guam
    "apra":          (13.443, 144.656),
    # Persian Gulf, Gulf of Oman, Red Sea
    "bandar_abbas":  (27.183, 56.278),
    "qeshm":         (26.950, 56.270),
    "jask":          (25.644, 57.775),
    "chabahar":      (25.290, 60.640),
    "bushehr":       (28.960, 50.840),
    "manama":        (26.200, 50.580),
    "isa_ab":        (25.918, 50.590),    # Isa Air Base, Bahrain
    "al_dhafra":     (24.248, 54.548),
    "fujairah":      (25.140, 56.340),
    "duqm":          (19.500, 57.700),
    "muscat":        (23.600, 58.590),
    "salalah":       (17.010, 54.090),
    "hodeidah":      (14.800, 42.950),
    "djibouti":      (11.550, 43.150),
    "jeddah":        (21.480, 39.190),
    "bab_el_mandeb": (12.583, 43.333),
    # Mediterranean
    "toulon":        (43.110, 5.930),
    "akrotiri":      (34.590, 32.988),    # Cyprus
    "limassol":      (34.680, 33.040),
    "tartus":        (34.900, 35.870),
    "khmeimim":      (35.401, 35.949),    # Latakia
    "souda":         (35.490, 24.120),    # Crete
    "sigonella":     (37.400, 14.920),    # Sicily
    "taranto":       (40.470, 17.240),
    "incirlik":      (37.002, 35.426),
    "haifa":         (32.820, 35.000),
    "alexandria":    (31.200, 29.870),
    "port_said":     (31.260, 32.300),
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
    # Western Pacific
    ("SEA OF JAPAN", 40.0, 134.5, "water"), ("EAST CHINA SEA", 28.5, 125.0, "water"),
    ("PHILIPPINE SEA", 20.0, 128.0, "water"), ("SOUTH CHINA SEA", 14.0, 114.5, "water"),
    ("TAIWAN STRAIT", 24.5, 119.4, "water"), ("BASHI CHANNEL", 21.3, 121.3, "water"),
    ("LUZON STRAIT", 20.3, 121.6, "water"), ("TSUSHIMA STRAIT", 34.3, 129.4, "water"),
    ("LA PÉROUSE STRAIT", 45.9, 142.0, "water"), ("YELLOW SEA", 35.5, 123.0, "water"),
    ("OKINAWA TROUGH", 26.5, 126.0, "water"), ("MIYAKO STRAIT", 25.3, 126.0, "water"),
    ("SULU SEA", 8.5, 120.5, "water"), ("SPRATLY ISLANDS", 9.6, 114.5, "water"),
    ("PARACEL ISLANDS", 16.5, 112.0, "water"), ("GULF OF TONKIN", 19.5, 107.5, "water"),
    ("JAPAN", 36.5, 138.0, "land"), ("HOKKAIDO", 43.5, 143.0, "land"), ("HONSHU", 37.5, 139.5, "land"),
    ("KYUSHU", 32.6, 131.0, "land"), ("KOREA", 36.7, 127.9, "land"), ("SAKHALIN", 50.5, 143.0, "land"),
    ("PRIMORYE", 44.8, 134.5, "land"), ("TAIWAN", 23.7, 121.0, "land"), ("LUZON", 16.5, 121.2, "land"),
    ("PALAWAN", 9.8, 118.7, "land"), ("HAINAN", 19.2, 109.7, "land"), ("FUJIAN", 26.2, 118.0, "land"),
    ("GUANGDONG", 23.5, 113.5, "land"), ("OKINAWA", 26.5, 128.0, "land"), ("MINDORO", 12.9, 121.1, "land"),
    ("VIETNAM", 15.5, 108.0, "land"), ("BORNEO", 3.0, 114.0, "land"), ("GUAM", 13.45, 144.8, "land"),
    # Persian Gulf, Gulf of Oman, Arabian Sea, Red Sea
    ("PERSIAN GULF", 26.8, 52.0, "water"), ("STRAIT OF HORMUZ", 26.55, 56.5, "water"),
    ("GULF OF OMAN", 24.6, 58.5, "water"), ("ARABIAN SEA", 19.0, 62.0, "water"),
    ("RED SEA", 20.0, 38.5, "water"), ("GULF OF ADEN", 12.5, 47.0, "water"),
    ("BAB EL-MANDEB", 12.8, 43.2, "water"), ("IRAN", 30.0, 55.5, "land"),
    ("OMAN", 21.5, 56.5, "land"), ("UNITED ARAB EMIRATES", 23.8, 54.0, "land"),
    ("SAUDI ARABIA", 24.5, 45.0, "land"), ("QATAR", 25.2, 51.2, "land"), ("YEMEN", 15.8, 46.5, "land"),
    ("MUSANDAM", 26.0, 56.25, "land"), ("QESHM", 26.75, 55.8, "land"), ("SOMALIA", 9.0, 48.5, "land"),
    ("PAKISTAN", 27.5, 65.5, "land"), ("EGYPT", 27.0, 30.5, "land"), ("SUDAN", 18.0, 33.0, "land"),
    # Mediterranean
    ("EASTERN MEDITERRANEAN", 34.0, 30.5, "water"), ("IONIAN SEA", 37.8, 18.5, "water"),
    ("AEGEAN SEA", 38.5, 25.2, "water"), ("LEVANTINE BASIN", 33.4, 33.6, "water"),
    ("TYRRHENIAN SEA", 40.0, 12.0, "water"), ("LIGURIAN SEA", 43.4, 8.5, "water"),
    ("STRAIT OF SICILY", 36.7, 12.2, "water"), ("GULF OF LION", 42.6, 4.3, "water"),
    ("ADRIATIC SEA", 43.0, 15.0, "water"), ("CYPRUS", 35.1, 33.3, "land"), ("CRETE", 35.25, 24.9, "land"),
    ("SICILY", 37.6, 14.2, "land"), ("SARDINIA", 40.1, 9.1, "land"), ("TURKEY", 38.5, 33.0, "land"),
    ("SYRIA", 35.0, 38.0, "land"), ("LEBANON", 33.9, 35.9, "land"), ("ISRAEL", 31.4, 34.9, "land"),
    ("LIBYA", 30.5, 19.5, "land"), ("GREECE", 39.5, 22.0, "land"), ("ITALY", 42.8, 12.8, "land"),
    ("FRANCE", 44.4, 4.0, "land"), ("CORSICA", 42.2, 9.1, "land"), ("RHODES", 36.2, 28.0, "land"),
]

@lru_cache(maxsize=4)
def dataset(region):
    path = Path(__file__).with_name("coastlines") / (region + ".json")
    return json.loads(path.read_text())


def region_of(lat0, lon0):
    return region_for(lat0, lon0)


@lru_cache(maxsize=4)
def _land_index(region):
    from shapely.strtree import STRtree
    polys = [Polygon(ring) for ring in dataset(region)["rings_lon_lat"]]
    return polys, STRtree(polys)


def is_land(lat, lon):
    """Whether a latitude/longitude falls inside a Natural Earth land polygon of its region."""
    from shapely.geometry import Point
    polys, tree = _land_index(region_of(lat, lon))
    pt = Point(lon, lat)
    return any(polys[i].contains(pt) for i in tree.query(pt))


def reclaimed_island(lat, lon, length_nm, width_nm, bearing_deg, lat0, lon0, name, elevation_m=6.0):
    """A small rectangular landmass in nm about the anchor, for reclaimed outposts that postdate
    the Natural Earth coastline. Approximate footprints from public satellite imagery."""
    cx, cy = project(lat, lon, lat0, lon0)
    a = math.radians(bearing_deg)
    ux, uy = math.sin(a), math.cos(a)
    vx, vy = -uy, ux
    hl, hw = length_nm / 2.0, width_nm / 2.0
    pts = [[round(cx + ux * hl * sx + vx * hw * sy, 4), round(cy + uy * hl * sx + vy * hw * sy, 4)]
           for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    return {"id": "reclaimed_" + name.lower().replace(" ", "_"), "name": name, "elevation_m": elevation_m, "points_nm": pts}


def labels_for(region):
    lon_min, lat_min, lon_max, lat_max = REGIONS[region]["bounds"]
    return [(name, lat, lon, kind) for name, lat, lon, kind in LABELS
            if lon_min <= lon <= lon_max and lat_min <= lat <= lat_max]

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

def default_height_m(lat0, lon0):
    """Uniform gameplay masking plateau for coasts the chart does not measure.

    Low shores: the Baltic and the Arabian side of the Gulf. Everything else the game is played
    against is mountainous enough that a plateau of a few hundred metres is the honest average.
    """
    if lat0 < 60 and 10 < lon0 < 30 and lat0 > 52:
        return 80  # Baltic
    if 22 < lat0 < 31 and 46 < lon0 < 60:
        return 220  # Gulf: Zagros to the north, desert to the south, averaged
    return 450


def chart(lat0, lon0, center, extent, height_m=None):
    """Clip outside the authored chart, retaining islands and polygon topology.

    0.2 nm generalization is for performance; Natural Earth itself is 1:10m.
    It does not support harbour navigation or a claim of sub-mile accuracy.
    Heights are uniform gameplay masking plateaus, not measured terrain.
    """
    region = region_of(lat0, lon0)
    height = default_height_m(lat0, lon0) if height_m is None else height_m
    view = box(*charted_box(center, extent))
    result=[]
    for ring in dataset(region)["rings_lon_lat"]:
        source=Polygon(ring)
        local=translate(scale(source, xfact=60*math.cos(math.radians(lat0)), yfact=60, origin=(lon0,lat0)), xoff=-lon0,yoff=-lat0)
        if not local.intersects(view): continue
        clipped=local.intersection(view).simplify(.2, preserve_topology=True)
        for part in polygons(clipped):
            if part.area < .035: continue
            pts=[[round(x,4),round(y,4)] for x,y in part.exterior.coords][:-1]
            # Keep the rendered ring and collision ring identical and valid after rounding.
            if len(pts)<3 or not Polygon(pts).is_valid: raise ValueError("Invalid coastline ring")
            result.append({"id": "ne_%04d" % len(result), "name": "",
                           "elevation_m":height, "points_nm":pts})
    labels=[{"text":name,"position_nm":pos(lat,lon,lat0,lon0),"kind":kind}
            for name,lat,lon,kind in labels_for(region)]
    return result, labels


def validate_scenario(d, domain_of):
    """Fail loudly on what the runtime test would fail on: a hull ashore, an installation afloat,
    a surface or submarine patrol leg that crosses the shipped coastline polygons, an objective area
    on land. `domain_of(platform_id)` gives surface / subsurface / air / land."""
    from shapely.geometry import LineString, Point
    from shapely.strtree import STRtree
    polys = [Polygon(l["points_nm"]) for l in d["terrain"]["land"]]
    tree = STRtree(polys)

    def ashore(p):
        pt = Point(p)
        return any(polys[i].contains(pt) for i in tree.query(pt))

    def crosses(a, b):
        line = LineString([a, b])
        return any(polys[i].intersects(line) for i in tree.query(line))

    problems = []
    for u in d["units"]:
        domain = domain_of(u["platform"])
        pos = u["position_nm"]
        if domain == "land" and not ashore(pos):
            problems.append("%s is not on charted land at %s" % (u["callsign"], pos))
        if domain in ("surface", "subsurface"):
            if ashore(pos):
                problems.append("%s starts ashore at %s" % (u["callsign"], pos))
            prev = pos
            for i, leg in enumerate(u.get("patrol_nm", [])):
                if crosses(prev, leg):
                    problems.append("%s patrol leg %d %s -> %s crosses the coast" % (u["callsign"], i, prev, leg))
                prev = leg
    for kind in ("victory", "loss"):
        for o in d.get("objectives", {}).get(kind, []):
            if o.get("type") == "reach_area" and ashore(o["center_nm"]):
                problems.append("objective %s is on land" % o.get("id"))
    if problems:
        raise ValueError("%s:\n  " % d["id"] + "\n  ".join(problems))
