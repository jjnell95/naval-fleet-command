"""Blender-free mesh kit for the fleet recognition models.

Everything here is built from primitives in metres using the convention of the earlier Blender
pipeline: X forward (bow or nose at +X), Y to port, Z up, with a ship's waterline at z = 0. The
export step turns that into the glTF frame the game expects (X forward, Y up, Z to starboard),
centres the model on its bounding box and scales its longest dimension to exactly ten units.

Parts carry a material name from PALETTE and a smoothing angle; faces sharing a vertex are
shaded smoothly when their normals differ by less than that angle, so hulls and fuselages are
round while deckhouses stay crisp. Each closed primitive is checked for outward winding, which
is what Blender's "recalculate normals" did for the old pipeline. One glTF mesh is written per
material, so the Godot importer produces a handful of surfaces per model.
"""
import math
from collections import defaultdict

import numpy as np
import trimesh

# name: (linear base colour, roughness, metallic). The first twenty are the Blender palette.
PALETTE = {
    "naval_paint": ((.39, .46, .50), .58, .0),
    "deck_non_skid": ((.075, .10, .12), .93, .0),
    "flight_deck": ((.075, .09, .105), .90, .0),
    "antifouling": ((.21, .045, .037), .8, .0),
    "boot_topping": ((.019, .028, .032), .7, .0),
    "array_face": ((.52, .57, .55), .72, .0),
    "radome": ((.74, .77, .70), .56, .0),
    "glazing": ((.014, .065, .092), .15, .64),
    "canopy_gold": ((.17, .20, .18), .13, .70),
    "rubber": ((.018, .024, .029), .84, .0),
    "titanium": ((.20, .24, .28), .30, .80),
    "bronze": ((.35, .20, .065), .35, .72),
    "marking_white": ((.79, .82, .79), .7, .0),
    "marking_yellow": ((.69, .43, .055), .70, .0),
    "hazard_red": ((.47, .06, .045), .62, .0),
    "airframe": ((.30, .36, .40), .58, .0),
    "airframe_light": ((.49, .56, .59), .62, .0),
    "airframe_blue": ((.23, .33, .39), .70, .0),
    "missile_body": ((.66, .70, .68), .50, .0),
    "seeker": ((.21, .24, .23), .27, .40),
    # Fixed sites: packed earth, concrete pads and drab vehicles read as land on the chart.
    "earth": ((.36, .33, .25), .95, .0),
    "earth_dark": ((.21, .19, .14), .95, .0),
    "concrete": ((.56, .56, .51), .85, .0),
    "drab": ((.19, .22, .15), .78, .0),
    "hull_black": ((.03, .035, .04), .70, .0),
    "hull_red": ((.36, .09, .06), .62, .0),
}

SMOOTH = 62.0  # degrees: round bodies shade smoothly, box corners stay hard


def _rotation(axis, angle):
    x, y, z = np.asarray(axis, float) / max(np.linalg.norm(axis), 1e-12)
    c, s = math.cos(angle), math.sin(angle)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


class Part:
    """A polygon mesh with one material (or one per face) and a smoothing angle."""

    def __init__(self, name, verts, faces, material, smooth=0.0):
        self.name = name
        self.verts = np.asarray(verts, dtype=float).reshape(-1, 3)
        self.faces = [tuple(int(i) for i in f) for f in faces]
        self.material = material
        self.smooth = smooth
        self.face_materials = None  # optional list parallel to faces

    def translate(self, v):
        self.verts = self.verts + np.asarray(v, float)
        return self

    def rotate(self, axis, angle, origin=(0, 0, 0)):
        o = np.asarray(origin, float)
        self.verts = (self.verts - o) @ _rotation(axis, angle).T + o
        return self

    def rotate_euler(self, rx=0.0, ry=0.0, rz=0.0, origin=(0, 0, 0)):
        """Blender XYZ Euler: about X first, then Y, then Z, all in the global frame."""
        if rx:
            self.rotate((1, 0, 0), rx, origin)
        if ry:
            self.rotate((0, 1, 0), ry, origin)
        if rz:
            self.rotate((0, 0, 1), rz, origin)
        return self

    def scale(self, s, origin=(0, 0, 0)):
        o = np.asarray(origin, float)
        self.verts = (self.verts - o) * np.asarray(s, float) + o
        return self

    def bounds(self):
        return self.verts.min(axis=0), self.verts.max(axis=0)

    def triangles(self):
        tris, owner = [], []
        for pi, f in enumerate(self.faces):
            for k in range(1, len(f) - 1):
                tris.append((f[0], f[k], f[k + 1]))
                owner.append(pi)
        return np.asarray(tris, dtype=np.int64).reshape(-1, 3), np.asarray(owner, dtype=np.int64)


class Model:
    """A collection of parts plus the primitive vocabulary of the old pipeline."""

    def __init__(self, default_material="naval_paint"):
        self.parts = []
        self.default = default_material
        self.waterline_z = 0.0

    # ---- bookkeeping -----------------------------------------------------------------------
    def add(self, name, verts, faces, m=None, smooth=0.0):
        p = Part(name, verts, faces, m or self.default, smooth)
        self.parts.append(p)
        return p

    def mark(self):
        return len(self.parts)

    def since(self, mark):
        return self.parts[mark:]

    def named(self, name):
        return [p for p in self.parts if p.name == name]

    def bounds(self):
        lo = np.array([np.inf] * 3)
        hi = np.array([-np.inf] * 3)
        for p in self.parts:
            if len(p.verts):
                lo = np.minimum(lo, p.verts.min(axis=0))
                hi = np.maximum(hi, p.verts.max(axis=0))
        return lo, hi

    def part_bounds(self, parts):
        lo = np.array([np.inf] * 3)
        hi = np.array([-np.inf] * 3)
        for p in parts:
            lo = np.minimum(lo, p.verts.min(axis=0))
            hi = np.maximum(hi, p.verts.max(axis=0))
        return lo, hi

    def paint(self, parts, m):
        for p in parts:
            p.material = m
            p.face_materials = None

    # ---- primitives --------------------------------------------------------------------------
    def box(self, x0, x1, y0, y1, z0, z1, name="box", m=None):
        verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                 (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        return self.add(name, verts, faces, m)

    def cbox(self, cx, cy, cz, sx, sy, sz, name="box", m=None):
        return self.box(cx - sx / 2, cx + sx / 2, cy - sy / 2, cy + sy / 2, cz - sz / 2, cz + sz / 2, name, m)

    def prism(self, x0, x1, y0, y1, z0, z1, top_inset=0.0, name="prism", m=None, inset_x=None):
        """A box whose top face is inset on every side: the sloped deckhouse of a modern hull."""
        i = top_inset
        ix = i if inset_x is None else inset_x
        verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                 (x0 + ix, y0 + i, z1), (x1 - ix, y0 + i, z1), (x1 - ix, y1 - i, z1), (x0 + ix, y1 - i, z1)]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        p = self.add(name, verts, faces, m)
        p.inset = top_inset  # lets the glazing pass follow a sloped bridge face
        return p

    def wedge(self, x0, x1, y0, y1, z0, z1, name="wedge", m=None, forward=True):
        """A triangular prism: a ramp rising from z0 at one end to z1 at the other."""
        if forward:
            verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x1, y0, z1), (x1, y1, z1)]
        else:
            verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x0, y1, z1)]
        faces = [(0, 3, 2, 1), (0, 1, 4), (2, 3, 5), (1, 2, 5, 4), (3, 0, 4, 5)]
        return self.add(name, verts, faces, m)

    def cylinder(self, cx, cy, z0, z1, r, segs=12, name="cyl", axis="z", r_top=None, m=None, smooth=SMOOTH):
        """Cylinder along an axis; for axis 'x' the (cx, cy) pair is (y, z) and z0..z1 runs
        along X; for axis 'y' it is (x, z)."""
        if axis not in ("x", "y", "z"):
            raise ValueError("cylinder axis must be x, y or z, got %r (pass the material as m=)" % (axis,))
        rt = r if r_top is None else r_top
        verts = []
        for h, rad in ((z0, r), (z1, rt)):
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
        return self.add(name, verts, faces, m, smooth)

    def revolve(self, profile, segs=16, name="rev", m=None, smooth=SMOOTH):
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
        return self.add(name, verts, faces, m, smooth)

    def plate(self, points_xy, z0, z1, name="plate", m=None):
        """Extrude a planar polygon (x, y) between two heights: wings, fins, decks."""
        n = len(points_xy)
        verts = [(x, y, z0) for (x, y) in points_xy] + [(x, y, z1) for (x, y) in points_xy]
        faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n
            faces.append((i, j, n + j, n + i))
        return self.add(name, verts, faces, m)

    def vplate(self, points_xz, y0, y1, name="fin", m=None):
        """Extrude a polygon in the (x, z) plane across Y: a vertical fin or a radar face."""
        n = len(points_xz)
        verts = [(x, y0, z) for (x, z) in points_xz] + [(x, y1, z) for (x, z) in points_xz]
        faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
        for i in range(n):
            j = (i + 1) % n
            faces.append((i, n + i, n + j, j))
        return self.add(name, verts, faces, m)

    def ellipsoid(self, cx, cy, cz, rx, ry, rz, segs=16, rings=8, name="ellipsoid", m=None):
        prof = []
        for i in range(rings + 1):
            a = math.pi * i / rings
            prof.append((-math.cos(a), max(math.sin(a), 0.0)))
        p = self.revolve([(x, r) for x, r in prof], segs, name, m)
        p.scale((rx, ry, rz))
        p.translate((cx, cy, cz))
        return p

    # ---- hull loft ---------------------------------------------------------------------------
    @staticmethod
    def ring_verts(x, b, d, fb, chine=1.0, flare=1.0):
        """One hull station: keel, bilge, waterline, topsides and a cambered deck, both sides."""
        star = [(0.0, -d), (0.55 * b, -0.92 * d), (0.92 * b * chine, -0.35 * d), (b, 0.0),
                (b * flare, fb * 0.55), (b * 0.96 * flare, fb), (0.0, fb + 0.12 * fb)]
        port = [(-y, z) for (y, z) in reversed(star[1:-1])]
        return [(x, y, z) for (y, z) in star + port]

    def hull(self, L, B, draft, fb_aft, fb_fwd, stations=26, transom=0.62, fullness=0.55, bow_sharp=True,
             flare=1.0, name="hull", m=None, x_offset=0.0, y_offset=0.0, bow_power=1.9, tumblehome=1.0):
        """Loft a displacement hull. `fullness` is where the parallel middle body ends (0..1 from
        the stern); a merchant is fuller than a frigate. The waterline is z = 0."""
        rings = []
        per = None
        for i in range(stations + 1):
            t = i / stations
            if t < 0.18:
                f = transom + (1.0 - transom) * math.sin(t / 0.18 * math.pi / 2)
            elif t < fullness:
                f = 1.0
            else:
                u = (t - fullness) / (1.0 - fullness)
                f = max(0.03 if bow_sharp else 0.25, 1.0 - u ** (bow_power if bow_sharp else 2.6))
            if i == stations:
                f = 0.03 if bow_sharp else 0.22
            b = B / 2 * f
            dr = draft
            if t > 0.78:
                dr = draft * (1.0 - 0.85 * ((t - 0.78) / 0.22) ** 1.6)
            if t < 0.12:
                dr = draft * (0.45 + 0.55 * t / 0.12)
            fb = fb_aft + (fb_fwd - fb_aft) * t ** 2.2
            x = -L / 2 + L * t + x_offset
            r = self.ring_verts(x, b, max(dr, 0.05), fb, flare=flare * tumblehome)
            per = len(r)
            rings.append([(vx, vy + y_offset, vz) for (vx, vy, vz) in r])
        verts = [v for r in rings for v in r]
        faces = []
        for i in range(len(rings) - 1):
            for k in range(per):
                n = (k + 1) % per
                faces.append((i * per + k, i * per + n, (i + 1) * per + n, (i + 1) * per + k))
        faces.append(tuple(range(per - 1, -1, -1)))
        last = (len(rings) - 1) * per
        faces.append(tuple(range(last, last + per)))
        return self.add(name, verts, faces, m, SMOOTH)

    @staticmethod
    def deck_z(fb_aft, fb_fwd, t):
        return fb_aft + (fb_fwd - fb_aft) * t ** 2.2

    # ---- fittings ------------------------------------------------------------------------------
    def mast(self, x, y, z0, z1, r=0.35, yard=0.0, m=None):
        self.cylinder(x, y, z0, z1, r, segs=8, name="mast", m=m)
        if yard > 0:
            self.cbox(x, y, z0 + (z1 - z0) * 0.72, r * 2, yard, r * 1.6, name="yard", m=m)

    def lattice_mast(self, x, y, z0, z1, base=3.0, top=1.0, m=None):
        """Four legs converging on a platform: the lattice mast of an older design."""
        for sy in (-1, 1):
            for sx in (-1, 1):
                a = np.array((x + sx * base / 2, y + sy * base / 2, z0))
                c = np.array((x + sx * top / 2, y + sy * top / 2, z1))
                self.rod(a, c, 0.16, name="leg", m=m, segs=4)
        for z in (z0 + (z1 - z0) * 0.5, z1):
            w = base + (top - base) * ((z - z0) / (z1 - z0))
            self.cbox(x, y, z, w * 1.1, w * 1.1, 0.25, name="platform", m=m)

    def gun(self, x, y, z, big=True, twin=False, m=None, stealth=False):
        s = 1.0 if big else 0.6
        if stealth:
            self.prism(x - 2.6 * s, x + 2.4 * s, y - 2.0 * s, y + 2.0 * s, z, z + 3.0 * s, 0.7 * s, name="turret", m=m)
        else:
            self.cbox(x, y, z + 1.6 * s, 6.0 * s, 4.0 * s, 3.0 * s, name="turret", m=m)
        for offset in (-.65, .65) if twin else (0,):
            self.cylinder(y + offset * s, z + 2.4 * s, x + 3.0 * s, x + 9.5 * s, 0.25 * s, segs=8, axis="x", name="barrel", m="titanium")

    def vls(self, x0, x1, y, z, w, rows=2, m=None):
        self.box(x0, x1, y - w / 2, y + w / 2, z, z + 0.45, name="vls", m=m)

    def radar_face(self, x, y, z, w, h, facing=1, m="array_face"):
        """A phased-array face: an octagonal plate on the side of a deckhouse."""
        pts = [(-w * 0.5 + w * 0.2, 0), (w * 0.5 - w * 0.2, 0), (w * 0.5, h * 0.2), (w * 0.5, h * 0.8),
               (w * 0.5 - w * 0.2, h), (-w * 0.5 + w * 0.2, h), (-w * 0.5, h * 0.8), (-w * 0.5, h * 0.2)]
        verts = []
        for (u, v) in pts:
            verts.append((x + u, y, z + v))
            verts.append((x + u, y + facing * 0.35, z + v))
        n = len(pts)
        faces = [tuple(range(0, 2 * n, 2))[::-1], tuple(range(1, 2 * n, 2))]
        for i in range(n):
            j = (i + 1) % n
            faces.append((2 * i, 2 * i + 1, 2 * j + 1, 2 * j))
        return self.add("array", verts, faces, m)

    def front_array(self, x, y, z, w, h, facing=1, m="array_face"):
        """An array face on a fore-or-aft facing bulkhead (facing +1 looks forward)."""
        pts = [(-w * 0.5 + w * 0.2, 0), (w * 0.5 - w * 0.2, 0), (w * 0.5, h * 0.2), (w * 0.5, h * 0.8),
               (w * 0.5 - w * 0.2, h), (-w * 0.5 + w * 0.2, h), (-w * 0.5, h * 0.8), (-w * 0.5, h * 0.2)]
        verts = []
        for (u, v) in pts:
            verts.append((x, y + u, z + v))
            verts.append((x + facing * 0.35, y + u, z + v))
        n = len(pts)
        faces = [tuple(range(0, 2 * n, 2)), tuple(range(1, 2 * n, 2))[::-1]]
        for i in range(n):
            j = (i + 1) % n
            faces.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))
        return self.add("array", verts, faces, m)

    def dome(self, x, y, z, r, segs=10, m="radome"):
        prof = [(0.0, 0.0)]
        for i in range(1, segs):
            a = math.pi * i / segs
            prof.append((r - r * math.cos(a), r * math.sin(a)))
        prof.append((2 * r, 0.0))
        o = self.revolve(prof, segs=12, name="dome", m=m)
        # The revolve runs along +X from the origin; stand it up on its base at (x, y, z).
        o.rotate((0, 1, 0), -math.pi / 2)
        o.translate((x, y, z))
        return o

    def sphere(self, x, y, z, r, segs=12, m="radome", name="dome"):
        return self.ellipsoid(x, y, z, r, r, r, segs, max(4, segs // 2), name, m)

    def hangar(self, x0, x1, B, z, h, name="hangar", m=None):
        return self.prism(x0, x1, -B * 0.42, B * 0.42, z, z + h, top_inset=0.6, name=name, m=m)

    def funnel(self, x, y, z, h, w=2.4, d=3.6, rake=0.0, m=None):
        verts = [(x - d / 2, y - w / 2, z), (x + d / 2, y - w / 2, z), (x + d / 2, y + w / 2, z), (x - d / 2, y + w / 2, z),
                 (x - d / 2 + rake, y - w / 2, z + h), (x + d / 2 + rake, y - w / 2, z + h),
                 (x + d / 2 + rake, y + w / 2, z + h), (x - d / 2 + rake, y + w / 2, z + h)]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        return self.add("funnel", verts, faces, m)

    def boat(self, x, y, z, m=None):
        return self.cbox(x, y, z + 0.6, 7.0, 2.4, 1.2, name="boat", m=m)

    def ciws(self, x, y, z, m=None):
        self.cylinder(x, y, z, z + 1.6, 1.0, segs=8, name="ciws", m=m)
        self.dome(x, y, z + 1.6, 1.1)

    def canisters(self, x, y, z, count, length=8.0, radius=.65, incline=.20, m=None, heading=0.0, stack=True):
        """A pack of inclined launch tubes, as the old cold-war models drew them."""
        mark = self.mark()
        for i in range(count):
            if count == 4 and stack:
                yy = ((i % 2) - .5) * radius * 2.25
                zz = (i // 2) * radius * 2.25
            else:
                yy = (i - (count - 1) / 2) * radius * 2.25
                zz = 0.0
            o = self.cylinder(yy, zz, -length / 2, length / 2, radius, 10, "tube", "x", m=m)
            o.rotate((0, 1, 0), -incline)
        for p in self.since(mark):
            if heading:
                p.rotate((0, 0, 1), heading)
            p.translate((x, y, z + radius))
        return self.since(mark)

    def rod(self, a, c, radius, name="railing", m=None, segs=6):
        a, c = np.asarray(a, float), np.asarray(c, float)
        length = np.linalg.norm(c - a)
        if length < 1e-6:
            return None
        o = self.cylinder(0, 0, 0, length, radius, segs=segs, name=name, m=m, smooth=0.0)
        axis = (c - a) / length
        z = np.array((0.0, 0.0, 1.0))
        dot = float(np.clip(np.dot(z, axis), -1, 1))
        if dot < 0.99999:
            if dot < -0.99999:
                o.rotate((1, 0, 0), math.pi)
            else:
                o.rotate(np.cross(z, axis), math.acos(dot))
        o.translate(a)
        return o

    def stripe(self, a, c, width=.2, m="marking_white", name="deck_marking"):
        a, c = np.asarray(a, float), np.asarray(c, float)
        d = c - a
        side = np.array((-d[1], d[0], 0.0))
        n = np.linalg.norm(side)
        if n < 1e-9:
            return None
        side = side / n * width / 2
        up = np.array((0, 0, .02))
        return self.add(name, [a - side, c - side, c + side, a + side, a - side + up, c - side + up, c + side + up, a + side + up],
                        [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], m)

    def circle(self, x, y, z, radius, width=.18, m="marking_white", segs=48):
        for i in range(segs):
            a, c = math.tau * i / segs, math.tau * (i + 1) / segs
            self.stripe((x + radius * math.cos(a), y + radius * math.sin(a), z),
                        (x + radius * math.cos(c), y + radius * math.sin(c), z), width, m)

    # ---- aircraft ------------------------------------------------------------------------------
    def fuselage(self, L, r, nose=0.22, tail=0.35, segs=14, taper=0.35, name="fuselage", m=None, nose_power=0.8):
        prof = []
        n = 8
        for i in range(n + 1):
            t = i / n
            prof.append((L / 2 - L * nose * t, r * math.sin(t * math.pi / 2) ** nose_power))
        prof.append((-L / 2 + L * tail, r))
        for i in range(1, n + 1):
            t = i / n
            prof.append((-L / 2 + L * tail * (1 - t), r * (1 - (1 - taper) * math.sin(t * math.pi / 2))))
        return self.revolve(prof, segs=segs, name=name, m=m)

    def wing(self, L, span, root, tip, sweep, x_root, z, dihedral=0.0, thickness=0.30, m=None, name="wing"):
        """A pair of trapezoidal wings. `x_root` is the leading-edge X at the root; sweep is the
        leading-edge X offset at the tip; both in metres."""
        for s in (-1, 1):
            pts = [(x_root, 0.0), (x_root - root, 0.0), (x_root - sweep - tip, s * span / 2), (x_root - sweep, s * span / 2)]
            o = self.plate(pts, z - thickness / 2, z + thickness / 2, name=name, m=m)
            if dihedral:
                o.rotate((1, 0, 0), s * dihedral)

    def fin(self, x_le, root, tip, height, sweep, y=0.0, cant=0.0, thickness=0.25, m=None, name="fin", z0=0.0):
        pts = [(x_le, z0), (x_le - root, z0), (x_le - sweep - tip, z0 + height), (x_le - sweep, z0 + height)]
        o = self.vplate(pts, -thickness / 2, thickness / 2, name=name, m=m)
        if cant:
            o.rotate((1, 0, 0), cant, (0, 0, z0))
        o.translate((0, y, 0))
        return o

    def engine_pod(self, x0, x1, y, z, r, m=None, segs=10):
        return self.cylinder(y, z, x0, x1, r, segs=segs, axis="x", name="engine", m=m)

    def canopy(self, x, y, z, length, width, height, m="canopy_gold"):
        """A low curved canopy: a half-ellipsoid dropped onto the spine."""
        prof = []
        for i in range(13):
            t = i / 12
            prof.append((-length / 2 + length * t, max(.015, math.sin(math.pi * t) ** .65)))
        o = self.revolve(prof, segs=14, name="canopy", m=m)
        o.scale((1.0, width * .5, height))
        o.translate((x, y, z))
        return o

    def rotor(self, x, y, z, radius, blades=4, chord=.45, phase=0.3, m="rubber"):
        self.cylinder(x, y, z - radius * .05, z + .05, radius * .05, 8, "rotor_head", m="titanium")
        for i in range(blades):
            a = i * math.tau / blades + phase
            o = self.plate([(0, -chord * .4), (radius * .98, -chord * .5), (radius, chord * .3), (0, chord * .4)], z, z + .07, name="rotor", m=m)
            o.rotate((0, 0, 1), a)
            o.translate((x, y, 0))

    def tail_rotor(self, x, y, z, radius, blades=4, m="rubber", thickness=.06):
        for i in range(blades):
            a = i * math.tau / blades + .35
            o = self.vplate([(0, 0), (radius * .12, -.1), (radius, -.13), (radius, .13), (radius * .12, .1)], -thickness / 2, thickness / 2, name="tail_rotor", m=m)
            o.rotate((0, 1, 0), a)
            o.translate((x, y, z))

    def propeller(self, x, y, z, radius, blades=4, m="rubber"):
        self.cylinder(y, z, x - .1, x + .25, radius * .14, 10, "spinner", "x", m="titanium")
        for i in range(blades):
            a = i * math.tau / blades
            o = self.vplate([(x + .05, 0), (x + .15, radius * .1), (x + .1, radius), (x - .1, radius), (x - .07, radius * .1)], -radius * .03, radius * .03, name="prop", m=m)
            o.rotate((1, 0, 0), a, (x, 0, 0))
            o.translate((0, y, z))

    # ---- export --------------------------------------------------------------------------------
    def triangle_count(self):
        return sum(len(p.triangles()[0]) for p in self.parts)

    def export(self, path, normalise=True):
        """Write a GLB in the game frame and return the manifest row plus render metadata."""
        buckets = defaultdict(lambda: ([], []))
        for part in self.parts:
            for material, pos, nrm in _finished_triangles(part):
                buckets[material][0].append(pos)
                buckets[material][1].append(nrm)
        all_pos = np.concatenate([np.concatenate(b[0]) for b in buckets.values()])
        lo, hi = all_pos.min(axis=0), all_pos.max(axis=0)
        center = (lo + hi) * .5
        scale = 10.0 / max(hi - lo) if normalise else 1.0
        geometry = {}
        triangles = 0
        for material, (pos_list, nrm_list) in buckets.items():
            pos = (np.concatenate(pos_list) - center) * scale
            nrm = np.concatenate(nrm_list)
            # Blender frame to glTF: X forward, Z up -> Y up, port -> -Z.
            pos = np.stack([pos[:, 0], pos[:, 2], -pos[:, 1]], axis=1)
            nrm = np.stack([nrm[:, 0], nrm[:, 2], -nrm[:, 1]], axis=1)
            key = np.concatenate([np.round(pos, 5), np.round(nrm, 3)], axis=1)
            uniq, inverse = np.unique(key, axis=0, return_inverse=True)
            faces = np.asarray(inverse).reshape(-1, 3)
            keep = ~((faces[:, 0] == faces[:, 1]) | (faces[:, 1] == faces[:, 2]) | (faces[:, 0] == faces[:, 2]))
            faces = faces[keep]
            if len(faces) == 0:
                continue
            colour, roughness, metallic = PALETTE[material]
            mesh = trimesh.Trimesh(vertices=uniq[:, :3], faces=faces, process=False)
            normals = uniq[:, 3:]
            normals = normals / np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
            mesh.vertex_normals = normals
            mesh.visual = trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
                name=material, baseColorFactor=[*colour, 1.0], metallicFactor=metallic, roughnessFactor=roughness,
                doubleSided=False))
            mesh.metadata = {}
            geometry[material] = mesh
            triangles += len(faces)
        scene = trimesh.Scene(geometry=geometry)
        with open(path, "wb") as f:
            f.write(scene.export(file_type="glb", include_normals=True))
        # The game frame's Y of the build-space waterline (z = self.waterline_z).
        return {
            "triangles": int(triangles),
            "scale": float(scale),
            "waterline_y": float((self.waterline_z - center[2]) * scale),
            "extent_m": [float(v) for v in (hi - lo)],
            "surfaces": len(geometry),
        }


def _finished_triangles(part):
    """Triangulate a part, make its winding outward and compute per-corner normals with the
    part's smoothing angle. Yields (material, positions[3T,3], normals[3T,3]) per material."""
    tris, owner = part.triangles()
    if len(tris) == 0:
        return
    verts = part.verts
    mesh = trimesh.Trimesh(vertices=verts, faces=tris, process=False)
    if len(tris) >= 4:
        try:
            mesh.fix_normals(multibody=False)
        except Exception:
            pass
    tris = np.asarray(mesh.faces)
    fn = np.asarray(mesh.face_normals)
    area = np.asarray(mesh.area_faces)
    if part.smooth > 0:
        keyed = np.round(verts, 4)
        _, inverse = np.unique(keyed, axis=0, return_inverse=True)
        inverse = np.asarray(inverse).reshape(-1)
        vert_faces = defaultdict(list)
        for fi, tri in enumerate(tris):
            for v in tri:
                vert_faces[inverse[v]].append(fi)
        cos_t = math.cos(math.radians(part.smooth))
        corner = np.empty((len(tris), 3, 3))
        for fi, tri in enumerate(tris):
            f = fn[fi]
            for k, v in enumerate(tri):
                acc = np.zeros(3)
                for fj in vert_faces[inverse[v]]:
                    if np.dot(fn[fj], f) >= cos_t:
                        acc += fn[fj] * area[fj]
                n = np.linalg.norm(acc)
                corner[fi, k] = acc / n if n > 1e-12 else f
        normals = corner.reshape(-1, 3)
    else:
        normals = np.repeat(fn, 3, axis=0)
    positions = verts[tris.reshape(-1)]
    if part.face_materials is None:
        yield part.material, positions, normals
        return
    mats = np.asarray([part.face_materials[o] for o in owner])
    for material in sorted(set(mats)):
        sel = np.repeat(mats == material, 3)
        yield material, positions[sel], normals[sel]


def split_hull_materials(part, draft, deck_material="deck_non_skid", paint="naval_paint"):
    """The old presentation pipeline's hull finish: antifouling below the boot topping band,
    non-skid on the deck faces, paint on the topsides."""
    tris, owner = part.triangles()
    band_lo = -min(0.7, max(0.25, draft * 0.14))
    band_hi = min(0.65, max(0.2, draft * 0.12))
    mats = [paint] * len(part.faces)
    for pi, f in enumerate(part.faces):
        pts = part.verts[list(f)]
        c = pts.mean(axis=0)
        n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        nn = np.linalg.norm(n)
        nz = n[2] / nn if nn > 1e-12 else 0.0
        if c[2] < band_lo:
            mats[pi] = "antifouling"
        elif c[2] < band_hi:
            mats[pi] = "boot_topping"
        elif abs(nz) > 0.6:
            mats[pi] = deck_material
    part.face_materials = mats
    return part
