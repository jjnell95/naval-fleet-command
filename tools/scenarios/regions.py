"""Chart regions: the pieces of the world the game has geography for.

Each region is one coastline extraction (tools/scenarios/coastlines/<name>.json, build-only) and
one sea-floor raster set (data/bathymetry/<name>_*.png/.exr, shipped). Bounds are lon_min,
lat_min, lon_max, lat_max in degrees. `stereo` is the oblique stereographic centre the bathymetry
interpolation runs in; `dlon`/`dlat` are the raster cell sizes in degrees, chosen so a cell is one
to two nautical miles across the latitudes each region is played at.

The runtime table in scripts/systems/bathymetry.gd must agree with the metadata these produce;
tests/test_ocean.gd holds them together.
"""

REGIONS = {
    "north_atlantic": {
        "bounds": (-46.0, 52.0, 55.0, 81.0),
        "stereo": (66.5, 4.5),
        "dlon": 1.0 / 30.0, "dlat": 1.0 / 60.0,
        "title": "North Atlantic, Norwegian Sea, Barents Sea and Baltic",
    },
    "west_pacific": {
        "bounds": (99.0, -2.0, 152.0, 52.0),
        "stereo": (25.0, 125.0),
        "dlon": 1.0 / 24.0, "dlat": 1.0 / 48.0,
        "title": "Western Pacific: East and South China Seas, Philippine Sea, Sea of Japan",
    },
    "arabian_sea": {
        "bounds": (30.0, 8.0, 76.0, 32.0),
        "stereo": (22.0, 58.0),
        "dlon": 1.0 / 24.0, "dlat": 1.0 / 48.0,
        "title": "Persian Gulf, Gulf of Oman, Arabian Sea and Red Sea",
    },
    "mediterranean": {
        "bounds": (-7.0, 29.0, 43.0, 47.0),
        "stereo": (37.0, 18.0),
        "dlon": 1.0 / 30.0, "dlat": 1.0 / 60.0,
        "title": "Mediterranean and Black Sea approaches",
    },
}


def contains(region, lat, lon):
    lon_min, lat_min, lon_max, lat_max = REGIONS[region]["bounds"]
    return lon_min <= lon <= lon_max and lat_min <= lat <= lat_max


def region_for(lat, lon):
    """The region whose bounds hold the point with the most margin to an edge."""
    best, best_margin = None, -1.0
    for name, r in REGIONS.items():
        lon_min, lat_min, lon_max, lat_max = r["bounds"]
        margin = min(lon - lon_min, lon_max - lon, lat - lat_min, lat_max - lat)
        if margin >= 0.0 and margin > best_margin:
            best, best_margin = name, margin
    if best is None:
        raise ValueError("no chart region covers %.2f, %.2f" % (lat, lon))
    return best
