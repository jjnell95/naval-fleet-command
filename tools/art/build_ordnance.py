"""Ordnance gallery shapes for build_models.py.

Six abstract silhouettes for the loadout thumbnails, chosen from the game's own spec fields
(type, range band, speed band, launch profile) and drawn at gallery proportions. They are
recognition icons in the style of the existing weapon renders, not models of any real item.
Nose at +X, metres.
"""
from ordnance_bodies import slender_body
from ordnance_extra import cone_body, blunt_body
from ordnance_mounts import mount


def weapon_model(m, spec):
    kind = spec.get("type", "asm")
    words = (spec.get("family", "") + " " + spec.get("display_name", "")).lower()
    rng = float(spec.get("max_range_nm", 0.0) or 0.0)
    speed = float(spec.get("speed_kn", 0.0) or 0.0)
    lofted = "ballistic" in words or "ballistic" in str(spec.get("profile", "")).lower() or speed >= 3000.0
    if kind in ("ciws", "gun"):
        mount(m, kind, words)
        return
    if kind == "torpedo":
        rocket = "rocket" in words or "vertical" in words
        light = rocket or "light" in words or "air-launched" in words or rng <= 8.0
        L, R = (4.6, .21) if rocket else (2.8, .16) if light else (6.4, .27)
        blunt_body(m, L, R, boosted=rocket)
    elif kind == "aam":
        short = rng <= 15.0
        L, R = (3.0, .07) if short else (3.8, .10)
        slender_body(m, L, R, tail=3.6 if short else 2.6, canards=short, strakes=not short)
    elif kind == "sam":
        band = 2 if rng >= 60.0 else 1 if rng >= 15.0 else 0
        L, R = ((2.9, .08), (5.4, .18), (7.0, .25))[band]
        slender_body(m, L, R, tail=(3.4, 3.2, 2.8)[band], canards=band == 0, strakes=band > 0, booster=rng >= 100.0)
    elif lofted:
        heavy = rng >= 400.0
        L, R = (10.0, .65) if heavy else (8.6, .34)
        cone_body(m, L, R, heavy)
    elif speed >= 1000.0:
        L, R = 7.0, .30
        slender_body(m, L, R, tail=2.6, ducts=4)
    else:
        L, R = (7.6, .26) if rng >= 150.0 else (5.6, .18) if rng >= 30.0 else (3.6, .14)
        boosted = rng >= 30.0 and "air-launched" not in words and "land-attack" not in words
        slender_body(m, L, R, tail=2.6, wings=True, booster=boosted)
    bands(m, L, R)


def bands(m, L, R):
    for frac, colour in ((.20, "marking_yellow"), (-.22, "hazard_red")):
        m.cylinder(0, 0, L * frac, L * frac + L * .018, R * 1.015, 24, "band", "x", m=colour, smooth=0.0)
    m.cylinder(0, 0, -L * .501, -L * .498, R * .62, 16, "nozzle", "x", m="rubber", smooth=0.0)
