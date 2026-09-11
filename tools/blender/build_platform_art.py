"""Build the platform recognition art with Blender.

Every ship, submarine and aircraft in data/platforms is modelled here from primitives, sized
from the numbers in its spec (length, mast height) plus a small table of proportions, and
rendered twice: an elevated side view for the unit panel's recognition card and a plan view for
the tactical map's close-zoom silhouette. Both are greyscale-on-alpha so the game tints them
with the identity or damage colour at draw time; the faces carry a mid-grey shade and the
Freestyle outline is white, which keeps the command-display look once modulated.

Original work throughout: these are stylised shapes that evoke a class, not blueprints.

Run with the Blender Python module (no GUI, Cycles on the CPU):

    python3 -m pip install bpy==4.2.0
    python3 tools/blender/build_platform_art.py            # everything
    python3 tools/blender/build_platform_art.py usn_ddg_arleigh_burke_iia usn_cvn_nimitz

Output: assets/platforms/<id>_profile.png and <id>_plan.png. The repository commits the PNGs,
so a game build never needs Blender; this script only runs when the art changes.
"""
import math
import os
import re
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PLATFORM_DIR = os.path.join(ROOT, "data", "platforms")
OUT_DIR = os.path.join(ROOT, "assets", "platforms")

PROFILE_SIZE = (768, 224)   # unit-panel recognition card, waterline at WATERLINE_FRACTION of height
PLAN_SIZE = (512, 512)      # map silhouette, bow to the right; the image is cut to the hull's proportions
WATERLINE_FRACTION = 0.80
SAMPLES = 24
LINE_PX = 1.7
PLAN_LINE_PX = 2.4

# --------------------------------------------------------------------------------------------
# Spec reading
# --------------------------------------------------------------------------------------------


def read_specs():
    specs = {}
    for sub in os.listdir(PLATFORM_DIR):
        d = os.path.join(PLATFORM_DIR, sub)
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if not f.endswith(".tres"):
                continue
            text = open(os.path.join(d, f)).read()

            def field(key, default):
                m = re.search(r"^%s = (.*)$" % key, text, re.M)
                if not m:
                    return default
                v = m.group(1).strip()
                if v.startswith('"'):
                    return v.strip('"')
                try:
                    return float(v)
                except ValueError:
                    return v

            spec = {
                "id": field("id", f[:-5]),
                "category": str(field("category", "")).lower(),
                "domain": str(field("domain", "surface")),
                "length_m": float(field("length_m", 0.0)),
                "mast_height_m": float(field("mast_height_m", 25.0)),
                "nation": str(field("nation", "")),
            }
            specs[spec["id"]] = spec
    return specs


# --------------------------------------------------------------------------------------------
# Mesh helpers. Ships point along +X (bow at +X), beam on Y, up on Z, waterline at z = 0.
# --------------------------------------------------------------------------------------------

_material = None
_objects = []


def material():
    global _material
    if _material is None:
        m = bpy.data.materials.new("hull")
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.85
        bsdf.inputs["Specular IOR Level"].default_value = 0.15
        _material = m
    return _material


def add_mesh(name, verts, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    mesh.update()
    mesh.materials.append(material())
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    _objects.append(obj)
    return obj


def box(x0, x1, y0, y1, z0, z1, name="box"):
    verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
             (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return add_mesh(name, verts, faces)


def cbox(cx, cy, cz, sx, sy, sz, name="box"):
    return box(cx - sx / 2, cx + sx / 2, cy - sy / 2, cy + sy / 2, cz - sz / 2, cz + sz / 2, name)


def prism(x0, x1, y0, y1, z0, z1, top_inset=0.0, name="prism"):
    """A box whose top face is inset on both sides: the sloped deckhouse of a modern hull."""
    i = top_inset
    verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
             (x0 + i, y0 + i, z1), (x1 - i, y0 + i, z1), (x1 - i, y1 - i, z1), (x0 + i, y1 - i, z1)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return add_mesh(name, verts, faces)


def cylinder(cx, cy, z0, z1, r, segs=12, name="cyl", axis="z", r_top=None):
    """Cylinder along an axis; for axis 'x' the (cx, cy) pair is (y, z) and z0..z1 runs along X."""
    rt = r if r_top is None else r_top
    verts = []
    for k, (h, rad) in enumerate(((z0, r), (z1, rt))):
        for s in range(segs):
            a = 2 * math.pi * s / segs
            u, v = math.cos(a) * rad, math.sin(a) * rad
            if axis == "z":
                verts.append((cx + u, cy + v, h))
            elif axis == "x":
                verts.append((h, cx + u, cy + v))
            else:
                verts.append((cx + u, h, cy + v))
    faces = []
    for s in range(segs):
        n = (s + 1) % segs
        faces.append((s, n, segs + n, segs + s))
    faces.append(tuple(range(segs - 1, -1, -1)))
    faces.append(tuple(range(segs, 2 * segs)))
    return add_mesh(name, verts, faces)


def revolve(profile, segs=16, name="rev"):
    """Revolve a list of (x, r) about the X axis into a closed body."""
    verts = []
    for (x, r) in profile:
        for s in range(segs):
            a = 2 * math.pi * s / segs
            verts.append((x, math.cos(a) * r, math.sin(a) * r))
    faces = []
    n = len(profile)
    for i in range(n - 1):
        for s in range(segs):
            t = (s + 1) % segs
            faces.append((i * segs + s, i * segs + t, (i + 1) * segs + t, (i + 1) * segs + s))
    faces.append(tuple(range(segs - 1, -1, -1)))
    faces.append(tuple(range((n - 1) * segs, n * segs)))
    return add_mesh(name, verts, faces)


def plate(points_xy, z0, z1, name="plate"):
    """Extrude a planar polygon (x, y) between two heights: wings, fins, decks."""
    n = len(points_xy)
    verts = [(x, y, z0) for (x, y) in points_xy] + [(x, y, z1) for (x, y) in points_xy]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    return add_mesh(name, verts, faces)


def vplate(points_xz, y0, y1, name="fin"):
    """Extrude a polygon in the (x, z) plane across Y: a vertical fin or a radar face."""
    n = len(points_xz)
    verts = [(x, y0, z) for (x, z) in points_xz] + [(x, y1, z) for (x, z) in points_xz]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, n + i, n + j, j))
    return add_mesh(name, verts, faces)


def ring_verts(x, b, d, fb, chine=1.0, flare=1.0):
    """One hull station: keel, bilge, waterline, topsides and a cambered deck, both sides."""
    star = [(0.0, -d), (0.55 * b, -0.92 * d), (0.92 * b * chine, -0.35 * d), (b, 0.0),
            (b * flare, fb * 0.55), (b * 0.96 * flare, fb), (0.0, fb + 0.12 * fb)]
    port = [(-y, z) for (y, z) in reversed(star[1:-1])]
    return [(x, y, z) for (y, z) in star + port]


def hull(L, B, draft, fb_aft, fb_fwd, stations=26, transom=0.62, fullness=0.55, bow_sharp=True,
         flare=1.0, name="hull"):
    """Loft a displacement hull. `fullness` is where the parallel middle body ends (0..1 from
    the stern); a merchant is fuller than a frigate."""
    rings = []
    per = None
    for i in range(stations + 1):
        t = i / stations
        # Half-beam along the hull.
        if t < 0.18:
            f = transom + (1.0 - transom) * math.sin(t / 0.18 * math.pi / 2)
        elif t < fullness:
            f = 1.0
        else:
            u = (t - fullness) / (1.0 - fullness)
            f = max(0.03 if bow_sharp else 0.25, 1.0 - u ** (1.9 if bow_sharp else 2.6))
        if i == stations:
            f = 0.03 if bow_sharp else 0.22
        b = B / 2 * f
        # Draft: cut the forefoot away and lift the stern a little.
        dr = draft
        if t > 0.78:
            dr = draft * (1.0 - 0.85 * ((t - 0.78) / 0.22) ** 1.6)
        if t < 0.12:
            dr = draft * (0.45 + 0.55 * t / 0.12)
        fb = fb_aft + (fb_fwd - fb_aft) * t ** 2.2
        x = -L / 2 + L * t
        r = ring_verts(x, b, max(dr, 0.05), fb, flare=flare)
        per = len(r)
        rings.append(r)
    verts = [v for r in rings for v in r]
    faces = []
    for i in range(len(rings) - 1):
        for k in range(per):
            n = (k + 1) % per
            faces.append((i * per + k, i * per + n, (i + 1) * per + n, (i + 1) * per + k))
    faces.append(tuple(range(per - 1, -1, -1)))             # transom
    last = (len(rings) - 1) * per
    faces.append(tuple(range(last, last + per)))          # stem cap (tiny)
    return add_mesh(name, verts, faces)


def deck_z(fb_aft, fb_fwd, t):
    return fb_aft + (fb_fwd - fb_aft) * t ** 2.2


def mast(x, y, z0, z1, r=0.35, yard=0.0):
    cylinder(x, y, z0, z1, r, segs=8, name="mast")
    if yard > 0:
        cbox(x, y, z0 + (z1 - z0) * 0.72, r * 2, yard, r * 1.6, name="yard")


def lattice_mast(x, y, z0, z1, base=3.0, top=1.0):
    """Four legs converging on a platform: the lattice mast of an older design."""
    for sy in (-1, 1):
        for sx in (-1, 1):
            leg = [(x + sx * base / 2, y + sy * base / 2, z0), (x + sx * top / 2, y + sy * top / 2, z1)]
            verts = [(leg[0][0] - 0.15, leg[0][1] - 0.15, z0), (leg[0][0] + 0.15, leg[0][1] + 0.15, z0),
                     (leg[1][0] + 0.15, leg[1][1] + 0.15, z1), (leg[1][0] - 0.15, leg[1][1] - 0.15, z1)]
            add_mesh("leg", verts, [(0, 1, 2, 3)])
    cbox(x, y, z1, top * 1.6, top * 1.6, 0.4, name="platform")


def gun(x, y, z, big=True, twin=False):
    s = 1.0 if big else 0.6
    cbox(x, y, z + 1.6 * s, 6.0 * s, 4.0 * s, 3.0 * s, name="turret")
    for offset in (-.65, .65) if twin else (0,):
        cylinder(y + offset*s, z + 2.4 * s, x + 3.0 * s, x + 9.5 * s, 0.25 * s, segs=6, axis="x", name="barrel")


def vls(x0, x1, y, z, w, rows=2):
    box(x0, x1, y - w / 2, y + w / 2, z, z + 0.45, name="vls")
    for i in range(1, rows):
        yy = y - w / 2 + w * i / rows
        box(x0, x1, yy - 0.05, yy + 0.05, z + 0.45, z + 0.55, name="vls_line")


def radar_face(x, y, z, w, h, facing=1, tilt=0.35):
    """A phased-array face: an octagonal plate leaning back against a deckhouse."""
    pts = [(-w * 0.5 + w * 0.2, 0), (w * 0.5 - w * 0.2, 0), (w * 0.5, h * 0.2), (w * 0.5, h * 0.8),
           (w * 0.5 - w * 0.2, h), (-w * 0.5 + w * 0.2, h), (-w * 0.5, h * 0.8), (-w * 0.5, h * 0.2)]
    verts = []
    for (u, v) in pts:
        verts.append((x + u, y, z + v))
        verts.append((x + u, y + facing * 0.35, z + v - tilt * 0))
    n = len(pts)
    faces = [tuple(range(0, 2 * n, 2))[::-1], tuple(range(1, 2 * n, 2))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((2 * i, 2 * i + 1, 2 * j + 1, 2 * j))
    add_mesh("array", verts, faces)


def dome(x, y, z, r, segs=10):
    prof = [(0.0, 0.0)]
    for i in range(1, segs):
        a = math.pi * i / segs
        prof.append((r - r * math.cos(a), r * math.sin(a)))
    prof.append((2 * r, 0.0))
    o = revolve(prof, segs=12, name="dome")
    o.location = (x - r, y, z)
    o.rotation_euler = (0.0, -math.pi / 2, 0.0)
    return o


def hangar(x0, x1, B, z, h, name="hangar"):
    prism(x0, x1, -B * 0.42, B * 0.42, z, z + h, top_inset=0.6, name=name)


def funnel(x, y, z, h, w=2.4, d=3.6, rake=0.0):
    verts = [(x - d / 2, y - w / 2, z), (x + d / 2, y - w / 2, z), (x + d / 2, y + w / 2, z), (x - d / 2, y + w / 2, z),
             (x - d / 2 + rake, y - w / 2, z + h), (x + d / 2 + rake, y - w / 2, z + h),
             (x + d / 2 + rake, y + w / 2, z + h), (x - d / 2 + rake, y + w / 2, z + h)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    add_mesh("funnel", verts, faces)


def boat(x, y, z):
    cbox(x, y, z + 0.6, 7.0, 2.4, 1.2, name="boat")


def ciws(x, y, z):
    cylinder(x, y, z, z + 1.6, 1.0, segs=8, name="ciws")
    dome(x, y, z + 1.6, 1.1)


# --------------------------------------------------------------------------------------------
# Classes. Each builder takes the spec and returns nothing; the scene is cleared per platform.
# --------------------------------------------------------------------------------------------


def build_aegis_destroyer(L, flight_iii=False):
    B = L * 0.13
    fa, ff, dr = L * 0.045, L * 0.075, L * 0.04
    hull(L, B, dr, fa, ff, flare=1.02)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    # Forward deckhouse with the SPY faces, bridge on top.
    prism(x(0.40), x(0.60), -B * 0.40, B * 0.40, d(0.5), d(0.5) + 9.5, top_inset=0.8, name="deckhouse")
    cbox(x(0.50), 0, d(0.5) + 11.5, L * 0.10, B * 0.55, 4.0, name="bridge")
    w = 5.5 if flight_iii else 4.5
    radar_face(x(0.585), -B * 0.40, d(0.5) + 3.0, w, w, facing=-1)
    radar_face(x(0.585), B * 0.40, d(0.5) + 3.0, w, w, facing=1)
    mast(x(0.535), 0, d(0.5) + 13.5, d(0.5) + 26.0, r=0.45, yard=6.0)
    # Twin raked stacks and the aft deckhouse with the helicopter hangar.
    funnel(x(0.38), 0, d(0.4) + 6.0, 6.0, w=3.2, d=4.0, rake=-1.0)
    funnel(x(0.30), 0, d(0.3) + 6.0, 6.0, w=3.2, d=4.0, rake=-1.0)
    prism(x(0.26), x(0.40), -B * 0.36, B * 0.36, d(0.33), d(0.33) + 6.0, top_inset=0.6, name="midhouse")
    hangar(x(0.10), x(0.24), B, d(0.17), 6.5)
    mast(x(0.24), 0, d(0.2) + 6.5, d(0.2) + 16.0, r=0.35)
    gun(x(0.76), 0, d(0.76), big=True)
    vls(x(0.64), x(0.72), 0, d(0.68), B * 0.55, rows=3)
    vls(x(0.25), x(0.32), 0, d(0.28) + 6.1, B * 0.6, rows=4)
    ciws(x(0.235), 0, d(0.2) + 6.5)
    for s in (-1, 1):
        boat(x(0.36), s * B * 0.42, d(0.36))


def build_ticonderoga(L):
    B = L * 0.096
    fa, ff, dr = L * 0.040, L * 0.075, L * 0.038
    hull(L, B, dr, fa, ff)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    # The long boxy superstructure of a converted destroyer hull, two blocks of arrays.
    box(x(0.30), x(0.68), -B * 0.42, B * 0.42, d(0.5), d(0.5) + 7.0, name="deckhouse")
    box(x(0.47), x(0.64), -B * 0.36, B * 0.36, d(0.5) + 7.0, d(0.5) + 12.0, name="fwd_block")
    radar_face(x(0.63), -B * 0.42, d(0.5) + 3.5, 4.2, 4.2, facing=-1)
    radar_face(x(0.63), B * 0.42, d(0.5) + 3.5, 4.2, 4.2, facing=1)
    box(x(0.28), x(0.40), -B * 0.36, B * 0.36, d(0.5) + 7.0, d(0.5) + 12.0, name="aft_block")
    radar_face(x(0.295), -B * 0.42, d(0.5) + 3.5, 4.2, 4.2, facing=-1)
    radar_face(x(0.295), B * 0.42, d(0.5) + 3.5, 4.2, 4.2, facing=1)
    lattice_mast(x(0.56), 0, d(0.5) + 12.0, d(0.5) + 27.0, base=4.0, top=1.4)
    lattice_mast(x(0.35), 0, d(0.5) + 12.0, d(0.5) + 24.0, base=3.5, top=1.2)
    funnel(x(0.55), 0, d(0.5) + 12.0, 4.5, w=3.0, d=4.0)
    funnel(x(0.34), 0, d(0.5) + 12.0, 4.5, w=3.0, d=4.0)
    hangar(x(0.10), x(0.28), B, d(0.17), 6.0)
    gun(x(0.78), 0, d(0.78), big=True)
    gun(x(0.06), 0, d(0.06), big=True)
    vls(x(0.68), x(0.76), 0, d(0.72), B * 0.6, rows=3)
    vls(x(0.19), x(0.27), 0, d(0.21) + 6.0, B * 0.5, rows=3)
    ciws(x(0.72), -B * 0.3, d(0.5) + 7.0)
    ciws(x(0.30), B * 0.3, d(0.5) + 7.0)


def build_constellation(L):
    B = L * 0.125
    fa, ff, dr = L * 0.050, L * 0.078, L * 0.035
    hull(L, B, dr, fa, ff, flare=1.0)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    # A stealthy slab superstructure running most of the length, one enclosed mast.
    prism(x(0.22), x(0.66), -B * 0.44, B * 0.44, d(0.45), d(0.45) + 7.5, top_inset=1.2, name="deckhouse")
    prism(x(0.44), x(0.62), -B * 0.34, B * 0.34, d(0.45) + 7.5, d(0.45) + 12.5, top_inset=0.8, name="bridge")
    prism(x(0.46), x(0.53), -2.0, 2.0, d(0.45) + 12.5, d(0.45) + 24.0, top_inset=0.6, name="mast_tower")
    radar_face(x(0.53), -B * 0.34, d(0.45) + 8.5, 3.8, 3.8, facing=-1)
    radar_face(x(0.53), B * 0.34, d(0.45) + 8.5, 3.8, 3.8, facing=1)
    funnel(x(0.36), 0, d(0.45) + 7.5, 3.5, w=3.0, d=5.0, rake=-0.6)
    hangar(x(0.10), x(0.22), B, d(0.17), 6.5)
    gun(x(0.78), 0, d(0.78), big=False)
    vls(x(0.68), x(0.75), 0, d(0.7), B * 0.5, rows=2)
    dome(x(0.16), 0, d(0.17) + 6.5, 1.4)


def build_type45(L):
    B = L * 0.14
    fa, ff, dr = L * 0.050, L * 0.085, L * 0.036
    hull(L, B, dr, fa, ff, flare=0.98)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    # The tall SAMPSON tower forward with its sphere, a pyramid aft for the long-range set.
    prism(x(0.30), x(0.66), -B * 0.44, B * 0.44, d(0.45), d(0.45) + 7.5, top_inset=1.0, name="deckhouse")
    prism(x(0.50), x(0.64), -B * 0.36, B * 0.36, d(0.45) + 7.5, d(0.45) + 12.0, top_inset=0.8, name="bridge")
    prism(x(0.52), x(0.60), -3.0, 3.0, d(0.45) + 12.0, d(0.45) + 30.0, top_inset=1.6, name="sampson_tower")
    dome(x(0.56), 0, d(0.45) + 30.0, 3.0)
    prism(x(0.30), x(0.40), -3.4, 3.4, d(0.45) + 7.5, d(0.45) + 19.0, top_inset=2.2, name="aft_pyramid")
    funnel(x(0.44), 0, d(0.45) + 7.5, 4.0, w=2.6, d=4.0)
    hangar(x(0.10), x(0.30), B, d(0.17), 7.0)
    gun(x(0.77), 0, d(0.77), big=True)
    vls(x(0.66), x(0.74), 0, d(0.7), B * 0.5, rows=3)
    ciws(x(0.20), -B * 0.36, d(0.17) + 7.0)


def build_european_frigate(L, apar=True):
    B = L * 0.125
    fa, ff, dr = L * 0.048, L * 0.078, L * 0.036
    hull(L, B, dr, fa, ff)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    prism(x(0.24), x(0.68), -B * 0.44, B * 0.44, d(0.45), d(0.45) + 6.5, top_inset=1.0, name="deckhouse")
    prism(x(0.50), x(0.66), -B * 0.36, B * 0.36, d(0.45) + 6.5, d(0.45) + 11.0, top_inset=0.7, name="bridge")
    if apar:
        # A cubic multifunction array block on a short mast and a tall lattice for the volume search set.
        prism(x(0.54), x(0.60), -2.4, 2.4, d(0.45) + 11.0, d(0.45) + 16.0, top_inset=0.3, name="apar_mast")
        cbox(x(0.57), 0, d(0.45) + 17.5, 4.0, 4.0, 3.0, name="apar_block")
        prism(x(0.36), x(0.42), -3.0, 3.0, d(0.45) + 6.5, d(0.45) + 22.0, top_inset=2.0, name="search_pyramid")
        cbox(x(0.39), 0, d(0.45) + 23.0, 6.0, 1.0, 2.2, name="search_array")
    funnel(x(0.45), 0, d(0.45) + 6.5, 4.0, w=2.8, d=4.5, rake=-0.6)
    hangar(x(0.10), x(0.24), B, d(0.17), 6.0)
    gun(x(0.78), 0, d(0.78), big=False)
    vls(x(0.68), x(0.75), 0, d(0.7), B * 0.45, rows=2)
    for s in (-1, 1):
        boat(x(0.34), s * B * 0.44, d(0.34) + 3.0)


def build_gorshkov(L):
    B = L * 0.12
    fa, ff, dr = L * 0.046, L * 0.078, L * 0.035
    hull(L, B, dr, fa, ff, flare=0.97)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    prism(x(0.26), x(0.70), -B * 0.44, B * 0.44, d(0.45), d(0.45) + 6.0, top_inset=1.4, name="deckhouse")
    prism(x(0.48), x(0.68), -B * 0.36, B * 0.36, d(0.45) + 6.0, d(0.45) + 11.0, top_inset=1.0, name="bridge")
    # A single tall faceted mast carrying the fixed arrays, well forward.
    prism(x(0.50), x(0.60), -3.6, 3.6, d(0.45) + 11.0, d(0.45) + 26.0, top_inset=2.4, name="pyramid_mast")
    prism(x(0.36), x(0.44), -B * 0.3, B * 0.3, d(0.45) + 6.0, d(0.45) + 10.5, top_inset=0.8, name="aft_house")
    funnel(x(0.40), 0, d(0.45) + 10.5, 3.0, w=2.4, d=3.4)
    hangar(x(0.10), x(0.26), B, d(0.17), 6.0)
    gun(x(0.80), 0, d(0.80), big=True)
    vls(x(0.68), x(0.77), 0, d(0.72), B * 0.5, rows=4)


def build_slava(L):
    B = L * 0.112
    fa, ff, dr = L * 0.036, L * 0.062, L * 0.045
    hull(L, B, dr, fa, ff)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    # Eight pairs of huge fixed launch tubes either side of the forward superstructure.
    for i in range(8):
        xx = x(0.46 + i * 0.037)
        for s in (-1, 1):
            o = cylinder(s * B * 0.36, d(0.5) + 3.2, xx - 5.5, xx + 5.5, 1.7, segs=8, axis="x", name="tube")
            o.rotation_euler = (0.0, -0.32, 0.0)
            o.location = (xx * 0.0, 0.0, 0.0)
    box(x(0.34), x(0.62), -B * 0.30, B * 0.30, d(0.5), d(0.5) + 6.5, name="deckhouse")
    box(x(0.50), x(0.62), -B * 0.26, B * 0.26, d(0.5) + 6.5, d(0.5) + 11.0, name="bridge")
    lattice_mast(x(0.55), 0, d(0.5) + 11.0, d(0.5) + 30.0, base=4.5, top=1.6)
    cbox(x(0.55), 0, d(0.5) + 31.0, 5.0, 1.2, 2.0, name="top_pair")
    funnel(x(0.41), -2.2, d(0.5) + 6.5, 9.0, w=2.6, d=4.0)
    funnel(x(0.41), 2.2, d(0.5) + 6.5, 9.0, w=2.6, d=4.0)
    # The big fire-control dome aft on its own tower, then the hangar and the helo deck.
    prism(x(0.22), x(0.30), -3.5, 3.5, d(0.26), d(0.26) + 12.0, top_inset=0.6, name="aft_tower")
    dome(x(0.26), 0, d(0.26) + 12.0, 3.4)
    lattice_mast(x(0.33), 0, d(0.3) + 6.5, d(0.3) + 22.0, base=3.5, top=1.2)
    hangar(x(0.08), x(0.20), B, d(0.14), 5.5)
    gun(x(0.80), 0, d(0.80), big=True, twin=True)
    for i in range(8):
        cylinder(x(0.08 + (i % 4) * 0.03), (-1 if i < 4 else 1) * B * 0.3, d(0.1) + 5.5, d(0.1) + 6.3, 1.1, segs=8, name="sam_silo")


def build_udaloy(L):
    B = L * 0.117
    fa, ff, dr = L * 0.040, L * 0.066, L * 0.040
    hull(L, B, dr, fa, ff)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    box(x(0.34), x(0.64), -B * 0.36, B * 0.36, d(0.5), d(0.5) + 6.5, name="deckhouse")
    box(x(0.50), x(0.63), -B * 0.30, B * 0.30, d(0.5) + 6.5, d(0.5) + 11.0, name="bridge")
    # Two tall lattice masts and two funnels: the cluttered profile of the older generation.
    lattice_mast(x(0.53), 0, d(0.5) + 11.0, d(0.5) + 30.0, base=4.5, top=1.6)
    cbox(x(0.53), 0, d(0.5) + 31.2, 6.0, 1.4, 2.4, name="top_plate")
    funnel(x(0.45), 0, d(0.5) + 6.5, 7.0, w=2.8, d=4.5)
    lattice_mast(x(0.36), 0, d(0.5) + 6.5, d(0.5) + 24.0, base=4.0, top=1.4)
    funnel(x(0.30), 0, d(0.35) + 6.0, 6.0, w=2.8, d=4.5)
    box(x(0.26), x(0.34), -B * 0.34, B * 0.34, d(0.35), d(0.35) + 6.0, name="aft_house")
    hangar(x(0.10), x(0.26), B, d(0.17), 6.0)
    cbox(x(0.18), 0, d(0.17) + 6.0, 6.0, 6.0, 3.0, name="hangar_top")
    gun(x(0.80), 0, d(0.80), big=True)
    gun(x(0.74), 0, d(0.74) + 1.0, big=True)
    for s in (-1, 1):
        o = cylinder(s * B * 0.36, d(0.66) + 2.5, x(0.64), x(0.70), 1.4, segs=8, axis="x", name="asw_tube")
        o.rotation_euler = (0.0, -0.25, 0.0)


def build_steregushchiy(L):
    B = L * 0.125
    fa, ff, dr = L * 0.046, L * 0.075, L * 0.036
    hull(L, B, dr, fa, ff, flare=0.97)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    # One long faceted block with an integrated mast; hangar built into the aft end.
    prism(x(0.16), x(0.68), -B * 0.44, B * 0.44, d(0.45), d(0.45) + 6.0, top_inset=1.5, name="deckhouse")
    prism(x(0.46), x(0.66), -B * 0.34, B * 0.34, d(0.45) + 6.0, d(0.45) + 10.5, top_inset=0.9, name="bridge")
    prism(x(0.48), x(0.56), -3.0, 3.0, d(0.45) + 10.5, d(0.45) + 22.0, top_inset=1.8, name="integrated_mast")
    cbox(x(0.52), 0, d(0.45) + 23.0, 4.4, 1.0, 1.6, name="mast_top")
    funnel(x(0.36), 0, d(0.45) + 6.0, 2.5, w=2.4, d=4.0)
    gun(x(0.80), 0, d(0.80), big=False)
    vls(x(0.69), x(0.76), 0, d(0.72), B * 0.4, rows=2)


def build_buyan(L):
    B = L * 0.15
    fa, ff, dr = L * 0.045, L * 0.070, L * 0.030
    hull(L, B, dr, fa, ff, transom=0.75)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    prism(x(0.30), x(0.70), -B * 0.42, B * 0.42, d(0.45), d(0.45) + 5.0, top_inset=1.0, name="deckhouse")
    prism(x(0.48), x(0.66), -B * 0.32, B * 0.32, d(0.45) + 5.0, d(0.45) + 8.5, top_inset=0.7, name="bridge")
    prism(x(0.52), x(0.58), -2.0, 2.0, d(0.45) + 8.5, d(0.45) + 16.0, top_inset=1.0, name="mast")
    gun(x(0.80), 0, d(0.80), big=False)
    vls(x(0.14), x(0.28), 0, d(0.2), B * 0.4, rows=2)
    cbox(x(0.36), 0, d(0.45) + 5.0, 3.0, 3.0, 2.2, name="stack")


def build_braunschweig(L):
    B = L * 0.15
    fa, ff, dr = L * 0.050, L * 0.078, L * 0.038
    hull(L, B, dr, fa, ff, flare=0.96)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    prism(x(0.22), x(0.70), -B * 0.44, B * 0.44, d(0.45), d(0.45) + 5.5, top_inset=1.6, name="deckhouse")
    prism(x(0.48), x(0.68), -B * 0.34, B * 0.34, d(0.45) + 5.5, d(0.45) + 9.5, top_inset=0.9, name="bridge")
    prism(x(0.50), x(0.58), -2.6, 2.6, d(0.45) + 9.5, d(0.45) + 19.0, top_inset=1.6, name="mast")
    gun(x(0.80), 0, d(0.80), big=False)
    cbox(x(0.36), 0, d(0.45) + 5.5, 4.0, 4.0, 2.4, name="stack")
    cbox(x(0.16), 0, d(0.2) + 1.0, 4.0, 3.0, 2.0, name="ram_launcher")


def build_carrier(L):
    B = L * 0.12   # hull beam; the flight deck overhangs it widely
    fa, ff, dr = L * 0.062, L * 0.070, L * 0.036
    hull(L, B, dr, fa, ff, fullness=0.62, transom=0.85)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    z = d(0.5) + 1.0
    # Flight deck: rectangular main deck with the angled landing area sponsoned to port.
    deck = [(x(0.0), -B * 0.62), (x(0.94), -B * 0.62), (x(0.985), -B * 0.35), (x(0.985), B * 0.35),
            (x(0.94), B * 0.66), (x(0.72), B * 0.66), (x(0.68), B * 0.78), (x(0.24), B * 0.90),
            (x(0.16), B * 0.90), (x(0.12), B * 0.78), (x(0.0), B * 0.66)]
    plate(deck, z, z + 2.6, name="flight_deck")
    # Island to starboard, well aft of midships, with the mast on top.
    prism(x(0.56), x(0.68), -B * 0.60, -B * 0.42, z + 2.6, z + 12.0, top_inset=0.6, name="island")
    box(x(0.60), x(0.665), -B * 0.58, -B * 0.44, z + 12.0, z + 17.0, name="island_top")
    radar_face(x(0.665), -B * 0.44, z + 6.0, 4.0, 4.0, facing=1)
    mast(x(0.63), -B * 0.51, z + 17.0, z + 34.0, r=0.5, yard=8.0)
    cbox(x(0.575), -B * 0.51, z + 20.0, 1.2, 8.0, 2.4, name="air_search")
    # Catapult tracks and the aft round-down, drawn as thin raised strips.
    for yy in (-B * 0.15, B * 0.15):
        box(x(0.70), x(0.96), yy - 0.4, yy + 0.4, z + 2.6, z + 2.9, name="cat")
    box(x(0.20), x(0.62), B * 0.42, B * 0.43, z + 2.6, z + 2.9, name="angle_edge")
    # Deck-edge lifts.
    for xx in (x(0.50), x(0.76), x(0.86)):
        box(xx - L * 0.03, xx + L * 0.03, -B * 0.66, -B * 0.60, z, z + 2.6, name="lift")
    box(x(0.30), x(0.36), B * 0.66, B * 0.78, z, z + 2.6, name="lift")


def build_merchant(L):
    B = L * 0.16
    fa, ff, dr = L * 0.062, L * 0.075, L * 0.055
    hull(L, B, dr, fa, ff, fullness=0.80, transom=0.75, bow_sharp=False, stations=30)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    # A bulk carrier: accommodation block right aft, a row of raised hatch covers forward.
    box(x(0.04), x(0.16), -B * 0.40, B * 0.40, d(0.1), d(0.1) + 10.0, name="accommodation")
    box(x(0.05), x(0.15), -B * 0.44, B * 0.44, d(0.1) + 10.0, d(0.1) + 12.5, name="bridge")
    funnel(x(0.06), 0, d(0.1) + 12.5, 5.0, w=3.0, d=5.0, rake=-1.0)
    mast(x(0.10), 0, d(0.1) + 12.5, d(0.1) + 20.0, r=0.4, yard=5.0)
    for i in range(6):
        t0 = 0.20 + i * 0.125
        box(x(t0), x(t0 + 0.10), -B * 0.30, B * 0.30, d(t0), d(t0) + 1.8, name="hatch")
    mast(x(0.94), 0, d(0.94), d(0.94) + 8.0, r=0.3)


def build_replenishment(L):
    B = L * 0.14
    fa, ff, dr = L * 0.058, L * 0.075, L * 0.045
    hull(L, B, dr, fa, ff, fullness=0.70, transom=0.7, bow_sharp=True, stations=30)
    d = lambda t: deck_z(fa, ff, t)
    x = lambda t: -L / 2 + L * t
    # Fleet oiler: aft superstructure and hangar, replenishment gantries amidships.
    prism(x(0.06), x(0.24), -B * 0.42, B * 0.42, d(0.15), d(0.15) + 9.0, top_inset=0.8, name="accommodation")
    box(x(0.08), x(0.22), -B * 0.44, B * 0.44, d(0.15) + 9.0, d(0.15) + 12.0, name="bridge")
    funnel(x(0.09), 0, d(0.15) + 12.0, 4.0, w=3.0, d=4.5, rake=-0.8)
    mast(x(0.18), 0, d(0.15) + 12.0, d(0.15) + 20.0, r=0.4, yard=5.0)
    for t in (0.38, 0.58):
        for s in (-1, 1):
            mast(x(t), s * B * 0.36, d(t), d(t) + 18.0, r=0.5)
        cbox(x(t), 0, d(t) + 18.0, 1.6, B * 0.8, 1.2, name="gantry")
        cbox(x(t), 0, d(t) + 9.0, 1.4, B * 0.7, 0.8, name="gantry_low")
    box(x(0.72), x(0.86), -B * 0.34, B * 0.34, d(0.8), d(0.8) + 2.0, name="fwd_house")
    mast(x(0.88), 0, d(0.88), d(0.88) + 9.0, r=0.3)


def build_submarine(L, kind):
    R = L * (0.075 if kind == "kilo" else 0.045)
    prof = []
    n = 12
    for i in range(n + 1):
        t = i / n
        prof.append((-L / 2 + L * 0.28 * t, R * math.sin(t * math.pi / 2) ** 0.7))
    prof.append((L * 0.30, R))
    for i in range(1, n + 1):
        t = i / n
        prof.append((L * 0.30 + L * 0.20 * t, R * math.cos(t * math.pi / 2) ** 0.55))
    body = revolve(prof, segs=20, name="pressure_hull")
    body.location = (0.0, 0.0, 0.0)
    # Sail, planes, rudders and (for the boats that have one) a pump-jet shroud.
    if kind == "kilo":
        sail = [(L * 0.02, R * 0.9), (L * 0.18, R * 0.9), (L * 0.20, R * 2.1), (L * 0.06, R * 2.2), (L * 0.02, R * 2.0)]
        vplate(sail, -R * 0.35, R * 0.35, name="sail")
        plate([(L * 0.09, -R * 1.5), (L * 0.15, -R * 1.5), (L * 0.15, R * 1.5), (L * 0.09, R * 1.5)], R * 1.7, R * 1.85, name="sail_planes")
    elif kind == "yasen":
        sail = [(-L * 0.06, R * 0.9), (L * 0.16, R * 0.9), (L * 0.14, R * 2.0), (-L * 0.02, R * 2.0)]
        vplate(sail, -R * 0.4, R * 0.4, name="sail")
        plate([(-L * 0.36, -R * 1.9), (-L * 0.32, -R * 1.9), (-L * 0.32, R * 1.9), (-L * 0.36, R * 1.9)], -R * 0.15, R * 0.15, name="stern_planes")
        vplate([(-L * 0.37, R * 0.6), (-L * 0.31, R * 0.7), (-L * 0.30, R * 2.0), (-L * 0.35, R * 2.1)], -R * 0.15, R * 0.15, name="upper_rudder")
    else:  # virginia
        sail = [(L * 0.04, R * 0.9), (L * 0.18, R * 0.9), (L * 0.17, R * 2.1), (L * 0.06, R * 2.1)]
        vplate(sail, -R * 0.35, R * 0.35, name="sail")
        plate([(L * 0.09, -R * 1.7), (L * 0.14, -R * 1.7), (L * 0.14, R * 1.7), (L * 0.09, R * 1.7)], R * 1.6, R * 1.75, name="sail_planes")
        plate([(-L * 0.38, -R * 1.9), (-L * 0.33, -R * 1.9), (-L * 0.33, R * 1.9), (-L * 0.38, R * 1.9)], -R * 0.15, R * 0.15, name="stern_planes")
        vplate([(-L * 0.39, R * 0.5), (-L * 0.32, R * 0.6), (-L * 0.32, R * 2.0), (-L * 0.37, R * 2.1)], -R * 0.15, R * 0.15, name="upper_rudder")
        o = cylinder(0.0, 0.0, -L * 0.50, -L * 0.45, R * 0.55, segs=14, axis="x", name="pumpjet", r_top=R * 0.4)
    vplate([(-L * 0.36, -R * 0.6), (-L * 0.30, -R * 0.7), (-L * 0.30, -R * 1.6), (-L * 0.35, -R * 1.7)], -R * 0.15, R * 0.15, name="lower_rudder")
    if kind == "kilo":
        plate([(-L * 0.34, -R * 1.5), (-L * 0.30, -R * 1.5), (-L * 0.30, R * 1.5), (-L * 0.34, R * 1.5)], -R * 0.15, R * 0.15, name="stern_planes")


def fuselage(L, r, nose=0.22, tail=0.35, segs=14, taper=0.35):
    prof = []
    n = 8
    for i in range(n + 1):
        t = i / n
        prof.append((L / 2 - L * nose * t, r * math.sin(t * math.pi / 2) ** 0.8))
    prof.append((-L / 2 + L * tail, r))
    for i in range(1, n + 1):
        t = i / n
        prof.append((-L / 2 + L * tail * (1 - t), r * (1 - (1 - taper) * math.sin(t * math.pi / 2))))
    return revolve(prof, segs=segs, name="fuselage")


def wing(L, span, root, tip, sweep, x_root, z, dihedral=0.0, thickness=0.30):
    """A pair of trapezoidal wings. `x_root` is the leading-edge X at the root; sweep is the
    leading-edge X offset at the tip; both in metres."""
    for s in (-1, 1):
        pts = [(x_root, 0.0), (x_root - root, 0.0), (x_root - sweep - tip, s * span / 2), (x_root - sweep, s * span / 2)]
        o = plate(pts, z - thickness / 2, z + thickness / 2, name="wing")
        if dihedral:
            o.rotation_euler = (s * dihedral, 0.0, 0.0)


def fin(x_le, root, tip, height, sweep, y=0.0, cant=0.0, thickness=0.25):
    pts = [(x_le, 0.0), (x_le - root, 0.0), (x_le - sweep - tip, height), (x_le - sweep, height)]
    o = vplate(pts, y - thickness / 2, y + thickness / 2, name="fin")
    o.rotation_euler = (cant, 0.0, 0.0)
    o.location = (0.0, y - y * math.cos(cant), 0.0)
    return o


def engine_pod(x0, x1, y, z, r):
    cylinder(y, z, x0, x1, r, segs=10, axis="x", name="engine")


def build_fighter(L, kind):
    """Twin-tail naval fighter family. kind: hornet | growler | flanker | foxhound."""
    if kind in ("hornet", "growler"):
        L = L or 18.3
        fuselage(L, L * 0.055, nose=0.30, tail=0.30, taper=0.55)
        span = L * 0.68
        # LERX-and-trapezoid wing, canted twin fins, slab tails, two engines close together.
        for s in (-1, 1):
            plate([(L * 0.05, 0), (-L * 0.28, 0), (-L * 0.24, s * span / 2), (-L * 0.12, s * span / 2)], -0.15, 0.15, name="wing")
            plate([(L * 0.30, s * L * 0.04), (L * 0.05, s * L * 0.04), (L * 0.02, s * L * 0.12)], -0.14, 0.14, name="lerx")
            plate([(-L * 0.36, s * L * 0.03), (-L * 0.47, s * L * 0.03), (-L * 0.47, s * L * 0.2), (-L * 0.41, s * L * 0.2)], -0.12, 0.12, name="stab")
            fin(-L * 0.20, L * 0.16, L * 0.06, L * 0.14, L * 0.10, y=s * L * 0.06, cant=-s * 0.35)
            engine_pod(-L * 0.50, -L * 0.05, s * L * 0.035, -0.4, L * 0.028)
            if kind == "growler":
                cylinder(s * span / 2, 0.0, -L * 0.28, -L * 0.10, 0.5, segs=8, axis="x", name="wingtip_pod")
                cylinder(s * L * 0.22, -1.0, -L * 0.24, -L * 0.06, 0.55, segs=8, axis="x", name="jammer_pod")
        cbox(L * 0.20, 0.0, L * 0.05, L * 0.16, L * 0.06, L * 0.05, name="canopy")
    elif kind == "flanker":
        L = L or 21.9
        fuselage(L, L * 0.05, nose=0.32, tail=0.28, taper=0.5)
        span = L * 0.68
        for s in (-1, 1):
            plate([(L * 0.02, 0), (-L * 0.30, 0), (-L * 0.28, s * span / 2), (-L * 0.16, s * span / 2)], -0.15, 0.15, name="wing")
            plate([(L * 0.32, s * L * 0.04), (L * 0.02, s * L * 0.04), (-L * 0.02, s * L * 0.13)], -0.14, 0.14, name="lerx")
            plate([(-L * 0.34, s * L * 0.05), (-L * 0.46, s * L * 0.05), (-L * 0.46, s * L * 0.22), (-L * 0.40, s * L * 0.22)], -0.12, 0.12, name="stab")
            fin(-L * 0.24, L * 0.18, L * 0.06, L * 0.17, L * 0.10, y=s * L * 0.10)
            engine_pod(-L * 0.50, -L * 0.10, s * L * 0.07, -0.6, L * 0.035)
        cbox(L * 0.20, 0.0, L * 0.05, L * 0.16, L * 0.06, L * 0.05, name="canopy")
    else:  # foxhound: long, straight leading edge, big square intakes
        L = L or 22.7
        fuselage(L, L * 0.05, nose=0.34, tail=0.24, taper=0.6)
        span = L * 0.58
        for s in (-1, 1):
            plate([(L * 0.0, 0), (-L * 0.30, 0), (-L * 0.28, s * span / 2), (-L * 0.20, s * span / 2)], -0.15, 0.15, name="wing")
            plate([(-L * 0.36, s * L * 0.07), (-L * 0.48, s * L * 0.07), (-L * 0.48, s * L * 0.20), (-L * 0.42, s * L * 0.20)], -0.12, 0.12, name="stab")
            fin(-L * 0.28, L * 0.16, L * 0.05, L * 0.15, L * 0.09, y=s * L * 0.08, cant=-s * 0.12)
            cbox(-L * 0.10, s * L * 0.08, -0.4, L * 0.55, L * 0.07, L * 0.06, name="intake")
        cbox(L * 0.22, 0.0, L * 0.05, L * 0.14, L * 0.05, L * 0.04, name="canopy")
        cbox(-L * 0.02, 0.0, -L * 0.07, L * 0.32, L * 0.05, L * 0.05, name="missile")


def build_bomber(L):
    # Swing-wing supersonic bomber: long pointed nose, wide fixed glove, wings swept mid-way.
    fuselage(L, L * 0.045, nose=0.30, tail=0.30, taper=0.4)
    span = L * 0.74
    for s in (-1, 1):
        plate([(L * 0.12, 0), (-L * 0.20, 0), (-L * 0.26, s * L * 0.16), (-L * 0.10, s * L * 0.16)], -0.2, 0.2, name="glove")
        plate([(-L * 0.10, s * L * 0.16), (-L * 0.26, s * L * 0.16), (-L * 0.40, s * span / 2), (-L * 0.34, s * span / 2)], -0.15, 0.15, name="wing")
        plate([(-L * 0.38, s * L * 0.04), (-L * 0.48, s * L * 0.04), (-L * 0.50, s * L * 0.18), (-L * 0.45, s * L * 0.18)], -0.12, 0.12, name="stab")
        engine_pod(-L * 0.50, -L * 0.05, s * L * 0.05, -0.5, L * 0.03)
        cbox(-L * 0.05, s * L * 0.20, -0.5, L * 0.22, L * 0.05, L * 0.03, name="missile")
    fin(-L * 0.30, L * 0.20, L * 0.06, L * 0.15, L * 0.12)


def build_patrol(L, kind):
    """Big multi-engine maritime aircraft. kind: bear | poseidon | hawkeye."""
    if kind == "bear":
        fuselage(L, L * 0.028, nose=0.16, tail=0.36, taper=0.3)
        span = L * 0.96
        for s in (-1, 1):
            plate([(L * 0.14, 0), (-L * 0.02, 0), (-L * 0.16, s * span / 2), (-L * 0.10, s * span / 2)], -0.2, 0.2, name="wing")
            plate([(-L * 0.40, s * L * 0.02), (-L * 0.48, s * L * 0.02), (-L * 0.50, s * L * 0.14), (-L * 0.46, s * L * 0.14)], -0.12, 0.12, name="stab")
            for k, yy in enumerate((L * 0.09, L * 0.20)):
                xx = L * 0.10 - yy * 0.35
                engine_pod(xx - L * 0.10, xx + L * 0.02, s * yy, -0.2, L * 0.016)
                cylinder(s * yy, -0.2, xx + L * 0.02, xx + L * 0.03, L * 0.05, segs=12, axis="x", name="prop_disc")
        fin(-L * 0.30, L * 0.16, L * 0.05, L * 0.15, L * 0.10)
        cylinder(0.0, -L * 0.03, -L * 0.20, -L * 0.14, L * 0.02, segs=10, axis="x", name="pod")
    elif kind == "poseidon":
        fuselage(L, L * 0.048, nose=0.14, tail=0.30, taper=0.2)
        span = L * 0.94
        for s in (-1, 1):
            plate([(L * 0.10, 0), (-L * 0.08, 0), (-L * 0.28, s * span / 2), (-L * 0.24, s * span / 2)], -0.25, 0.25, name="wing")
            plate([(-L * 0.36, s * L * 0.03), (-L * 0.46, s * L * 0.03), (-L * 0.50, s * L * 0.18), (-L * 0.46, s * L * 0.18)], -0.12, 0.12, name="stab")
            engine_pod(-L * 0.10, L * 0.02, s * L * 0.15, -L * 0.05, L * 0.03)
        fin(-L * 0.24, L * 0.20, L * 0.07, L * 0.18, L * 0.14)
        cbox(-L * 0.20, 0.0, -L * 0.045, L * 0.16, L * 0.05, L * 0.02, name="bay")
    else:  # hawkeye
        L = L or 17.6
        fuselage(L, L * 0.055, nose=0.16, tail=0.32, taper=0.3)
        span = L * 1.4
        for s in (-1, 1):
            plate([(L * 0.08, 0), (-L * 0.08, 0), (-L * 0.10, s * span / 2), (L * 0.02, s * span / 2)], -0.2, 0.2, name="wing")
            engine_pod(-L * 0.08, L * 0.16, s * L * 0.18, 0.0, L * 0.035)
            cylinder(s * L * 0.18, 0.0, L * 0.16, L * 0.17, L * 0.09, segs=12, axis="x", name="prop_disc")
            plate([(-L * 0.36, 0), (-L * 0.46, 0), (-L * 0.46, s * L * 0.25), (-L * 0.40, s * L * 0.25)], -0.12, 0.12, name="stab")
            fin(-L * 0.38, L * 0.08, L * 0.05, L * 0.10, L * 0.02, y=s * L * 0.25)
            fin(-L * 0.38, L * 0.08, L * 0.05, L * 0.10, L * 0.02, y=s * L * 0.09)
        # The rotodome on its pylon.
        cylinder(0.0, L * 0.12, -L * 0.14, -L * 0.06, L * 0.015, segs=8, axis="x", name="pylon")
        d = cylinder(-L * 0.10, 0.0, L * 0.12, L * 0.14, L * 0.20, segs=24, name="rotodome")


def build_helicopter(L):
    # Seahawk: rounded cabin, tail boom, four-blade main rotor, canted tail rotor, wheels.
    prof = [(L * 0.40, 0.0), (L * 0.36, L * 0.05), (L * 0.28, L * 0.075), (L * 0.10, L * 0.08),
            (-L * 0.08, L * 0.075), (-L * 0.14, L * 0.05), (-L * 0.16, L * 0.035), (-L * 0.42, L * 0.03),
            (-L * 0.44, L * 0.02), (-L * 0.45, 0.0)]
    cab = revolve(prof, segs=12, name="cabin")
    cab.scale = (1.0, 1.0, 0.85)
    cbox(L * 0.08, 0.0, L * 0.07, L * 0.30, L * 0.12, L * 0.05, name="engine_deck")
    plate([(-L * 0.36, -L * 0.14), (-L * 0.30, -L * 0.14), (-L * 0.30, L * 0.14), (-L * 0.36, L * 0.14)], 0.0, 0.1, name="stabilator")
    vplate([(-L * 0.42, 0.0), (-L * 0.36, 0.03), (-L * 0.38, L * 0.14), (-L * 0.44, L * 0.15)], -0.1, 0.1, name="fin")
    for k in range(4):
        a = k * math.pi / 2 + 0.3
        r = L * 0.14
        vplate([(-L * 0.42 + math.cos(a) * L * 0.01, L * 0.10 + math.sin(a) * L * 0.01),
                (-L * 0.42 + math.cos(a) * r, L * 0.10 + math.sin(a) * r),
                (-L * 0.42 + math.cos(a) * r - math.sin(a) * L * 0.015, L * 0.10 + math.sin(a) * r + math.cos(a) * L * 0.015),
                (-L * 0.42 + math.cos(a) * L * 0.01 - math.sin(a) * L * 0.015, L * 0.10 + math.sin(a) * L * 0.01 + math.cos(a) * L * 0.015)],
               L * 0.055, L * 0.065, name="tail_blade")
    cylinder(L * 0.06, 0.0, L * 0.09, L * 0.13, L * 0.012, segs=8, name="rotor_mast")
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        R = L * 0.41
        plate([(L * 0.06 + math.cos(a + 0.03) * L * 0.02, math.sin(a + 0.03) * L * 0.02),
               (L * 0.06 + math.cos(a) * R, math.sin(a) * R),
               (L * 0.06 + math.cos(a) * R - math.sin(a) * L * 0.012, math.sin(a) * R + math.cos(a) * L * 0.012),
               (L * 0.06 + math.cos(a - 0.03) * L * 0.02, math.sin(a - 0.03) * L * 0.02)], L * 0.125, L * 0.132, name="blade")
    cylinder(L * 0.06, 0.0, L * 0.12, L * 0.14, L * 0.035, segs=8, name="rotor_head")
    cbox(-L * 0.02, 0.0, -L * 0.07, L * 0.10, L * 0.09, L * 0.03, name="sonar")
    for s in (-1, 1):
        cylinder(s * L * 0.07, -L * 0.075, L * 0.20, L * 0.22, L * 0.02, segs=8, axis="x", name="wheel")
        cylinder(s * L * 0.11, L * 0.02, L * 0.02, L * 0.26, L * 0.012, segs=8, axis="x", name="stub_wing")


def build_air_station():
    """A shore air station: runway, taxiway, apron and hangars on a low plinth."""
    box(-900, 900, -80, 80, 0.0, 2.0, name="plinth")
    box(-800, 800, -25, 25, 2.0, 2.6, name="runway")
    box(-700, 700, 40, 55, 2.0, 2.6, name="taxiway")
    box(-200, 300, 55, 75, 2.0, 2.6, name="apron")
    for i in range(3):
        cbox(-120 + i * 110, 78, 2.0 + 7.0, 60, 40, 14, name="hangar")
    cbox(340, 70, 2.0 + 14.0, 14, 14, 28, name="tower")
    dome(-300, -60, 2.0, 12.0)



def build_lightning(L, carrier=True):
    # Single engine, trapezoid wing, two canted fins; the C has a visibly wider wing.
    fuselage(L, L * 0.065, nose=0.30, tail=0.28, taper=0.5)
    span = 13.1 if carrier else 10.7
    for side in (-1, 1):
        plate([(L*.10, side*.4), (-L*.28, side*.6), (-L*.22, side*span/2), (-L*.02, side*span/2)], -.15, .15, name="trapezoid_wing")
        plate([(-L*.30,side*.3),(-L*.48,side*.4),(-L*.44,side*L*.23),(-L*.31,side*L*.19)], -.12,.12,name="tailplane")
        fin(-L*.28,L*.19,L*.065,L*.14,L*.10,y=side*L*.07,cant=-side*.45)
        cbox(L*.04,side*L*.07,-.3,L*.22,L*.045,L*.065,name="intake")
    engine_pod(-L*.50,-L*.15,0,-.2,L*.048)
    cbox(L*.18,0,L*.064,L*.18,L*.07,L*.05,name="canopy")
    if not carrier:
        cylinder(0,0,L*.055,L*.075,L*.065,segs=24,axis="z",name="lift_fan_door")


def build_rafale(L):
    fuselage(L,L*.052,nose=.3,tail=.25,taper=.5)
    for side in (-1,1):
        plate([(L*.15,side*.3),(-L*.37,side*.4),(-L*.34,side*5.45)],-.12,.12,name="delta_wing")
        plate([(L*.25,side*.2),(L*.10,side*.2),(L*.12,side*2.2)],.35,.5,name="canard")
        engine_pod(-L*.5,-L*.08,side*.45,-.15,.45)
    fin(-L*.27,L*.24,L*.075,L*.21,L*.085,y=0)
    cbox(L*.20,0,L*.055,L*.19,L*.06,L*.055,name="canopy")


def build_triton(L):
    fuselage(L,L*.085,nose=.28,tail=.40,taper=.6)
    for side in (-1,1):
        plate([(L*.03,side*.5),(-L*.18,side*.5),(-L*.25,side*19.95),(-L*.14,side*19.95)],-.14,.14,name="long_span_wing")
        fin(-L*.30,L*.20,L*.08,L*.22,L*.07,y=side*.55,cant=-side*.75)
    engine_pod(-L*.43,-L*.04,0,L*.08,L*.05)
    dome(L*.20,0,L*.045,L*.10)


def build_queen_elizabeth(L):
    B=39.0; z=20.0
    hull(L,B,10.0,18.0,21.0,fullness=.65,transom=.8)
    plate([(-L*.49,-B*.78),(L*.48,-B*.72),(L*.50,-B*.4),(L*.50,B*.4),(L*.45,B*.72),(-L*.49,B*.78)],z,z+2,name="straight_flight_deck")
    # Two distinct islands and the raised bow ramp are the recognition features.
    for xx in (L*.12,-L*.16):
        prism(xx-13,xx+13,-B*.70,-B*.44,z+2,z+17,top_inset=1,name="island")
        mast(xx,-B*.56,z+17,z+29,r=.6,yard=6)
    vplate([(L*.31,z+2),(L*.49,z+2),(L*.49,z+8),(L*.43,z+6)],-B*.25,B*.26,name="ski_jump")
    for xx in (-L*.02,-L*.32):
        box(xx-11,xx+11,-B*.85,-B*.70,z,z+2,name="deck_lift")
    box(-L*.44,L*.30,-.35,.35,z+2,z+2.15,name="deck_centerline")


def build_merlin(L, coaxial=False):
    # A conventional long-tail Merlin or a compact coaxial Ka-27: no shared silhouette.
    body=L*.55
    fuselage(body,body*.13,nose=.22,tail=.25,taper=.5)
    cbox(-L*.30,0,.2,L*.45,.45,.5,name="tail_boom")
    cbox(-L*.04,0,body*.12,L*.25,L*.11,L*.07,name="engine_deck")
    rotor_z=body*.27
    cylinder(0,0,body*.1,rotor_z,.14,segs=8,axis="z",name="rotor_mast")
    span=15.9 if coaxial else 18.6
    for level in range(2 if coaxial else 1):
        blades=3 if coaxial else 5
        for i in range(blades):
            a=i*math.tau/blades+level*.5
            obj=plate([(0,-.16),(span*.48,-.25),(span*.50,.12),(0,.16)],rotor_z+level*.65,rotor_z+level*.65+.06,name="rotor")
            obj.rotation_euler.z=a
    if coaxial:
        for side in (-1,1):
            fin(-L*.39,L*.16,L*.10,L*.13,.1,y=side*1.7)
        plate([(-L*.35,-2.1),(-L*.47,-2.1),(-L*.47,2.1),(-L*.35,2.1)],.4,.55,name="tailplane")
    else:
        fin(-L*.38,L*.15,L*.10,L*.20,.1,y=0)
        for a in (0,math.pi/2):
            obj=cbox(-L*.43,.45,L*.11,.08,.08,2.8,name="tail_rotor")
            obj.rotation_euler.y=a


BUILDERS = {
    "usn_fighter_f35c": lambda s: build_lightning(s["length_m"], True),
    "rn_fighter_f35b": lambda s: build_lightning(s["length_m"], False),
    "fra_fighter_rafale_m": lambda s: build_rafale(s["length_m"]),
    "usn_uav_mq4c": lambda s: build_triton(s["length_m"]),
    "rn_cvf_queen_elizabeth": lambda s: build_queen_elizabeth(s["length_m"]),
    "rn_helo_merlin_hm2": lambda s: build_merlin(s["length_m"]),
    "rfn_helo_ka27": lambda s: build_merlin(s["length_m"], True),
    "fra_ffg_fremm": lambda s: build_constellation(s["length_m"]),
    "rn_ffg_type26": lambda s: build_european_frigate(s["length_m"], apar=False),
    "usn_cvn_ford": lambda s: build_carrier(s["length_m"]),
    "rn_ssn_astute": lambda s: build_submarine(s["length_m"], "virginia"),
    "civ_fishing_trawler": lambda s: build_merchant(s["length_m"]),
    "usn_ddg_arleigh_burke_iia": lambda s: build_aegis_destroyer(s["length_m"]),
    "usn_ddg_burke_iii": lambda s: build_aegis_destroyer(s["length_m"], flight_iii=True),
    "usn_cg_ticonderoga": lambda s: build_ticonderoga(s["length_m"]),
    "usn_ffg_constellation": lambda s: build_constellation(s["length_m"]),
    "rn_ddg_type45": lambda s: build_type45(s["length_m"]),
    "rnon_ffg_fridtjof_nansen": lambda s: build_european_frigate(s["length_m"]),
    "dnk_ffg_iver_huitfeldt": lambda s: build_european_frigate(s["length_m"]),
    "rfn_ffg_admiral_gorshkov": lambda s: build_gorshkov(s["length_m"]),
    "rfn_cg_slava": lambda s: build_slava(s["length_m"]),
    "rfn_ddg_udaloy": lambda s: build_udaloy(s["length_m"]),
    "rfn_fsg_steregushchiy": lambda s: build_steregushchiy(s["length_m"]),
    "rfn_fsg_buyan_m": lambda s: build_buyan(s["length_m"]),
    "deu_fsg_braunschweig": lambda s: build_braunschweig(s["length_m"]),
    "usn_cvn_nimitz": lambda s: build_carrier(s["length_m"]),
    "civ_merchant_bulk": lambda s: build_merchant(s["length_m"]),
    "rnon_aux_maud": lambda s: build_replenishment(s["length_m"]),
    "rfn_ssk_kilo_877": lambda s: build_submarine(s["length_m"], "kilo"),
    "rfn_ssk_kilo": lambda s: build_submarine(s["length_m"], "kilo"),
    "rfn_ssn_yasen_m": lambda s: build_submarine(s["length_m"], "yasen"),
    "usn_ssn_virginia": lambda s: build_submarine(s["length_m"], "virginia"),
    "usn_fighter_fa18e": lambda s: build_fighter(s["length_m"] or 18.3, "hornet"),
    "usn_ea_ea18g": lambda s: build_fighter(s["length_m"] or 18.3, "growler"),
    "rfn_fighter_su35s": lambda s: build_fighter(s["length_m"], "flanker"),
    "rfn_strike_su30sm": lambda s: build_fighter(s["length_m"], "flanker"),
    "rfn_strike_mig31k": lambda s: build_fighter(s["length_m"], "foxhound"),
    "rfn_bomber_tu22m3": lambda s: build_bomber(s["length_m"]),
    "rfn_mpa_tu142": lambda s: build_patrol(s["length_m"], "bear"),
    "usn_mpa_p8a": lambda s: build_patrol(s["length_m"], "poseidon"),
    "usn_aew_e2d": lambda s: build_patrol(s["length_m"] or 17.6, "hawkeye"),
    "usn_helo_mh60r": lambda s: build_helicopter(s["length_m"]),
    "shore_air_station": lambda s: build_air_station(),
}


def generic_builder(spec):
    """Anything a future data file adds without a dedicated builder gets a category shape."""
    c, dom, L = spec["category"], spec["domain"], spec["length_m"] or 120.0
    if dom == "air":
        if "helicopter" in c or "helo" in c:
            return build_helicopter(L)
        if "patrol" in c or "early" in c or "aew" in c:
            return build_patrol(L, "poseidon")
        if "bomber" in c:
            return build_bomber(L)
        return build_fighter(L, "hornet")
    if dom == "subsurface":
        return build_submarine(L, "virginia")
    if dom == "land":
        return build_air_station()
    if "carrier" in c:
        return build_carrier(L)
    if "merchant" in c:
        return build_merchant(L)
    if "auxiliar" in c or "replenish" in c:
        return build_replenishment(L)
    if "cruiser" in c:
        return build_ticonderoga(L)
    if "corvette" in c:
        return build_braunschweig(L)
    return build_european_frigate(L)


# --------------------------------------------------------------------------------------------
# Scene and rendering
# --------------------------------------------------------------------------------------------


def clear_scene():
    global _objects
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)
    _objects = []


def scene_bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in _objects:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def setup_render(scene):
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 2
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.compression = 90
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = LINE_PX
    vl = scene.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    fs.crease_angle = math.radians(120)
    fs.use_culling = True
    while len(fs.linesets) > 1:
        fs.linesets.remove(fs.linesets[-1])
    ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("outline")
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    ls.select_contour = False
    ls.select_edge_mark = False
    ls.visibility = "VISIBLE"
    st = ls.linestyle
    st.color = (1.0, 1.0, 1.0)
    st.alpha = 1.0
    st.thickness = LINE_PX
    st.thickness_position = "CENTER"
    # World: dim grey ambient so the shadow side stays legible after tinting.
    world = scene.world or bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.5, 0.5, 0.5, 1.0)
    bg.inputs[1].default_value = 0.28


_holdout = None


def sea_holdout(L):
    """An invisible sea: a holdout plane at the waterline hides the underwater hull and its
    bilge creases so the profile is cut at the waterline like a recognition drawing."""
    global _holdout
    if _holdout is None:
        m = bpy.data.materials.new("sea_holdout")
        m.use_nodes = True
        nt = m.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        hold = nt.nodes.new("ShaderNodeHoldout")
        nt.links.new(hold.outputs[0], out.inputs[0])
        _holdout = m
    o = box(-L * 4, L * 4, -L * 4, L * 4, -L, -0.02, name="sea")
    o.data.materials.clear()
    o.data.materials.append(_holdout)
    _objects.remove(o)
    return o


def add_sun(scene, direction, strength=3.4):
    light = bpy.data.lights.new("sun", "SUN")
    light.energy = strength
    light.angle = math.radians(6)
    o = bpy.data.objects.new("sun", light)
    scene.collection.objects.link(o)
    o.rotation_euler = Vector(direction).normalized().to_track_quat("-Z", "Y").to_euler()
    return o


def place_camera(scene, target, size_x, size_y, direction, distance):
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.clip_end = distance * 4
    o = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(o)
    d = Vector(direction).normalized()
    o.location = target + d * distance
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    scene.camera = o
    return o, cam


def box_corners(lo, hi):
    return [Vector((x, y, z)) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]


def scene_vertices():
    pts = []
    for o in _objects:
        mw = o.matrix_world
        for v in o.data.vertices:
            pts.append(mw @ v.co)
    return pts


def fit_camera(cam_obj, cam, corners, aspect, margin):
    """Aim the orthographic camera at the centre of the projected points and scale it so they
    all fit with `margin`. Returns (view_w, view_h) in metres."""
    rot = cam_obj.rotation_euler.to_matrix()
    right = rot @ Vector((1.0, 0.0, 0.0))
    up = rot @ Vector((0.0, 1.0, 0.0))
    fwd = rot @ Vector((0.0, 0.0, 1.0))
    xs = [c.dot(right) for c in corners]
    ys = [c.dot(up) for c in corners]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    view_w = max((max(xs) - min(xs)), (max(ys) - min(ys)) * aspect) * margin
    dist = (cam_obj.location - Vector((0, 0, 0))).dot(fwd)
    cam_obj.location = right * cx + up * cy + fwd * dist
    cam.ortho_scale = view_w
    return view_w, view_w / aspect


def render(scene, path, w, h):
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_platform(spec, scene):
    clear_scene()
    for o in list(scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    builder = BUILDERS.get(spec["id"])
    if builder:
        builder(spec)
    else:
        generic_builder(spec)
    bpy.context.view_layer.update()
    lo, hi = scene_bounds()
    is_air = spec["domain"] == "air"
    is_land = spec["domain"] == "land"
    L = hi.x - lo.x
    if spec["domain"] == "surface":
        sea_holdout(L)
    cx = (lo.x + hi.x) / 2
    margin = 1.10
    # --- Profile: an elevated side view from the port quarter, bow to the right.
    w, h = PROFILE_SIZE
    aspect = w / h
    add_sun(scene, (0.4, -1.0, 1.2) if (is_air or is_land) else (-0.5, -1.0, 1.4))
    scene.render.line_thickness = LINE_PX
    scene.view_layers[0].freestyle_settings.linesets[0].linestyle.thickness = LINE_PX
    if is_air or is_land:
        # Aircraft and the air station get a three-quarter view from ahead, port and above,
        # which shows planform and fins together and fills a wide frame.
        direction = (0.55, -1.0, 0.75) if is_air else (-0.35, -0.8, 0.75)
        target = Vector((cx, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2))
        cam_obj, cam = place_camera(scene, target, w, h, direction, 4000.0)
        fit_camera(cam_obj, cam, scene_vertices(), aspect, 1.06)
    else:
        direction = (0.0, -1.0, 0.22)
        extent = L * margin
        # Frame so the waterline lands at WATERLINE_FRACTION of the image height.
        view_h = extent / aspect
        target_z = view_h * (0.5 - WATERLINE_FRACTION)  # camera centre above the waterline
        target = Vector((cx, 0.0, -target_z))
        _, cam = place_camera(scene, target, w, h, direction, 4000.0)
        cam.ortho_scale = extent
        # A tall mast can poke out of the frame: widen until it fits.
        top = hi.z
        while top * 1.06 > view_h * WATERLINE_FRACTION:
            extent *= 1.08
            view_h = extent / aspect
            target_z = view_h * (0.5 - WATERLINE_FRACTION)
            scene.camera.location = Vector((cx, 0.0, -target_z)) + Vector(direction).normalized() * 4000.0
            cam.ortho_scale = extent
    render(scene, os.path.join(OUT_DIR, spec["id"] + "_profile.png"), w, h)
    # --- Plan: straight down, bow to the right, for the map silhouette.
    for o in list(scene.objects):
        if o.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(o, do_unlink=True)
    span = hi.y - lo.y
    if span <= L:
        w = PLAN_SIZE[0]
        h = max(8, int(round(w * span / L)))
    else:
        h = PLAN_SIZE[0]
        w = max(8, int(round(h * L / span)))
    w += w % 2
    h += h % 2
    add_sun(scene, (-0.6, -0.8, 1.2))
    scene.render.line_thickness = PLAN_LINE_PX
    scene.view_layers[0].freestyle_settings.linesets[0].linestyle.thickness = PLAN_LINE_PX
    target = Vector((cx, (lo.y + hi.y) / 2, 0.0))
    cam_obj, cam = place_camera(scene, target, w, h, (0.0, 0.0, 1.0), 4000.0)
    # An identity rotation is the plain top view: looking down -Z with +Y up, so the bow at +X
    # lands on the right of the image (the tracking quaternion mirrors it).
    cam_obj.rotation_euler = (0.0, 0.0, 0.0)
    cam.ortho_scale = max(L, span) * margin
    render(scene, os.path.join(OUT_DIR, spec["id"] + "_plan.png"), w, h)


def main():
    args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else sys.argv[1:]
    wanted = [a for a in args if not a.startswith("-")]
    specs = read_specs()
    os.makedirs(OUT_DIR, exist_ok=True)
    scene = bpy.context.scene
    setup_render(scene)
    ids = wanted or sorted(specs)
    for pid in ids:
        if pid not in specs:
            print("no such platform:", pid)
            continue
        print("==", pid)
        render_platform(specs[pid], scene)
    print("done:", len(ids), "platforms ->", OUT_DIR)


if __name__ == "__main__":
    main()
