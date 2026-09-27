#!/usr/bin/env python3
"""Build the runtime GLB models for the 2027 theatre catalogue without Blender.

    python3 tools/art/build_models.py                 # every id in data/theatres_2027_manifest.json
    python3 tools/art/build_models.py pla_ddg_type055 pla_yj18

Each platform in data/platforms and weapon in data/weapons named in the manifest gets an
original, stylised recognition model built from primitives (tools/art/artkit.py), sized from
its spec (length, mast height) and a small table of class proportions. The GLB is written to
assets/models/<id>.glb centred and normalised to ten units, assets/models/manifest.json gains
its {id, kind, triangles} row, and tools/art/render_manifest.json records what
tools/art/render_assets.gd needs to frame it (domain and the waterline height).

These are evocations of a class for a command display, not blueprints or engineering models;
no external meshes or drawings are used. Two ids share a donor's geometry and renders (the Air
Self-Defense Force F-35B and the Iranian Kilo), copied here under the new id.
"""
import json
import math
import os
import re
import shutil
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from artkit import Model, split_hull_materials, SMOOTH  # noqa: E402
import build_air_weapons as aw  # noqa: E402

ROOT = HERE.parent.parent
DATA = ROOT / "data"
MODELS = ROOT / "assets" / "models"
PLATFORM_ART = ROOT / "assets" / "platforms"
WEAPON_ART = ROOT / "assets" / "weapons"
SIDECAR = HERE / "render_manifest.json"
NEW_RECORDS = DATA / "theatres_2027_manifest.json"
COPIES = {"jasdf_fighter_f35b": "rn_fighter_f35b", "irn_ssk_kilo_877ekm": "rfn_ssk_kilo_877"}
TRIANGLE_BUDGET = 25000


# --------------------------------------------------------------------------------------------
# Specs
# --------------------------------------------------------------------------------------------


def read_tres(path):
    text = path.read_text()
    fields = {}
    for key, value in re.findall(r"^(\w+) = (.*)$", text, re.M):
        value = value.strip()
        if value.startswith('"'):
            fields[key] = value.strip('"')
        else:
            try:
                fields[key] = float(value)
            except ValueError:
                fields[key] = value
    return fields


def platform_specs():
    specs = {}
    for path in sorted(DATA.glob("platforms/**/*.tres")):
        f = read_tres(path)
        sid = f.get("id", path.stem)
        specs[sid] = {
            "id": sid,
            "category": str(f.get("category", "")).lower(),
            "domain": str(f.get("domain", "surface")),
            "length_m": float(f.get("length_m", 0.0) or 0.0),
            "displacement_t": float(f.get("displacement_t", 0.0) or 0.0),
            "mast_height_m": float(f.get("mast_height_m", 25.0) or 25.0),
            "nation": str(f.get("nation", "")),
            "display_name": str(f.get("display_name", sid)),
            "aviation_facility": str(f.get("aviation_facility", "auto")),
        }
    return specs


def weapon_specs():
    specs = {}
    for path in sorted(DATA.glob("weapons/*.tres")):
        f = read_tres(path)
        sid = f.get("id", path.stem)
        specs[sid] = {
            "id": sid,
            "type": str(f.get("type", "asm")),
            "family": str(f.get("family", "")),
            "display_name": str(f.get("display_name", sid)),
            "max_range_nm": float(f.get("max_range_nm", 0.0) or 0.0),
            "speed_kn": float(f.get("speed_kn", 0.0) or 0.0),
            "profile": str(f.get("profile", "")),
        }
    return specs


# --------------------------------------------------------------------------------------------
# Surface-ship scaffolding
# --------------------------------------------------------------------------------------------


class Ship:
    """A lofted hull with the station helpers the class builders use."""

    def __init__(self, m, L, B, draft, fa, ff, **hull_kwargs):
        self.m, self.L, self.B, self.draft, self.fa, self.ff = m, L, B, draft, fa, ff
        self.hull_part = m.hull(L, B, draft, fa, ff, **hull_kwargs)
        self.hull_parts = [self.hull_part]

    def x(self, t):
        return self.L * (t - .5)

    def d(self, t):
        return Model.deck_z(self.fa, self.ff, t)


def finish_surface(m, ship, spec, deck="deck_non_skid", railings=True):
    """The presentation finish: hull material split, guardrails, bridge glazing, VLS hatch
    grids, stack exhausts and hangar doors. Names given at build time drive it."""
    for hull in ship.hull_parts:
        split_hull_materials(hull, ship.draft, deck_material=deck)
    if railings:
        add_railings(m, ship)
    for p in list(m.parts):
        lo, hi = p.bounds()
        dim = hi - lo
        if p.name in ("bridge", "island", "accommodation", "bridge_glazed"):
            add_glazing(m, p, lo, hi, dim)
        elif p.name == "vls":
            nx, ny = max(2, round(dim[0] / 1.5)), max(2, round(dim[1] / 1.35))
            for ix in range(nx):
                for iy in range(ny):
                    x0, y0 = lo[0] + ix * dim[0] / nx + .09, lo[1] + iy * dim[1] / ny + .09
                    m.box(x0, x0 + dim[0] / nx - .18, y0, y0 + dim[1] / ny - .18, hi[2] + .01, hi[2] + .06, "cell_hatch", "array_face")
        elif p.name == "funnel":
            m.box(lo[0] + .3, hi[0] - .3, lo[1] + .3, hi[1] - .3, hi[2] - .01, hi[2] + .05, "stack_exhaust", "rubber")
        elif p.name == "hangar":
            doors = 2 if dim[1] > 13 else 1
            for k in range(doors):
                cy = (lo[1] + hi[1]) * .5 + (k - (doors - 1) / 2) * dim[1] * .46
                hw = dim[1] * (.18 if doors == 2 else .3)
                m.box(lo[0] - .05, lo[0] - .02, cy - hw, cy + hw, lo[2] + .2, hi[2] - .8, "hangar_door", "deck_non_skid")
                for i in range(6):
                    m.box(lo[0] - .07, lo[0] - .05, cy - hw, cy + hw, lo[2] + .5 + i * .7, lo[2] + .55 + i * .7, "door_seam", "naval_paint")


def add_glazing(m, p, lo, hi, dim):
    inset = getattr(p, "inset", 0.0)
    frac = (hi[2] - .95 - lo[2]) / max(dim[2], 1e-6)
    off = inset * frac
    for sign in (-1, 1):
        yy = hi[1] - off + .015 if sign > 0 else lo[1] + off - .015
        count = max(3, int(dim[0] / 1.6))
        for i in range(count):
            xx = lo[0] + .8 + i * (dim[0] - 1.6) / count
            m.box(xx, xx + .92, yy - .02, yy + .02, hi[2] - 1.38, hi[2] - .50, "bridge_window", "glazing")
    count = max(3, int(dim[1] / 1.5))
    for i in range(count):
        yy = lo[1] + off + .65 + i * (dim[1] - 2 * off - 1.3) / count
        m.box(hi[0] - off + .015, hi[0] - off + .04, yy, yy + .8, hi[2] - 1.38, hi[2] - .50, "bridge_window", "glazing")


def add_railings(m, ship, step=2):
    hull = ship.hull_part
    rings = len(hull.verts) // 12
    for idx in (5, 7):
        points = []
        for i in range(rings):
            v = hull.verts[i * 12 + idx].copy()
            v[1] *= .99
            points.append(v)
        for i in range(0, len(points) - step, step):
            a, c = points[i], points[i + step]
            for z in (.52, 1.03):
                m.rod(a + np.array((0, 0, z)), c + np.array((0, 0, z)), .035, "railing", "naval_paint", segs=4)
            m.rod(a, a + np.array((0, 0, 1.05)), .045, "railing", "naval_paint", segs=4)


def helipad(m, x, y, z, r, marks="H"):
    m.box(x - r * 1.1, x + r * 1.1, y - r * 1.1, y + r * 1.1, z - .1, z, "landing_pad", "deck_non_skid")
    m.circle(x, y, z + .018, r)
    if marks == "H":
        for yy in (-r * .28, r * .28):
            m.stripe((x - r * .38, y + yy, z + .025), (x + r * .38, y + yy, z + .025), .24)
        m.stripe((x, y - r * .28, z + .026), (x, y + r * .28, z + .026), .24)
    m.stripe((x - r * .9, y, z + .027), (x + r * .9, y, z + .027), .09, "marking_yellow")


def bulbous_bow(m, ship, r=None):
    L = ship.L
    r = r or ship.B * .08
    m.ellipsoid(L * .5 - r * 2.7, 0, -ship.draft * .62, r * 3.2, r, r * .9, 12, 6, "bulb", "antifouling")


def liferafts(m, ship, ts, y, z):
    for t in ts:
        for sign in (-1, 1):
            m.cylinder(ship.x(t), sign * y, z, z + .8, .52, 10, "liferaft", m="naval_paint")


def sensor_box(m, x, y, z, w=1.2, d=1.2, h=1.2, m_name="array_face"):
    return m.cbox(x, y, z + h / 2, d, w, h, "sensor", m_name)


def enclosed_mast(m, x, y, z0, z1, base_x, base_y, top_x, top_y, name="integrated_mast", m_name=None):
    """A faceted tower tapering from a rectangular base to a smaller top."""
    verts = [(x - base_x / 2, y - base_y / 2, z0), (x + base_x / 2, y - base_y / 2, z0),
             (x + base_x / 2, y + base_y / 2, z0), (x - base_x / 2, y + base_y / 2, z0),
             (x - top_x / 2, y - top_y / 2, z1), (x + top_x / 2, y - top_y / 2, z1),
             (x + top_x / 2, y + top_y / 2, z1), (x - top_x / 2, y + top_y / 2, z1)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return m.add(name, verts, faces, m_name)


def rotating_radar(m, x, y, z, width=4.0, height=1.2, m_name="array_face"):
    m.cylinder(x, y, z, z + .5, .35, 8, "pedestal", m="naval_paint")
    m.cbox(x, y, z + .5 + height / 2, .5, width, height, "search_array", m_name)


def canister_pack(m, x, y, z, count, length, radius, heading=0.0, incline=.20, m_name=None, stack=True):
    return m.canisters(x, y, z, count, length, radius, incline, m_name, heading, stack)


def box_launcher(m, x, y, z, cells_x, cells_y, cell, length, heading=0.0, incline=.25, m_name=None):
    """Square launch boxes in a raised rack, like a coastal battery's or a fast craft's cells."""
    mark = m.mark()
    w = cells_y * cell
    h = cells_x * cell
    m.cbox(0, 0, h / 2, length, w, h, "launch_box", m_name)
    for ix in range(cells_x):
        for iy in range(cells_y):
            yy = (iy - (cells_y - 1) / 2) * cell
            zz = ix * cell + cell / 2
            m.box(length / 2 - .02, length / 2 + .08, yy - cell * .4, yy + cell * .4, zz - cell * .4, zz + cell * .4, "cell_cap", "rubber")
    parts = m.since(mark)
    for p in parts:
        p.rotate((0, 1, 0), -incline)
        if heading:
            p.rotate((0, 0, 1), heading)
        p.translate((x, y, z))
    return parts


# --------------------------------------------------------------------------------------------
# PLAN and JMSDF surface combatants
# --------------------------------------------------------------------------------------------


def build_type055(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 20.0, 6.6, 7.6, 11.8
    s = Ship(m, L, B, dr, fa, ff, stations=44, transom=.80, fullness=.50, flare=1.0, bow_power=2.1)
    x, d = s.x, s.d
    bulbous_bow(m, s)
    # A long flush hull carrying two faceted blocks; the forward one wears the four big arrays
    # and the enclosed mast, the aft one folds the funnel into a hangar for two helicopters.
    m.prism(x(.40), x(.66), -B * .44, B * .44, d(.53), d(.53) + 7.0, .9, "deckhouse")
    m.prism(x(.50), x(.65), -B * .38, B * .38, d(.53) + 7.0, d(.53) + 11.5, .6, "bridge")
    p = m.prism(x(.51), x(.60), -4.4, 4.4, d(.53) + 11.5, d(.53) + 27.5, 1.6, "integrated_mast")
    m.cbox(x(.555), 0, d(.53) + 28.6, 5.0, 5.0, 2.2, "mast_top", "array_face")
    m.mast(x(.555), 0, d(.53) + 29.7, spec["mast_height_m"] + 1.5, .22)
    for sign in (-1, 1):
        m.radar_face(x(.61), sign * B * .44, d(.53) + 1.6, 5.2, 5.2, sign)
        m.radar_face(x(.445), sign * B * .44, d(.53) + 1.6, 5.2, 5.2, sign)
        for zz, ww in ((d(.53) + 13.5, 3.0), (d(.53) + 20.5, 2.2)):
            m.radar_face(x(.555), sign * (4.4 - (zz - d(.53) - 11.5) / 16.0 * 1.6), zz, ww, ww, sign)
    m.prism(x(.16), x(.38), -B * .42, B * .42, d(.30), d(.30) + 6.8, .8, "hangar")
    m.prism(x(.30), x(.38), -B * .30, B * .30, d(.30) + 6.8, d(.30) + 11.0, .9, "aft_block")
    m.funnel(x(.345), 0, d(.30) + 11.0, 1.8, 4.6, 5.0, -.3)
    m.prism(x(.24), x(.29), -2.6, 2.6, d(.30) + 6.8, d(.30) + 16.5, 1.3, "aft_mast")
    m.cbox(x(.265), 0, d(.30) + 17.2, 1.2, 6.0, 1.6, "search_array", "array_face")
    m.gun(x(.83), 0, d(.83), big=True, stealth=True)
    m.vls(x(.675), x(.78), 0, d(.72) + .4, B * .58)
    m.vls(x(.40), x(.475), 0, d(.42) + .4, B * .55)
    m.ciws(x(.66), 0, d(.53) + 11.5)
    m.ciws(x(.19), 0, d(.30) + 6.8)
    m.cbox(x(.66), 0, d(.53) + 7.6, 2.2, 3.0, 1.2, "hhq10", "naval_paint")
    helipad(m, x(.075), 0, d(.075) + .12, min(B * .30, L * .05))
    liferafts(m, s, (.20, .27, .43, .58), B * .40, d(.3) + 7.0)
    finish_surface(m, s, spec)


def build_type052d(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 17.8, 6.2, 6.4, 10.2
    s = Ship(m, L, B, dr, fa, ff, stations=40, transom=.76, fullness=.52, flare=1.01)
    x, d = s.x, s.d
    bulbous_bow(m, s)
    m.prism(x(.44), x(.65), -B * .43, B * .43, d(.53), d(.53) + 6.5, .7, "deckhouse")
    m.prism(x(.51), x(.64), -B * .36, B * .36, d(.53) + 6.5, d(.53) + 10.5, .5, "bridge")
    for sign in (-1, 1):
        m.radar_face(x(.60), sign * B * .43, d(.53) + 1.4, 4.4, 4.4, sign)
        m.radar_face(x(.47), sign * B * .43, d(.53) + 1.4, 4.4, 4.4, sign)
    # A tapered enclosed mast with a lattice top, then the tall slab-sided funnel.
    m.prism(x(.53), x(.59), -3.2, 3.2, d(.53) + 10.5, d(.53) + 20.0, 1.4, "pyramid_mast")
    m.lattice_mast(x(.56), 0, d(.53) + 20.0, spec["mast_height_m"] - 1.0, 2.6, .9)
    m.cbox(x(.56), 0, spec["mast_height_m"], 1.0, 5.0, 1.4, "search_array", "array_face")
    m.prism(x(.34), x(.43), -B * .36, B * .36, d(.40), d(.40) + 6.5, .6, "midhouse")
    m.funnel(x(.385), 0, d(.40) + 6.5, 6.0, 4.8, 6.4, -.4)
    m.prism(x(.24), x(.30), -2.4, 2.4, d(.40) + 6.5, d(.40) + 16.0, 1.2, "aft_mast")
    m.cbox(x(.27), 0, d(.40) + 16.8, 1.1, 5.0, 1.4, "search_array", "array_face")
    m.hangar(x(.11), x(.245), B * .80, d(.18), 6.0)
    m.gun(x(.82), 0, d(.82), big=True, stealth=True)
    m.vls(x(.68), x(.76), 0, d(.72) + .4, B * .52)
    m.vls(x(.245), x(.325), 0, d(.28) + .4, B * .52)
    m.ciws(x(.66), 0, d(.53) + 6.5)
    m.cbox(x(.14), 0, d(.18) + 6.6, 2.2, 3.0, 1.2, "hhq10", "naval_paint")
    for sign in (-1, 1):
        m.boat(x(.30), sign * B * .40, d(.32) + 2.5)
    helipad(m, x(.055), 0, d(.055) + .12, min(B * .30, L * .05))
    liferafts(m, s, (.22, .32, .47), B * .40, d(.4) + 6.7)
    finish_surface(m, s, spec)


def build_maya(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 21.0, 6.4, 5.4, 8.6
    s = Ship(m, L, B, dr, fa, ff, stations=44, transom=.78, fullness=.52, flare=1.02)
    x, d = s.x, s.d
    bulbous_bow(m, s)
    # Aegis deckhouse: four fixed arrays on a larger hull than a Burke, twin stacks, one hangar.
    m.prism(x(.46), x(.67), -B * .42, B * .42, d(.56), d(.56) + 7.4, .7, "deckhouse")
    m.prism(x(.54), x(.66), -B * .33, B * .33, d(.56) + 7.4, d(.56) + 10.6, .4, "bridge")
    m.prism(x(.33), x(.46), -B * .36, B * .36, d(.42), d(.42) + 5.8, .6, "midhouse")
    m.hangar(x(.14), x(.32), B, d(.24), 5.9)
    for sign in (-1, 1):
        m.radar_face(x(.645), sign * B * .42, d(.56) + 1.6, 4.4, 4.4, sign)
        m.radar_face(x(.475), sign * B * .42, d(.56) + 1.6, 4.4, 4.4, sign)
        m.boat(x(.44), sign * B * .43, d(.45) + 2.0)
    m.prism(x(.555), x(.60), -2.2, 2.2, d(.56) + 10.6, d(.56) + 20.5, 1.0, "mast_tower")
    m.lattice_mast(x(.58), 0, d(.56) + 20.5, spec["mast_height_m"] - 1.0, 2.2, .8)
    m.cbox(x(.58), 0, spec["mast_height_m"], .9, 4.6, 1.2, "search_array", "array_face")
    m.funnel(x(.44), 0, d(.42) + 5.8, 4.8, 4.2, 5.2, -.5)
    m.funnel(x(.355), 0, d(.42) + 5.8, 4.8, 4.2, 5.2, -.5)
    m.mast(x(.36), 0, d(.42) + 10.6, d(.42) + 22.0, .28, 4.5)
    m.gun(x(.82), 0, d(.82), big=True)
    m.vls(x(.69), x(.75), 0, d(.72) + .4, B * .40)
    m.vls(x(.20), x(.30), 0, d(.24) + 6.1, B * .50)
    m.ciws(x(.64), 0, d(.56) + 10.6)
    m.ciws(x(.17), 0, d(.24) + 5.9)
    for sign in (-1, 1):
        canister_pack(m, x(.395), sign * B * .28, d(.42) + 5.9, 4, 4.8, .30, heading=sign * .18)
    helipad(m, x(.07), 0, d(.07) + .12, min(B * .30, L * .05))
    liferafts(m, s, (.18, .26, .40, .50), B * .41, d(.4) + 6.0)
    finish_surface(m, s, spec)


def build_akizuki(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 18.3, 5.4, 4.8, 8.2
    s = Ship(m, L, B, dr, fa, ff, stations=40, transom=.76, fullness=.53, flare=1.0)
    x, d = s.x, s.d
    # A tall deckhouse wearing the FCS-3A panels high on its forward corners, one enclosed mast
    # behind the bridge, a single stack, and the aft panels on the hangar block.
    m.prism(x(.44), x(.67), -B * .43, B * .43, d(.54), d(.54) + 6.6, .8, "deckhouse")
    m.prism(x(.50), x(.64), -B * .36, B * .36, d(.54) + 6.6, d(.54) + 11.4, .6, "bridge")
    for sign in (-1, 1):
        m.radar_face(x(.61), sign * B * .36, d(.54) + 7.6, 3.4, 3.2, sign)
        m.front_array(x(.64), sign * 3.4, d(.54) + 7.6, 3.4, 3.2, 1)
    m.prism(x(.52), x(.58), -2.8, 2.8, d(.54) + 11.4, d(.54) + 22.0, 1.4, "pyramid_mast")
    m.mast(x(.55), 0, d(.54) + 22.0, spec["mast_height_m"] + .5, .25, 4.0)
    m.prism(x(.33), x(.44), -B * .34, B * .34, d(.40), d(.40) + 6.0, .6, "midhouse")
    m.funnel(x(.395), 0, d(.40) + 6.0, 5.6, 4.6, 6.0, -.5)
    m.hangar(x(.12), x(.30), B, d(.22), 6.4)
    m.prism(x(.24), x(.30), -B * .26, B * .26, d(.22) + 6.4, d(.22) + 9.6, .4, "aft_block")
    for sign in (-1, 1):
        m.radar_face(x(.28), sign * B * .26, d(.22) + 6.6, 3.0, 2.8, sign)
        m.boat(x(.36), sign * B * .43, d(.38) + 1.5)
        canister_pack(m, x(.32), sign * B * .27, d(.40) + 6.1, 4, 4.8, .30, heading=sign * .20)
    m.gun(x(.82), 0, d(.82), big=True, stealth=True)
    m.vls(x(.70), x(.76), 0, d(.72) + .4, B * .44)
    m.ciws(x(.64), 0, d(.54) + 11.4)
    m.ciws(x(.15), 0, d(.22) + 6.4)
    helipad(m, x(.06), 0, d(.06) + .12, min(B * .30, L * .05))
    liferafts(m, s, (.20, .30, .48), B * .41, d(.4) + 6.2)
    finish_surface(m, s, spec)


def build_type054a(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 16.0, 4.6, 4.6, 7.6
    s = Ship(m, L, B, dr, fa, ff, stations=38, transom=.74, fullness=.54, flare=1.0)
    x, d = s.x, s.d
    # A conventional frigate: gun, forward VLS, bridge, tandem stacks with the canisters
    # between them, a hangar carrying the close-in mounts.
    m.prism(x(.44), x(.66), -B * .42, B * .42, d(.52), d(.52) + 5.8, .7, "deckhouse")
    m.prism(x(.51), x(.65), -B * .36, B * .36, d(.52) + 5.8, d(.52) + 9.6, .5, "bridge")
    m.prism(x(.52), x(.58), -2.4, 2.4, d(.52) + 9.6, d(.52) + 16.5, 1.0, "pyramid_mast")
    m.lattice_mast(x(.55), 0, d(.52) + 16.5, spec["mast_height_m"] - 1.0, 2.2, .8)
    m.cbox(x(.55), 0, spec["mast_height_m"], .9, 4.4, 1.3, "search_array", "array_face")
    m.sphere(x(.62), 0, d(.52) + 10.8, 1.0)
    m.prism(x(.28), x(.44), -B * .38, B * .38, d(.38), d(.38) + 5.6, .6, "midhouse")
    m.funnel(x(.41), 0, d(.38) + 5.6, 4.6, 4.0, 4.8, -.4)
    m.funnel(x(.31), 0, d(.38) + 5.6, 4.6, 4.0, 4.8, -.4)
    m.lattice_mast(x(.34), 0, d(.38) + 5.6, d(.38) + 15.0, 2.6, .9)
    m.cbox(x(.34), 0, d(.38) + 15.6, .8, 3.6, 1.2, "search_array", "array_face")
    for sign in (-1, 1):
        canister_pack(m, x(.36), sign * B * .24, d(.38) + 5.7, 4, 6.0, .42, heading=sign * .22)
        m.boat(x(.47), sign * B * .43, d(.48) + 1.2)
    m.hangar(x(.12), x(.28), B, d(.20), 5.6)
    m.ciws(x(.22), -B * .30, d(.20) + 5.6)
    m.ciws(x(.22), B * .30, d(.20) + 5.6)
    m.gun(x(.82), 0, d(.82), big=False, stealth=True)
    m.vls(x(.70), x(.77), 0, d(.73) + .4, B * .46)
    helipad(m, x(.055), 0, d(.055) + .12, min(B * .30, L * .05))
    liferafts(m, s, (.24, .33, .50), B * .40, d(.4) + 5.8)
    finish_surface(m, s, spec)


def build_mogami(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 16.3, 4.7, 5.6, 8.4
    s = Ship(m, L, B, dr, fa, ff, stations=40, transom=.82, fullness=.56, flare=.92, bow_power=2.3)
    x, d = s.x, s.d
    # Clean stealth shaping: tumblehome topsides, one long faceted deckhouse, one tall unicorn
    # mast and almost no fittings on deck.
    m.prism(x(.22), x(.68), -B * .40, B * .40, d(.48), d(.48) + 6.4, 1.6, "deckhouse")
    m.prism(x(.48), x(.66), -B * .30, B * .30, d(.48) + 6.4, d(.48) + 10.2, 1.0, "bridge")
    m.prism(x(.50), x(.58), -2.8, 2.8, d(.48) + 10.2, d(.48) + 20.0, 1.7, "integrated_mast")
    m.cylinder(x(.54), 0, d(.48) + 20.0, spec["mast_height_m"] - 1.0, .55, 10, "unicorn", m="naval_paint", r_top=.30)
    m.sphere(x(.54), 0, spec["mast_height_m"] - .4, .7)
    for sign in (-1, 1):
        m.radar_face(x(.565), sign * 2.5, d(.48) + 12.0, 2.6, 2.6, sign)
    m.prism(x(.36), x(.42), -2.4, 2.4, d(.48) + 6.4, d(.48) + 9.0, .5, "stack")
    m.prism(x(.22), x(.34), -B * .30, B * .30, d(.48) + 6.4, d(.48) + 8.6, .6, "hangar_top")
    m.cylinder(x(.25), 0, d(.48) + 8.6, d(.48) + 10.0, 1.0, 8, "ciws", m="naval_paint")
    m.dome(x(.25), 0, d(.48) + 10.0, 1.05)
    m.gun(x(.80), 0, d(.80), big=True, stealth=True)
    m.vls(x(.68), x(.73), 0, d(.70) + .35, B * .34)
    helipad(m, x(.07), 0, d(.07) + .12, min(B * .30, L * .05))
    finish_surface(m, s, spec, railings=False)


def build_moudge(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 11.1, 3.3, 2.9, 5.2
    s = Ship(m, L, B, dr, fa, ff, stations=34, transom=.70, fullness=.52)
    x, d = s.x, s.d
    # A small conventional frigate: gun, boxy bridge, lattice mast, one stack, four canisters
    # abaft the funnel and an open landing deck at the stern.
    m.box(x(.40), x(.66), -B * .38, B * .38, d(.52), d(.52) + 4.4, "deckhouse")
    m.box(x(.52), x(.65), -B * .34, B * .34, d(.52) + 4.4, d(.52) + 7.2, "bridge")
    m.dome(x(.60), 0, d(.52) + 7.2, 1.0)
    m.lattice_mast(x(.54), 0, d(.52) + 7.2, spec["mast_height_m"] - 1.0, 2.6, .9)
    m.cbox(x(.54), 0, spec["mast_height_m"], .8, 3.4, 1.1, "search_array", "array_face")
    m.funnel(x(.42), 0, d(.52) + 4.4, 4.6, 2.6, 3.6, -.7)
    m.box(x(.26), x(.40), -B * .34, B * .34, d(.36), d(.36) + 3.6, "midhouse")
    for sign in (-1, 1):
        canister_pack(m, x(.33), sign * B * .18, d(.36) + 3.7, 2, 6.2, .40, heading=sign * .16, stack=False)
    m.gun(x(.80), 0, d(.80), big=False)
    m.gun(x(.20), 0, d(.20), big=False, twin=True)
    helipad(m, x(.07), 0, d(.07) + .12, min(B * .32, L * .05), marks="")
    liferafts(m, s, (.34, .48), B * .39, d(.45) + 4.5)
    finish_surface(m, s, spec)


def build_alvand(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 11.1, 3.4, 2.6, 5.4
    s = Ship(m, L, B, dr, fa, ff, stations=34, transom=.66, fullness=.50)
    x, d = s.x, s.d
    # A 1970s Vosper: rounded 4.5-inch turret forward, tall bridge with a flying bridge, a
    # lattice foremast, one raked funnel, a lattice mainmast and quad canisters aft.
    m.box(x(.36), x(.66), -B * .38, B * .38, d(.50), d(.50) + 4.2, "deckhouse")
    m.box(x(.52), x(.64), -B * .34, B * .34, d(.50) + 4.2, d(.50) + 7.0, "bridge")
    m.box(x(.54), x(.63), -B * .26, B * .26, d(.50) + 7.0, d(.50) + 8.2, "flying_bridge")
    m.lattice_mast(x(.50), 0, d(.50) + 7.0, spec["mast_height_m"] - 1.0, 3.0, 1.0)
    m.cbox(x(.50), 0, spec["mast_height_m"], .8, 3.6, 1.2, "search_array", "array_face")
    m.dome(x(.60), 0, d(.50) + 8.2, .8)
    m.funnel(x(.40), 0, d(.50) + 4.2, 5.4, 2.4, 3.8, -1.4)
    m.lattice_mast(x(.31), 0, d(.40) + 4.2, d(.40) + 13.0, 2.4, .8)
    m.box(x(.24), x(.36), -B * .34, B * .34, d(.34), d(.34) + 3.4, "midhouse")
    for sign in (-1, 1):
        canister_pack(m, x(.28), sign * B * .16, d(.34) + 3.5, 2, 6.2, .40, heading=sign * .20, stack=False)
    m.cylinder(x(.82), 0, d(.82), d(.82) + 1.0, 2.4, 12, "barbette", m="naval_paint")
    m.ellipsoid(x(.82), 0, d(.82) + 1.0, 3.2, 2.4, 2.2, 12, 5, "turret", "naval_paint")
    m.cylinder(0, d(.82) + 1.9, x(.82) + 2.0, x(.82) + 8.6, .18, 8, "barrel", "x", m="titanium")
    m.cylinder(x(.12), 0, d(.12), d(.12) + 1.6, 1.0, 8, "pedestal", m="naval_paint")
    m.cbox(x(.12), 0, d(.12) + 2.2, 1.6, 2.4, 1.0, "sam_launcher", "naval_paint")
    liferafts(m, s, (.30, .44), B * .39, d(.45) + 4.3)
    finish_surface(m, s, spec)


def build_type056a(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 11.1, 4.0, 3.4, 5.8
    s = Ship(m, L, B, dr, fa, ff, stations=34, transom=.78, fullness=.54, flare=.98)
    x, d = s.x, s.d
    # A compact corvette: gun forward, one boxy superstructure with a short mast, canisters
    # amidships, a point-defence box aft over an open landing deck.
    m.prism(x(.36), x(.66), -B * .40, B * .40, d(.50), d(.50) + 4.6, .7, "deckhouse")
    m.prism(x(.50), x(.64), -B * .34, B * .34, d(.50) + 4.6, d(.50) + 7.4, .5, "bridge")
    m.prism(x(.52), x(.57), -2.0, 2.0, d(.50) + 7.4, d(.50) + 13.0, .9, "pyramid_mast")
    m.lattice_mast(x(.545), 0, d(.50) + 13.0, spec["mast_height_m"] - 1.0, 1.8, .7)
    m.cbox(x(.545), 0, spec["mast_height_m"], .7, 3.2, 1.0, "search_array", "array_face")
    m.prism(x(.40), x(.44), -1.8, 1.8, d(.50) + 4.6, d(.50) + 7.0, .4, "stack")
    for sign in (-1, 1):
        canister_pack(m, x(.36), sign * B * .18, d(.50) + 4.7, 2, 6.0, .40, heading=sign * .18, stack=False)
        m.cylinder(x(.58), sign * B * .34, d(.50) + 4.6, d(.50) + 5.4, .5, 8, "gun_mount", m="naval_paint")
        m.cylinder(sign * B * .34, d(.50) + 5.2, x(.58), x(.58) + 2.6, .08, 6, "barrel", "x", m="titanium")
    m.prism(x(.22), x(.36), -B * .32, B * .32, d(.30), d(.30) + 3.6, .5, "aft_house")
    m.cbox(x(.27), 0, d(.30) + 4.4, 2.2, 3.0, 1.4, "hhq10", "naval_paint")
    m.gun(x(.81), 0, d(.81), big=False, stealth=True)
    helipad(m, x(.08), 0, d(.08) + .12, min(B * .32, L * .05), marks="")
    m.box(x(0.0) - .2, x(0.0) + .6, -1.6, 1.6, d(.0) - 2.4, d(.0) - .6, "towed_array_door", "deck_non_skid")
    liferafts(m, s, (.30, .46), B * .40, d(.45) + 4.7)
    finish_surface(m, s, spec)


# --------------------------------------------------------------------------------------------
# Fast craft
# --------------------------------------------------------------------------------------------


def build_type022(m, spec):
    L = spec["length_m"]
    B, hull_b, dr = 12.2, 2.6, 1.5
    fa, ff = 2.6, 3.4
    s = None
    hulls = []
    for sign in (-1, 1):
        hull = m.hull(L, hull_b, dr, fa, ff, stations=30, transom=.85, fullness=.55, flare=1.0, bow_power=1.4,
                      y_offset=sign * (B / 2 - hull_b / 2), name="hull")
        hulls.append(hull)
    s = Ship.__new__(Ship)
    s.m, s.L, s.B, s.draft, s.fa, s.ff = m, L, B, dr, fa, ff
    s.hull_part, s.hull_parts = hulls[0], hulls
    x, d = s.x, s.d
    # A wave-piercing catamaran: two slender hulls under one angular bridging deck, a low
    # faceted house, eight covered missile cells aft and a shrouded close-in gun forward.
    m.prism(x(.06), x(.86), -B * .5 + .2, B * .5 - .2, 1.4, d(.5) + .4, .0, "cross_deck")
    m.wedge(x(.86), x(.97), -B * .5 + .2, B * .5 - .2, 1.4, d(.5) + .4, "bow_deck", forward=False)
    m.prism(x(.30), x(.68), -B * .40, B * .40, d(.5) + .4, d(.5) + 3.2, 1.0, "deckhouse")
    m.prism(x(.40), x(.62), -B * .28, B * .28, d(.5) + 3.2, d(.5) + 5.4, .8, "bridge")
    m.prism(x(.46), x(.52), -1.4, 1.4, d(.5) + 5.4, spec["mast_height_m"] - 1.5, .6, "integrated_mast")
    m.cbox(x(.49), 0, spec["mast_height_m"] - 1.0, .8, 2.4, 1.0, "search_array", "array_face")
    for sign in (-1, 1):
        box_launcher(m, x(.16), sign * B * .24, d(.5) + .4, 2, 2, 1.25, 6.4, heading=sign * .06, incline=.22)
    m.prism(x(.74), x(.80), -1.4, 1.4, d(.5) + .4, d(.5) + 2.0, .4, "gun_house")
    m.cylinder(0, d(.5) + 1.5, x(.80), x(.80) + 2.4, .18, 8, "barrel", "x", m="titanium")
    finish_surface(m, s, spec, railings=False)


def build_houdong(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 6.8, 1.9, 2.0, 3.2
    s = Ship(m, L, B, dr, fa, ff, stations=30, transom=.80, fullness=.50, flare=1.0)
    x, d = s.x, s.d
    # A missile boat: wheelhouse forward of amidships, four canisters aft in two angled pairs.
    m.box(x(.40), x(.64), -B * .40, B * .40, d(.52), d(.52) + 2.4, "deckhouse")
    m.box(x(.48), x(.62), -B * .34, B * .34, d(.52) + 2.4, d(.52) + 4.4, "bridge")
    m.lattice_mast(x(.44), 0, d(.52) + 2.4, spec["mast_height_m"] - .5, 1.6, .6)
    m.cbox(x(.44), 0, spec["mast_height_m"], .6, 2.2, .7, "search_array", "array_face")
    m.dome(x(.58), 0, d(.52) + 4.4, .6)
    for sign in (-1, 1):
        canister_pack(m, x(.24), sign * B * .18, d(.26) + .2, 2, 6.2, .40, heading=sign * .16, stack=False)
    m.cylinder(x(.82), 0, d(.82), d(.82) + 1.0, .9, 8, "gun_mount", m="naval_paint")
    for off in (-.25, .25):
        m.cylinder(off, d(.82) + .9, x(.82), x(.82) + 2.8, .07, 6, "barrel", "x", m="titanium")
    m.cylinder(x(.06), 0, d(.06), d(.06) + .9, .7, 8, "gun_mount", m="naval_paint")
    m.cylinder(0, d(.06) + .8, x(.06) - 2.2, x(.06), .06, 6, "barrel", "x", m="titanium")
    finish_surface(m, s, spec, railings=False)


def build_peykaap(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 3.6, .8, .9, 1.5
    s = Ship(m, L, B, dr, fa, ff, stations=24, transom=.88, fullness=.48, flare=1.0)
    x, d = s.x, s.d
    # A tiny craft: an open cockpit behind a windscreen, two tubes on the after deck.
    m.prism(x(.36), x(.62), -B * .36, B * .36, d(.5), d(.5) + .9, .15, "cockpit_coaming")
    m.box(x(.58), x(.62), -B * .34, B * .34, d(.5) + .9, d(.5) + 1.5, "windscreen", "glazing")
    m.box(x(.36), x(.58), -B * .30, B * .30, d(.5) + .9, d(.5) + 1.0, "cockpit_top", "deck_non_skid")
    m.mast(x(.40), 0, d(.5) + 1.0, spec["mast_height_m"], .08, .8)
    for sign in (-1, 1):
        m.cylinder(sign * B * .26, d(.15) + .45, x(-.02), x(.30), .28, 10, "tube", "x")
    m.cbox(x(.03), 0, d(.03) + .5, 1.0, 1.2, .8, "engine_box")
    finish_surface(m, s, spec, railings=False)


# --------------------------------------------------------------------------------------------
# Carriers
# --------------------------------------------------------------------------------------------


def parked_aircraft(m, builder, length, positions, z, deck_material="airframe_light"):
    for xx, yy, heading in positions:
        mark = m.mark()
        builder(m, length)
        for p in m.since(mark):
            p.rotate((0, 0, 1), heading)
            p.translate((xx, yy, z))
            p.material = "glazing" if p.name == "canopy" else deck_material
            p.face_materials = None


def build_shandong(m, spec):
    L = spec["length_m"]
    B, dr = 38.0, 10.5
    fa, ff = 15.0, 16.5
    s = Ship(m, L, B, dr, fa, ff, stations=44, fullness=.62, transom=.82, bow_power=1.6)
    x, d = s.x, s.d
    z = d(.5) + .8
    bulbous_bow(m, s, r=3.6)
    # A STOBAR carrier: the flight deck sweeps up into a bow ramp, the angled recovery deck
    # sponsons out to port and the island sits to starboard abaft amidships.
    deck = [(x(0.0), -B * .62), (x(.72), -B * .62), (x(.985), -B * .40), (x(.985), B * .30),
            (x(.86), B * .48), (x(.60), B * .60), (x(.34), B * .92), (x(.16), B * .96), (x(.05), B * .80), (x(0.0), B * .64)]
    m.plate(deck, z, z + 2.4, "flight_deck", "flight_deck")
    ramp = [(x(.86), z + 2.4), (x(.985), z + 2.4), (x(.985), z + 8.6), (x(.94), z + 6.0)]
    m.vplate(ramp, -B * .30, B * .30, "ski_jump", "flight_deck")
    m.prism(x(.50), x(.66), -B * .62, -B * .44, z + 2.4, z + 12.0, .6, "island")
    m.box(x(.55), x(.65), -B * .60, -B * .46, z + 12.0, z + 16.5, "bridge")
    for sign, xx in ((-1, x(.505)), (1, x(.655))):
        m.front_array(xx, -B * .53, z + 6.0, 5.0, 5.0, sign)
    m.radar_face(x(.58), -B * .44, z + 6.0, 5.0, 5.0, 1)
    m.prism(x(.58), x(.63), -B * .58, -B * .48, z + 16.5, z + 24.0, 1.0, "mast_tower")
    m.mast(x(.605), -B * .53, z + 24.0, spec["mast_height_m"] + 1.0, .5, 8.0)
    m.cbox(x(.53), -B * .53, z + 18.0, 1.2, 7.0, 2.2, "search_array", "array_face")
    m.funnel(x(.52), -B * .53, z + 12.0, 2.2, 4.0, 5.0)
    for xx in (x(.42), x(.72)):
        m.box(xx - L * .03, xx + L * .03, -B * .70, -B * .62, z, z + 2.4, "lift", "flight_deck")
    m.box(x(.26), x(.62), B * .44, B * .45, z + 2.4, z + 2.7, "angle_edge", "marking_white")
    for sign in (-1, 1):
        for xx in (x(.25), x(.80)):
            m.cbox(xx, sign * B * .60, z - 1.5, L * .04, 3.0, 2.0, "sponson")
            m.ciws(xx, sign * B * .61, z - .5)
    carrier_markings(m, L, B, z + 2.4, angle=.12, catapults=False)
    parked_aircraft(m, aw.parked_flanker, 21.9, [(x(.20), B * .30, .0), (x(.30), B * .33, .0), (x(.40), -B * .28, .0), (x(.76), B * .15, .0)], z + 3.2)
    finish_surface(m, s, spec, railings=False)


def build_izumo(m, spec):
    L = spec["length_m"]
    B, dr = 38.0, 7.5
    fa, ff = 13.5, 15.0
    s = Ship(m, L, B, dr, fa, ff, stations=44, fullness=.68, transom=.88, bow_power=1.9)
    x, d = s.x, s.d
    z = d(.5) + .6
    bulbous_bow(m, s, r=3.0)
    # A flat through deck with a squared-off bow for the Lightning, one long starboard island.
    deck = [(x(0.0), -B * .50), (x(.93), -B * .50), (x(.995), -B * .34), (x(.995), B * .34), (x(.93), B * .50), (x(0.0), B * .50)]
    m.plate(deck, z, z + 2.2, "flight_deck", "flight_deck")
    m.prism(x(.42), x(.70), -B * .50, -B * .34, z + 2.2, z + 10.0, .6, "island")
    m.box(x(.56), x(.69), -B * .49, -B * .36, z + 10.0, z + 14.0, "bridge")
    for sign, xx in ((-1, x(.425)), (1, x(.695))):
        m.front_array(xx, -B * .42, z + 4.5, 4.0, 4.0, sign)
    m.radar_face(x(.50), -B * .34, z + 4.5, 4.0, 4.0, 1)
    m.radar_face(x(.62), -B * .34, z + 4.5, 4.0, 4.0, 1)
    m.prism(x(.60), x(.64), -B * .46, -B * .38, z + 14.0, z + 21.0, .8, "mast_tower")
    m.mast(x(.62), -B * .42, z + 21.0, spec["mast_height_m"] + 1.0, .45, 6.0)
    m.funnel(x(.47), -B * .42, z + 10.0, 2.0, 3.6, 5.0)
    m.funnel(x(.53), -B * .42, z + 10.0, 2.0, 3.6, 5.0)
    m.cbox(x(.45), -B * .42, z + 14.5, 1.0, 5.0, 1.6, "search_array", "array_face")
    m.box(x(.20) - L * .03, x(.20) + L * .03, -B * .58, -B * .50, z, z + 2.2, "lift", "flight_deck")
    m.box(x(.78) - L * .03, x(.78) + L * .03, -B * .10, B * .10, z + 2.2, z + 2.35, "lift_outline", "marking_white")
    for sign in (-1, 1):
        m.cbox(x(.12), sign * B * .50, z - 1.2, L * .03, 2.4, 1.8, "sponson")
        m.ciws(x(.12), sign * B * .51, z - .3)
    m.ciws(x(.94), -B * .32, z + 2.2)
    for t in (.16, .36, .56, .80):
        m.circle(x(t), B * .05, z + 2.25, 6.0, .28)
    m.stripe((x(.02), -B * .16, z + 2.24), (x(.92), -B * .16, z + 2.24), .35)
    m.stripe((x(.02), B * .26, z + 2.24), (x(.92), B * .26, z + 2.24), .35)
    parked_aircraft(m, aw.parked_lightning, 15.7, [(x(.28), -B * .32, .0), (x(.68), B * .30, .0), (x(.86), B * .28, .0)], z + 2.9)
    finish_surface(m, s, spec, railings=False)


def carrier_markings(m, L, B, z, angle=.12, catapults=True):
    for sign in (-1, 1):
        m.stripe((-L * .43, -B * .10 + sign * B * .12, z), (L * .22, L * .65 * angle - B * .10 + sign * B * .12, z), .38)
    for i in range(16):
        xx = -L * .42 + i * L * .035
        yy = -B * .10 + (xx + L * .43) * angle
        m.stripe((xx, yy, z + .01), (xx + L * .018, yy + L * .018 * angle, z + .01), .38, "marking_yellow")
    if catapults:
        for y in (-B * .16, B * .15):
            m.stripe((L * .06, y, z), (L * .43, y, z), .20)


# --------------------------------------------------------------------------------------------
# Auxiliaries and civil
# --------------------------------------------------------------------------------------------


def build_type903a(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 24.8, 8.6, 6.4, 10.0
    s = Ship(m, L, B, dr, fa, ff, stations=40, fullness=.72, transom=.78, bow_power=1.7)
    x, d = s.x, s.d
    bulbous_bow(m, s)
    # A fleet replenishment ship: superstructure and hangar aft, two pairs of kingposts with
    # cross beams and rigs amidships, a raised forecastle house.
    m.prism(x(.08), x(.27), -B * .42, B * .42, d(.17), d(.17) + 8.0, .6, "accommodation")
    m.box(x(.13), x(.26), -B * .44, B * .44, d(.17) + 8.0, d(.17) + 11.0, "bridge")
    m.funnel(x(.12), 0, d(.17) + 11.0, 5.0, 3.4, 5.0, -.8)
    m.mast(x(.22), 0, d(.17) + 11.0, d(.17) + 20.0, .4, 6.0)
    m.cbox(x(.22), 0, d(.17) + 19.0, .9, 4.6, 1.3, "search_array", "array_face")
    m.hangar(x(.02), x(.09), B * .55, d(.06), 6.4)
    for t in (.40, .60):
        for sign in (-1, 1):
            m.cylinder(x(t), sign * B * .34, d(t), d(t) + 22.0, .6, 8, "kingpost")
            m.rod((x(t), sign * B * .34, d(t) + 14.0), (x(t) + 5.0, sign * B * .12, d(t) + 3.0), .18, "rig", "naval_paint", 6)
        m.cbox(x(t), 0, d(t) + 21.0, 1.6, B * .74, 1.4, "gantry")
        m.cbox(x(t), 0, d(t) + 12.0, 1.4, B * .70, 1.0, "gantry_low")
        m.box(x(t) - 6, x(t) + 6, -B * .12, B * .12, d(t), d(t) + 2.6, "pump_house")
    m.box(x(.74), x(.86), -B * .32, B * .32, d(.80), d(.80) + 2.4, "fwd_house")
    m.mast(x(.90), 0, d(.90), d(.90) + 9.0, .3)
    m.box(x(.28), x(.70), -.9, .9, d(.5), d(.5) + 1.2, "pipe_run", "naval_paint")
    liferafts(m, s, (.10, .20), B * .43, d(.17) + 8.2)
    finish_surface(m, s, spec, deck="flight_deck")


def build_vlcc(m, spec):
    L = spec["length_m"]
    B, dr, fa, ff = 60.0, 16.0, 8.0, 10.5
    s = Ship(m, L, B, dr, fa, ff, stations=48, fullness=.86, transom=.70, bow_sharp=False, flare=1.0)
    x, d = s.x, s.d
    m.ellipsoid(L * .5 - 10.0, 0, -dr * .70, 22.0, 6.0, 5.5, 12, 6, "bulb", "antifouling")
    # A very large crude carrier: the whole house aft, a long pipe run and catwalk down the
    # centreline, the manifold amidships and a low forecastle.
    m.box(x(.05), x(.14), -B * .38, B * .38, d(.1), d(.1) + 12.0, "accommodation")
    m.box(x(.06), x(.13), -B * .42, B * .42, d(.1) + 12.0, d(.1) + 15.0, "bridge")
    m.funnel(x(.05), 0, d(.1) + 15.0, 7.0, 5.0, 7.0, -1.0)
    m.mast(x(.11), 0, d(.1) + 15.0, d(.1) + 26.0, .4, 6.0)
    m.box(x(.15), x(.90), -1.6, 1.6, d(.5), d(.5) + 2.2, "catwalk")
    for yy in (-4.6, -3.2, 3.2, 4.6):
        m.cylinder(yy, d(.5) + .8, x(.15), x(.88), .55, 8, "pipe", "x")
    m.box(x(.48), x(.52), -B * .40, B * .40, d(.5), d(.5) + 2.6, "manifold")
    for sign in (-1, 1):
        m.cylinder(x(.50), sign * B * .20, d(.5), d(.5) + 12.0, .5, 8, "crane_post")
        m.rod((x(.50), sign * B * .20, d(.5) + 12.0), (x(.50) + 2.0, sign * B * .44, d(.5) + 6.0), .3, "crane_jib", "naval_paint", 6)
    for i in range(7):
        t0 = .18 + i * .10
        for sign in (-1, 1):
            m.cbox(x(t0 + .04), sign * B * .22, d(t0) + .7, 3.0, 3.0, 1.4, "tank_hatch")
    m.box(x(.90), x(.97), -B * .30, B * .30, d(.93), d(.93) + 2.4, "forecastle_house")
    m.mast(x(.95), 0, d(.95) + 2.4, d(.95) + 12.0, .3, 3.0)
    finish_surface(m, s, spec, deck="hull_red", railings=False)


# --------------------------------------------------------------------------------------------
# Submarines
# --------------------------------------------------------------------------------------------


def sub_hull(m, L, R, blunt=True, name="pressure_hull"):
    prof = [(-L * .5, .02), (-L * .44, R * .40), (-L * .31, R * .92), (-L * .15, R), (L * .26, R), (L * .37, R * .92), (L * .45, R * .64), (L * .50, .02)]
    if blunt:
        prof = [(-L * .5, .02), (-L * .44, R * .40), (-L * .31, R * .92), (-L * .15, R), (L * .30, R), (L * .40, R * .90), (L * .47, R * .55), (L * .50, .02)]
    return m.revolve(prof, 24, name, "rubber")


def sub_tail(m, L, R, kind="cruciform", prop_blades=7):
    if kind == "cruciform":
        for a in (0, math.pi / 2, math.pi, math.pi * 1.5):
            o = m.plate([(-L * .40, 0), (-L * .32, 0), (-L * .36, R * 1.6), (-L * .42, R * 1.35)], -.13, .13, "stern_fin", "rubber")
            o.rotate((1, 0, 0), a)
    else:
        for a in (math.pi * .25, math.pi * .75, math.pi * 1.25, math.pi * 1.75):
            o = m.plate([(-L * .40, 0), (-L * .32, 0), (-L * .36, R * 1.6), (-L * .42, R * 1.35)], -.13, .13, "x_rudder", "rubber")
            o.rotate((1, 0, 0), a)
    for i in range(prop_blades):
        o = m.plate([(-L * .495, 0), (-L * .48, R * .8), (-L * .46, R * .85), (-L * .47, 0)], -.08, .08, "propeller", "bronze")
        o.rotate((1, 0, 0), i * math.tau / prop_blades)


def build_type093b(m, spec):
    L = spec["length_m"]
    R = 5.5
    sub_hull(m, L, R, blunt=True)
    # A rounded sail with a long low hump behind it, sail planes, cruciform tail.
    sail = [(L * .04, R * .90), (L * .16, R * .90), (L * .155, R * 1.9), (L * .12, R * 2.15), (L * .06, R * 2.15), (L * .045, R * 1.9)]
    m.vplate(sail, -R * .36, R * .36, "sail", "rubber")
    m.ellipsoid(L * .10, 0, R * 1.35, L * .065, R * .36, R * .78, 14, 6, "sail_fairing", "rubber")
    m.plate([(L * .08, -R * 1.6), (L * .13, -R * 1.6), (L * .13, R * 1.6), (L * .08, R * 1.6)], R * 1.55, R * 1.68, "sail_planes", "rubber")
    hump = [(-L * .16, R * .95), (-L * .10, R * 1.18), (L * .02, R * 1.18), (L * .04, R * .95)]
    m.vplate(hump, -R * .55, R * .55, "vls_hump", "rubber")
    m.ellipsoid(-L * .07, 0, R * .95, L * .11, R * .55, R * .24, 14, 6, "hump_fairing", "rubber")
    for xx in (L * .09, L * .11, L * .13):
        m.mast(xx, 0, R * 2.1, R * 2.7, .07, m="rubber")
    sub_tail(m, L, R, "cruciform", 7)
    m.waterline_z = 0.0


def build_type039a(m, spec):
    L = spec["length_m"]
    R = 4.2
    prof = []
    n = 12
    for i in range(n + 1):
        t = i / n
        prof.append((-L / 2 + L * .28 * t, R * math.sin(t * math.pi / 2) ** .7))
    prof.append((L * .30, R))
    for i in range(1, n + 1):
        t = i / n
        prof.append((L * .30 + L * .20 * t, R * math.cos(t * math.pi / 2) ** .55))
    m.revolve(prof, 22, "pressure_hull", "rubber")
    # A teardrop diesel boat with a tall, raked sail on a long faired base.
    sail = [(L * .02, R * .9), (L * .18, R * .9), (L * .17, R * 2.25), (L * .07, R * 2.3), (L * .035, R * 2.1)]
    m.vplate(sail, -R * .34, R * .34, "sail", "rubber")
    m.wedge(-L * .02, L * .02, -R * .34, R * .34, R * .85, R * 1.3, "sail_fairing", "rubber", forward=True)
    m.plate([(L * .09, -R * 1.5), (L * .15, -R * 1.5), (L * .15, R * 1.5), (L * .09, R * 1.5)], R * 1.7, R * 1.85, "sail_planes", "rubber")
    for xx in (L * .08, L * .11, L * .14):
        m.mast(xx, 0, R * 2.2, R * 2.8, .07, m="rubber")
    sub_tail(m, L, R, "cruciform", 7)
    m.waterline_z = 0.0


def build_taigei(m, spec):
    L = spec["length_m"]
    R = 4.55
    sub_hull(m, L, R, blunt=False)
    sail = [(L * .01, R * .90), (L * .18, R * .9), (L * .17, R * 2.02), (L * .07, R * 2.17), (L * .015, R * 1.8)]
    m.vplate(sail, -R * .27, R * .27, "sail", "rubber")
    m.plate([(L * .07, -R * 1.6), (L * .12, -R * 1.6), (L * .12, R * 1.6), (L * .07, R * 1.6)], R * 1.64, R * 1.75, "sail_planes", "rubber")
    for xx in (L * .08, L * .11, L * .14):
        m.mast(xx, 0, R * 2, R * 2.6, .06, m="rubber")
    sub_tail(m, L, R, "x", 7)
    m.waterline_z = 0.0


def build_ghadir(m, spec):
    L = spec["length_m"]
    R = 1.4
    prof = [(-L * .5, .02), (-L * .46, R * .45), (-L * .34, R * .92), (-L * .2, R), (L * .30, R), (L * .42, R * .8), (L * .48, R * .4), (L * .50, .02)]
    m.revolve(prof, 18, "pressure_hull", "rubber")
    # A midget boat: a slab-sided sail, small planes, a simple cross tail and one screw.
    m.box(L * .0, L * .12, -R * .40, R * .40, R * .85, R * 2.4, "sail", "rubber")
    m.wedge(L * .12, L * .16, -R * .40, R * .40, R * .85, R * 2.4, "sail_front", "rubber", forward=False)
    m.plate([(L * .30, -R * 1.5), (L * .36, -R * 1.5), (L * .36, R * 1.5), (L * .30, R * 1.5)], -.08, .08, "bow_planes", "rubber")
    for xx in (L * .04, L * .08):
        m.mast(xx, 0, R * 2.4, R * 3.2, .06, m="rubber")
    sub_tail(m, L, R, "cruciform", 5)
    m.waterline_z = 0.0


# --------------------------------------------------------------------------------------------
# Fixed sites (domain land): a compact installation on a flat earth base
# --------------------------------------------------------------------------------------------


VEHICLE_SCALE = 1.6  # stylised: a launcher must still read on a 700 m base


def site_base(m, length, width, roads=()):
    m.box(-length / 2, length / 2, -width / 2, width / 2, -3.0, 0.0, "base", "earth")
    # A perimeter track and the access roads break the slab up in plan.
    edge = 14.0
    for (x0, y0, x1, y1) in ((-length / 2 + edge, -width / 2 + edge, length / 2 - edge, -width / 2 + edge),
                             (length / 2 - edge, -width / 2 + edge, length / 2 - edge, width / 2 - edge),
                             (length / 2 - edge, width / 2 - edge, -length / 2 + edge, width / 2 - edge),
                             (-length / 2 + edge, width / 2 - edge, -length / 2 + edge, -width / 2 + edge)):
        m.stripe((x0, y0, .05), (x1, y1, .05), 8.0, "earth_dark", "track")
    for (x0, y0, x1, y1, w) in roads:
        m.stripe((x0, y0, .05), (x1, y1, .05), w, "concrete", "road")


def revetment(m, x, y, radius=26.0, height=4.0, opening=.9, heading=0.0):
    """A horseshoe earth berm around a launcher position, open on one side."""
    segs = 14
    for i in range(segs):
        a0 = opening + (math.tau - 2 * opening) * i / segs
        a1 = opening + (math.tau - 2 * opening) * (i + 1) / segs
        p0 = (x + radius * math.cos(a0 + heading), y + radius * math.sin(a0 + heading), 0.0)
        p1 = (x + radius * math.cos(a1 + heading), y + radius * math.sin(a1 + heading), 0.0)
        a, c = np.asarray(p0), np.asarray(p1)
        d = c - a
        side = np.array((-d[1], d[0], 0.0))
        side /= max(np.linalg.norm(side), 1e-9)
        w = 9.0
        verts = [a - side * w, c - side * w, c + side * w, a + side * w,
                 a - side * w * .3 + (0, 0, height), c - side * w * .3 + (0, 0, height), c + side * w * .3 + (0, 0, height), a + side * w * .3 + (0, 0, height)]
        m.add("berm", verts, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], "earth_dark")
    m.cylinder(x, y, .0, .3, radius * .72, 16, "pad", m="concrete", smooth=0.0)


def truck(m, x, y, heading, length=14.0, width=3.3, cab=2.4, m_name="drab", axles=4):
    k = VEHICLE_SCALE
    length, width, cab = length * k, width * k, cab * k
    mark = m.mark()
    m.box(-length / 2, length / 2, -width / 2, width / 2, 1.1 * k, 2.2 * k, "chassis", m_name)
    m.box(length / 2 - cab, length / 2, -width / 2, width / 2, 2.2 * k, 3.9 * k, "cab", m_name)
    m.box(length / 2 - .15, length / 2 - .05, -width * .42, width * .42, 2.9 * k, 3.6 * k, "cab_glass", "glazing")
    for i in range(axles):
        xx = -length / 2 + 1.8 * k + i * (length - 3.4 * k) / max(1, axles - 1)
        for sign in (-1, 1):
            m.cylinder(sign * (width / 2 + .1), .7 * k, xx - .55 * k, xx + .55 * k, .7 * k, 10, "wheel", "y", m="rubber")
    parts = m.since(mark)
    for p in parts:
        p.rotate((0, 0, 1), heading)
        p.translate((x, y, 0))
    return parts


def tel(m, x, y, heading, tubes=4, tube_len=8.0, tube_r=.5, erect=math.radians(88), square=False, length=14.0, m_name="drab"):
    """A transporter-erector-launcher with its tubes raised."""
    truck(m, x, y, heading, length=length, m_name=m_name)
    k = VEHICLE_SCALE
    tube_len, tube_r, length = tube_len * k, tube_r * k, length * k
    mark = m.mark()
    pivot_x = -length / 2 + 1.5 * k
    for i in range(tubes):
        yy = (i - (tubes - 1) / 2) * tube_r * 2.3 if tubes > 1 else 0.0
        if square:
            m.box(0, tube_len, yy - tube_r, yy + tube_r, -tube_r, tube_r, "tube", m_name)
            m.box(tube_len - .05, tube_len + .05, yy - tube_r * .9, yy + tube_r * .9, -tube_r * .9, tube_r * .9, "tube_cap", "rubber")
        else:
            m.cylinder(yy, 0, 0, tube_len, tube_r, 10, "tube", "x", m=m_name)
            m.cylinder(yy, 0, tube_len - .05, tube_len + .05, tube_r * .92, 10, "tube_cap", "x", m="rubber")
    m.box(-.6 * k, .6 * k, -tubes * tube_r * 1.2, tubes * tube_r * 1.2, -tube_r * 1.3, tube_r * 1.3, "cradle", m_name)
    for p in m.since(mark):
        p.rotate((0, 1, 0), -erect)
        p.translate((pivot_x, 0, 2.6 * k))
        p.rotate((0, 0, 1), heading)
        p.translate((x, y, 0))


def radar_truck(m, x, y, heading, panel_w=8.0, panel_h=4.0, mast_h=0.0):
    truck(m, x, y, heading, length=11.0)
    k = VEHICLE_SCALE
    panel_w, panel_h = panel_w * k, panel_h * k
    mark = m.mark()
    m.box(-4.0 * k, 0.0, -.4 * k, .4 * k, 2.2 * k, 3.4 * k, "pedestal", "drab")
    m.box(-.6 * k, .0, -panel_w / 2, panel_w / 2, 3.4 * k, 3.4 * k + panel_h, "panel", "array_face")
    if mast_h:
        m.cylinder(-4.5 * k, 0, 2.2 * k, mast_h, .3, 8, "radar_mast", m="drab")
        m.cbox(-4.5 * k, 0, mast_h + .8, .8, 4.0, 1.4, "search_array", "array_face")
    for p in m.since(mark):
        p.rotate((0, 0, 1), heading)
        p.translate((x, y, 0))


def radar_tower(m, x, y, height, m_name="drab"):
    m.lattice_mast(x, y, 0.0, height, max(9.0, height * .30), 3.0, m=m_name)
    m.cbox(x, y, height + 1.6, 1.6, 9.0, 3.0, "search_array", "array_face")
    m.cbox(x + 12.0, y, 2.4, 9.0, 6.0, 4.8, "cabin", m_name)


def build_coastal_battery(m, spec, kind):
    mast_h = max(12.0, min(spec["mast_height_m"], 60.0))
    site_base(m, 560.0, 330.0, roads=[(-250, -70, 250, -70, 14.0), (-195, -70, -195, 60, 12.0), (-65, -70, -65, 60, 12.0),
                                      (65, -70, 65, 60, 12.0), (195, -70, 195, 60, 12.0)])
    positions = [(-195, 60), (-65, 60), (65, 60), (195, 60)]
    for (xx, yy) in positions:
        revetment(m, xx, yy, 32.0, 6.0, opening=.95, heading=-math.pi / 2)
        if kind == "yj12b":
            tel(m, xx, yy, math.radians(8), tubes=3, tube_len=8.5, tube_r=.9, erect=math.radians(30), square=True, length=15.0)
        elif kind == "type12":
            tel(m, xx, yy, math.radians(-6), tubes=3, tube_len=6.0, tube_r=.55, erect=math.radians(45), square=True, length=12.0)
        elif kind == "bastion":
            tel(m, xx, yy, math.radians(4), tubes=2, tube_len=9.5, tube_r=.7, erect=math.radians(82), length=13.0)
        else:  # qader / noor
            tel(m, xx, yy, math.radians(-4), tubes=3, tube_len=7.0, tube_r=.5, erect=math.radians(25), square=True, length=12.0)
    radar_tower(m, -40.0, -125.0, mast_h)
    truck(m, 50.0, -120.0, math.radians(90), length=10.0)
    m.box(90, 130, -145, -115, 0, 6.0, "command_post", "concrete")
    m.box(-240, -200, -140, -110, 0, 5.0, "shelter", "concrete")
    m.box(200, 240, -140, -110, 0, 5.0, "shelter", "concrete")


def build_sam_site(m, spec, kind):
    site_base(m, 640.0, 440.0)
    ring = 160.0
    launchers = [(ring, 0), (-ring, 0), (0, ring), (0, -ring)]
    for i, (xx, yy) in enumerate(launchers):
        heading = math.atan2(yy, xx)
        revetment(m, xx, yy, 34.0, 6.0, opening=.9, heading=heading + math.pi)
        if kind == "bavar":
            tel(m, xx, yy, heading, tubes=4, tube_len=8.0, tube_r=.6, erect=math.radians(70), square=True, length=14.0)
        elif kind == "s400":
            tel(m, xx, yy, heading, tubes=4, tube_len=9.0, tube_r=.55, erect=math.radians(88), length=14.0)
        else:
            tel(m, xx, yy, heading, tubes=4, tube_len=8.0, tube_r=.55, erect=math.radians(88), length=14.0)
        m.stripe((xx * .28, yy * .28, .05), (xx * .78, yy * .78, .05), 12.0, "concrete", "road")
    revetment(m, 0.0, 0.0, 38.0, 4.0, opening=.9, heading=math.pi * .75)
    radar_truck(m, 0.0, 0.0, math.radians(20), panel_w=9.0, panel_h=4.5)
    radar_tower(m, -110.0, 120.0, max(15.0, min(spec["mast_height_m"], 40.0)))
    truck(m, 95.0, 120.0, math.radians(100), length=11.0)
    truck(m, 130.0, 120.0, math.radians(100), length=11.0)
    m.box(-105, -45, -150, -115, 0, 6.0, "command_post", "concrete")
    m.stripe((-250, 200, .05), (250, 200, .05), 12.0, "concrete", "road")
    m.stripe((0, 200, .05), (0, 160, .05), 12.0, "concrete", "road")


def build_ballistic_battery(m, spec, kind):
    site_base(m, 460.0, 300.0, roads=[(-200, -40, 200, -40, 14.0), (-140, -40, -140, 50, 12.0), (0, -40, 0, 50, 12.0), (140, -40, 140, 50, 12.0)])
    for i, xx in enumerate((-140, 0, 140)):
        yy = 50.0
        revetment(m, xx, yy, 32.0, 5.0, opening=.9, heading=-math.pi / 2)
        if kind == "df21d":
            tel(m, xx, yy, math.radians(4), tubes=1, tube_len=11.0, tube_r=.75, erect=math.radians(89), length=16.0)
        else:
            tel(m, xx, yy, math.radians(-3), tubes=1, tube_len=8.5, tube_r=.32, erect=math.radians(80), length=11.0)
    truck(m, -80.0, -100.0, math.radians(0), length=10.0)
    truck(m, 80.0, -100.0, math.radians(0), length=10.0)
    m.box(-30, 30, -125, -90, 0, 7.0, "command_post", "concrete")
    m.lattice_mast(170.0, -100.0, 0, max(10.0, spec["mast_height_m"]) + 8.0, 6.0, 2.0, m="drab")
    m.cbox(170.0, -100.0, max(10.0, spec["mast_height_m"]) + 8.8, 1.2, 2.4, 1.6, "antenna", "array_face")


def build_drone_site(m, spec):
    site_base(m, 380.0, 250.0, roads=[(-160, -40, 160, -40, 12.0)])
    for i in range(4):
        xx = -120 + i * 80
        yy = 40.0
        m.box(xx - 12, xx + 12, yy - 14, yy + 14, 0, 1.0, "launch_pad", "concrete")
        truck(m, xx, yy, math.radians(90), length=9.0, width=2.8)
        rail = m.box(-.5, 14.0, -.9, .9, -.4, .4, "launch_rail", "drab")
        rail.rotate((0, 1, 0), -math.radians(28))
        rail.rotate((0, 0, 1), math.radians(90))
        rail.translate((xx, yy - 3.0, 4.5))
        for k in range(2):
            m.box(xx - 30 - k * 8, xx - 24 - k * 8, yy - 10, yy + 10, 0, 4.2, "container", "drab")
    for i in range(5):
        m.box(-110 + i * 26, -92 + i * 26, -110, -92, 0, 4.2, "container", "concrete")
    m.box(110, 150, -115, -90, 0, 6.0, "control_cabin", "concrete")
    m.lattice_mast(160.0, -60.0, 0, max(8.0, spec["mast_height_m"]) + 10.0, 5.0, 1.6, m="drab")
    m.cbox(160.0, -60.0, max(8.0, spec["mast_height_m"]) + 10.8, 1.0, 1.6, 1.2, "antenna", "array_face")
    for sign in (-1, 1):
        m.box(-165, 165, sign * 108 - 8, sign * 108 + 8, 0, 4.5, "berm", "earth_dark")


# --------------------------------------------------------------------------------------------
# Registry
# --------------------------------------------------------------------------------------------

BUILDERS = {
    "pla_ddg_type055": build_type055,
    "pla_ddg_type052d": build_type052d,
    "jmsdf_ddg_maya": build_maya,
    "jmsdf_dd_akizuki": build_akizuki,
    "pla_ffg_type054a": build_type054a,
    "jmsdf_ffm_mogami": build_mogami,
    "irn_ffg_moudge": build_moudge,
    "irn_ffg_alvand": build_alvand,
    "pla_fsg_type056a": build_type056a,
    "pla_pgg_type022": build_type022,
    "irn_pgg_houdong": build_houdong,
    "irn_fac_peykaap3": build_peykaap,
    "pla_cv_shandong": build_shandong,
    "jmsdf_ddh_izumo": build_izumo,
    "pla_aor_type903a": build_type903a,
    "civ_tanker_vlcc": build_vlcc,
    "pla_ssn_type093b": build_type093b,
    "pla_ssk_type039a": build_type039a,
    "jmsdf_ssk_taigei": build_taigei,
    "irn_ssm_ghadir": build_ghadir,
    "pla_battery_yj12b": lambda m, s: build_coastal_battery(m, s, "yj12b"),
    "jgsdf_ssm_type12_battery": lambda m, s: build_coastal_battery(m, s, "type12"),
    "irn_battery_qader": lambda m, s: build_coastal_battery(m, s, "qader"),
    "rfn_battery_bastion": lambda m, s: build_coastal_battery(m, s, "bastion"),
    "pla_sam_hq9b_site": lambda m, s: build_sam_site(m, s, "hq9b"),
    "irn_sam_bavar373": lambda m, s: build_sam_site(m, s, "bavar"),
    "rfn_sam_s400_site": lambda m, s: build_sam_site(m, s, "s400"),
    "pla_asbm_df21d": lambda m, s: build_ballistic_battery(m, s, "df21d"),
    "irn_asbm_khalij_fars": lambda m, s: build_ballistic_battery(m, s, "khalij_fars"),
    "irn_drone_site_shahed": build_drone_site,
}
BUILDERS.update(aw.BUILDERS)


# --------------------------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------------------------


def load_json(path, default):
    if path.exists():
        return json.loads(path.read_text())
    return default


def write_manifest(rows):
    existing = load_json(MODELS / "manifest.json", [])
    changed = {row["id"] for row in rows}
    merged = [row for row in existing if row["id"] not in changed] + rows
    merged.sort(key=lambda row: row["id"])
    (MODELS / "manifest.json").write_text(json.dumps(merged, indent=2) + "\n")


def build_one(sid, spec, is_weapon):
    m = Model("missile_body" if is_weapon else "naval_paint")
    if is_weapon:
        aw.weapon_model(m, spec)
    else:
        builder = BUILDERS.get(sid)
        if builder is None:
            raise KeyError("no builder for " + sid)
        builder(m, spec)
    MODELS.mkdir(parents=True, exist_ok=True)
    info = m.export(str(MODELS / (sid + ".glb")))
    if info["triangles"] > TRIANGLE_BUDGET:
        raise RuntimeError("%s has %d triangles (budget %d)" % (sid, info["triangles"], TRIANGLE_BUDGET))
    if info["surfaces"] > 20:
        raise RuntimeError("%s has %d surfaces (budget 20)" % (sid, info["surfaces"]))
    entry = {"kind": "weapon" if is_weapon else "platform"}
    if not is_weapon:
        entry["domain"] = spec["domain"]
        if spec["domain"] in ("surface", "subsurface"):
            entry["waterline_y"] = round(info["waterline_y"], 4)
    print("MODEL %-28s %6d tris %2d surfaces %s" % (sid, info["triangles"], info["surfaces"],
                                                    " ".join("%.1f" % v for v in info["extent_m"])), flush=True)
    return {"id": sid, "kind": entry["kind"], "triangles": info["triangles"]}, entry


def copy_asset(sid, donor, specs, sidecar, rows):
    """Reuse a donor's geometry and renders under a new id (same airframe or hull)."""
    src = MODELS / (donor + ".glb")
    if not src.exists():
        raise FileNotFoundError(src)
    shutil.copyfile(src, MODELS / (sid + ".glb"))
    kind = "weapon" if sid not in specs else "platform"
    art = WEAPON_ART if kind == "weapon" else PLATFORM_ART
    views = ("beauty", "thumb") if kind == "weapon" else ("beauty", "thumb", "profile", "plan")
    for view in views:
        s = art / ("%s_%s.png" % (donor, view))
        if s.exists():
            shutil.copyfile(s, art / ("%s_%s.png" % (sid, view)))
    donor_rows = [r for r in load_json(MODELS / "manifest.json", []) if r["id"] == donor]
    triangles = donor_rows[0]["triangles"] if donor_rows else 0
    rows.append({"id": sid, "kind": kind, "triangles": triangles})
    entry = {"kind": kind, "copy_of": donor}
    if kind == "platform":
        entry["domain"] = specs[sid]["domain"]
        if donor in sidecar and "waterline_y" in sidecar[donor]:
            entry["waterline_y"] = sidecar[donor]["waterline_y"]
    sidecar[sid] = entry
    print("COPY  %-28s from %s" % (sid, donor), flush=True)


def main(argv):
    wanted = [a for a in argv if not a.startswith("--")]
    specs = platform_specs()
    weapons = weapon_specs()
    if not wanted:
        manifest = load_json(NEW_RECORDS, {})
        wanted = list(manifest.get("platforms", [])) + list(manifest.get("weapons", []))
    sidecar = load_json(SIDECAR, {})
    rows = []
    failures = []
    for sid in wanted:
        try:
            if sid in COPIES:
                copy_asset(sid, COPIES[sid], specs, sidecar, rows)
                continue
            if sid in weapons and sid not in specs:
                row, entry = build_one(sid, weapons[sid], True)
            elif sid in specs:
                row, entry = build_one(sid, specs[sid], False)
            else:
                raise KeyError("unknown id " + sid)
            rows.append(row)
            sidecar[sid] = entry
        except Exception as exc:  # keep going, report at the end
            failures.append((sid, repr(exc)))
            print("FAILED", sid, repr(exc), flush=True)
    if rows:
        write_manifest(rows)
        SIDECAR.write_text(json.dumps(dict(sorted(sidecar.items())), indent=1) + "\n")
    print("BUILD COMPLETE %d models, %d failures" % (len(rows), len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
