"""Real North Atlantic, Norwegian Sea, Barents Sea and Baltic geography for the scenario set.

Coordinates here are latitude/longitude of actual places. Coastlines are deliberately coarse
outlines — a few dozen vertices where a real survey has millions — but every vertex sits at a
real position, so the Kola Peninsula is where the Kola Peninsula is, Andoya is the distance from
Severomorsk that it actually is, and a strait is as wide as it actually is. That is the claim
being made and the only one: these are simplified outlines for a game chart, not survey data,
and no depth, bathymetry or shoreline detail is represented.

The game's world is flat nautical miles, so each scenario picks an anchor and everything is
projected onto a local plane around it: one minute of latitude is one nautical mile, and a
minute of longitude is scaled by the cosine of the anchor latitude. At the 100-300 nm scale of a
scenario, and at these latitudes, that is accurate to well under a mile.
"""
import math

NM_PER_DEG_LAT = 60.0


def project(lat, lon, lat0, lon0):
    """Latitude/longitude to game nautical miles, +x east, +y north, about an anchor."""
    x = (lon - lon0) * NM_PER_DEG_LAT * math.cos(math.radians(lat0))
    y = (lat - lat0) * NM_PER_DEG_LAT
    return (round(x, 2), round(y, 2))


def ring(points, lat0, lon0):
    return [list(project(lat, lon, lat0, lon0)) for lat, lon in points]


# --------------------------------------------------------------------------------------------
# Places. Bases, ports and airfields that scenarios site forces on or near.
# --------------------------------------------------------------------------------------------

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


# --------------------------------------------------------------------------------------------
# Coastlines, as closed rings of real latitude/longitude. Coarse on purpose.
# --------------------------------------------------------------------------------------------

COASTS = {}

# Kola Peninsula. North (Murman) coast west to east from the Norwegian border to Svyatoy Nos,
# then back along the White Sea side. Kola Bay, which is what Severomorsk sits on, is the notch
# at roughly 33.4E.
COASTS["kola_peninsula"] = dict(name="Kola Peninsula", elevation_m=520, points=[
    (69.78, 30.20), (69.82, 30.85), (69.71, 31.45), (69.92, 31.72), (69.96, 32.05),
    (69.75, 32.44), (69.55, 32.90), (69.34, 33.32), (69.05, 33.42), (68.90, 33.05),
    (69.08, 32.60), (69.26, 32.35), (69.38, 32.90), (69.46, 33.55), (69.30, 34.10),
    (69.19, 35.13), (69.05, 36.10), (68.72, 37.30), (68.42, 38.60), (68.15, 39.75),
    (67.60, 40.55), (67.05, 41.10), (66.60, 40.40), (66.40, 38.50), (66.55, 36.60),
    (66.80, 34.60), (67.15, 32.60), (67.60, 31.30), (68.20, 30.10), (68.90, 29.35),
    (69.40, 29.60),
])

# Northern Norway: Finnmark and Troms, from the Russian border west past North Cape to Tromso,
# then down the Lofoten wall to Bodo and inland back north along the Swedish border.
COASTS["northern_norway"] = dict(name="Northern Norway", elevation_m=760, points=[
    (69.72, 30.05), (70.37, 31.11), (70.65, 30.20), (70.92, 28.30), (70.55, 27.65),
    (70.98, 26.60), (71.17, 25.78), (70.75, 25.20), (70.90, 24.30), (70.30, 23.90),
    (70.66, 23.68), (70.55, 22.30), (70.15, 21.00), (69.98, 19.90), (69.68, 18.92),
    (69.30, 17.80), (69.29, 16.14), (68.85, 15.30), (68.40, 14.40), (68.05, 13.30),
    (67.66, 12.68), (67.45, 13.40), (67.28, 14.37), (66.95, 13.60), (66.30, 13.00),
    (65.80, 12.20), (65.30, 12.10), (65.00, 13.00), (65.60, 14.40), (66.40, 15.20),
    (67.20, 16.30), (68.10, 18.40), (68.90, 20.20), (69.30, 23.00), (69.10, 26.00),
    (69.60, 29.20),
])

# Iceland.
COASTS["iceland"] = dict(name="Iceland", elevation_m=680, points=[
    (63.81, -22.71), (63.99, -22.61), (64.15, -21.94), (64.55, -21.90), (64.70, -22.60),
    (64.87, -23.78), (65.08, -22.80), (65.50, -24.53), (65.80, -23.50), (66.10, -23.20),
    (66.45, -22.44), (66.20, -21.20), (66.15, -18.91), (66.05, -17.30), (66.36, -14.53),
    (65.60, -14.00), (64.80, -13.60), (64.25, -15.20), (63.85, -17.20), (63.42, -19.01),
    (63.50, -20.30), (63.66, -21.70),
])

# Faroe Islands, as one simplified mass.
COASTS["faroes"] = dict(name="Faroe Islands", elevation_m=520, points=[
    (61.40, -6.68), (61.50, -6.95), (62.06, -7.28), (62.30, -7.15), (62.40, -6.70),
    (62.20, -6.35), (61.80, -6.40), (61.55, -6.45),
])

# Shetland.
COASTS["shetland"] = dict(name="Shetland", elevation_m=280, points=[
    (59.85, -1.30), (60.10, -1.55), (60.40, -1.45), (60.60, -1.35), (60.80, -0.85),
    (60.55, -0.80), (60.20, -1.05), (59.90, -1.10),
])

# Orkney.
COASTS["orkney"] = dict(name="Orkney", elevation_m=180, points=[
    (58.72, -3.40), (58.90, -3.45), (59.25, -3.00), (59.20, -2.40), (58.95, -2.70),
    (58.75, -2.90),
])

# Northern Scotland, from Cape Wrath east along the Moray Firth coast.
COASTS["north_scotland"] = dict(name="Northern Scotland", elevation_m=640, points=[
    (58.63, -5.00), (58.55, -4.20), (58.60, -3.40), (58.45, -3.10), (58.00, -3.40),
    (57.71, -3.34), (57.60, -2.00), (57.20, -2.05), (56.80, -2.30), (56.60, -3.50),
    (57.00, -5.00), (57.50, -5.80), (58.20, -5.40),
])

# Outer Hebrides, simplified to one chain.
COASTS["hebrides"] = dict(name="Outer Hebrides", elevation_m=260, points=[
    (56.80, -7.55), (57.20, -7.45), (57.60, -7.30), (58.00, -7.05), (58.21, -6.32),
    (58.50, -6.20), (58.30, -6.75), (57.85, -7.15), (57.30, -7.60), (56.90, -7.70),
])

# Bear Island (Bjornoya), the lonely rock in the middle of the Barents approaches.
COASTS["bear_island"] = dict(name="Bjornoya", elevation_m=340, points=[
    (74.36, 18.95), (74.42, 18.70), (74.52, 18.80), (74.51, 19.20), (74.42, 19.25),
])

# Jan Mayen.
COASTS["jan_mayen"] = dict(name="Jan Mayen", elevation_m=1200, points=[
    (70.80, -9.10), (70.92, -9.00), (71.05, -8.30), (71.15, -7.95), (71.02, -7.90),
    (70.88, -8.55),
])

# Southern Spitsbergen, Svalbard.
COASTS["sorkapp"] = dict(name="Sorkapp, Svalbard", elevation_m=900, points=[
    (76.45, 16.00), (76.60, 15.20), (77.10, 14.60), (77.60, 14.20), (78.00, 15.20),
    (77.90, 17.20), (77.40, 18.40), (76.90, 18.20), (76.55, 17.10),
])

# Gotland.
COASTS["gotland"] = dict(name="Gotland", elevation_m=60, points=[
    (56.92, 18.16), (57.20, 18.10), (57.63, 18.30), (57.90, 18.80), (57.95, 19.10),
    (57.60, 18.95), (57.25, 18.70), (57.00, 18.50),
])

# Oland.
COASTS["oland"] = dict(name="Oland", elevation_m=40, points=[
    (56.20, 16.40), (56.60, 16.45), (57.05, 16.95), (57.36, 17.08), (57.30, 17.15),
    (56.90, 16.95), (56.50, 16.65), (56.18, 16.50),
])

# Bornholm.
COASTS["bornholm"] = dict(name="Bornholm", elevation_m=120, points=[
    (54.99, 14.70), (55.10, 14.68), (55.30, 14.78), (55.28, 15.15), (55.05, 15.10),
    (54.98, 14.90),
])

# Estonian islands, Saaremaa and Hiiumaa as one simplified mass.
COASTS["estonian_isles"] = dict(name="Saaremaa and Hiiumaa", elevation_m=50, points=[
    (57.90, 21.85), (58.20, 21.80), (58.55, 21.85), (58.95, 22.05), (59.05, 22.70),
    (58.80, 23.20), (58.45, 23.30), (58.10, 22.60), (57.95, 22.20),
])

# The eastern Baltic shore: Lithuania, Latvia and the Estonian mainland to the Gulf of Finland.
COASTS["baltic_east_shore"] = dict(name="Eastern Baltic shore", elevation_m=90, points=[
    (54.95, 21.05), (55.70, 21.07), (56.30, 21.00), (56.51, 21.01), (57.00, 21.55),
    (57.55, 21.65), (57.75, 22.60), (58.35, 24.50), (59.00, 24.10), (59.44, 24.75),
    (59.50, 26.50), (59.20, 27.40), (58.00, 27.50), (56.50, 25.00), (55.20, 22.80),
    (54.70, 21.80),
])

# The southern Baltic shore: Kaliningrad oblast, Poland and the German coast.
COASTS["baltic_south_shore"] = dict(name="Southern Baltic shore", elevation_m=60, points=[
    (54.68, 19.65), (54.65, 19.91), (54.40, 19.40), (54.35, 18.65), (54.75, 18.55),
    (54.83, 17.50), (54.60, 16.85), (54.20, 15.60), (54.05, 14.25), (54.15, 12.10),
    (53.90, 11.00), (53.60, 12.50), (53.50, 15.00), (53.80, 17.50), (54.00, 20.00),
    (54.40, 20.60),
])

# Southern Sweden.
COASTS["south_sweden"] = dict(name="Southern Sweden", elevation_m=140, points=[
    (55.34, 12.85), (55.43, 13.82), (55.65, 14.35), (56.16, 15.59), (56.65, 16.30),
    (57.30, 16.65), (57.90, 16.80), (58.40, 17.00), (58.70, 17.60), (58.60, 16.00),
    (58.00, 14.50), (57.00, 13.20), (56.20, 12.75), (55.60, 12.70),
])

# The Norwegian coast from Stad north to the Lofoten wall: the inner lead the group's flank
# rests on in the Norwegian Sea scenarios.
COASTS["mid_norway"] = dict(name="Mid-Norway coast", elevation_m=700, points=[
    (62.00, 5.10), (62.60, 5.70), (63.10, 7.20), (63.45, 8.10), (63.70, 9.60),
    (64.00, 10.30), (64.50, 11.20), (65.00, 12.10), (65.60, 12.20), (66.30, 13.00),
    (66.95, 13.60), (67.28, 14.37), (67.10, 15.60), (66.50, 15.40), (65.60, 14.50),
    (64.60, 13.60), (63.60, 12.30), (62.80, 11.00), (62.10, 9.50), (61.60, 7.00),
    (61.70, 5.20),
])

# Greenland's south-east coast, the far side of the Denmark Strait.
COASTS["east_greenland"] = dict(name="South-east Greenland", elevation_m=1600, points=[
    (59.78, -43.92), (61.00, -42.50), (62.50, -41.60), (64.00, -40.20), (65.61, -37.64),
    (66.80, -35.50), (68.00, -32.00), (69.20, -26.50), (70.48, -21.97), (70.90, -24.00),
    (70.00, -28.00), (68.50, -33.00), (66.50, -38.00), (64.50, -42.00), (62.00, -45.00),
    (60.20, -46.00),
])


def landmass(key, lat0, lon0):
    c = COASTS[key]
    return {
        "id": key,
        "name": c["name"],
        "elevation_m": c["elevation_m"],
        "points_nm": ring(c["points"], lat0, lon0),
    }


def at(place, lat0, lon0, bearing_deg=None, offset_nm=0.0):
    """A real place in game coordinates, optionally offset (to put a ship off a port, say)."""
    lat, lon = PLACES[place]
    x, y = project(lat, lon, lat0, lon0)
    if bearing_deg is not None and offset_nm:
        r = math.radians(bearing_deg)
        x += math.sin(r) * offset_nm
        y += math.cos(r) * offset_nm
    return [round(x, 2), round(y, 2)]


def pos(lat, lon, lat0, lon0):
    return list(project(lat, lon, lat0, lon0))
