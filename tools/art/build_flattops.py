"""Flat-top builders for build_models.py: the U.S. carriers, Queen Elizabeth, Charles de Gaulle,
America and Mistral.

The first flat-tops came from the Blender pipeline as a slab of hull under a slab of deck, with a
box for an island. These replace them with what a flight deck actually reads as from a camera
over the sea: a flared hull that meets an overhanging deck, the angled landing area and its
sponsons, deck-edge lifts over dark hangar openings, catwalks round the deck edge, an island in
tiers with its bridge, flying control, mast and radars, weapons on the sponsons, the deck's
markings, and aircraft parked where the class parks them.

The same convention as artkit: metres, bow at +X, port at +Y, up +Z, waterline at z = 0. A deck
outline is given stern to bow down the starboard edge and back up the port edge as (t, y) pairs,
t running 0 at the stern to 1 at the bow. Class shapes are public recognition features at game
scale, not dimensions from drawings.
"""
import math

import numpy as np

from artkit import Model
import build_air_weapons as aw


# --------------------------------------------------------------------------------------------
# Geometry helpers
# --------------------------------------------------------------------------------------------


def _area(points):
    a = 0.0
    for i in range(len(points)):
        x0, y0 = points[i]
        x1, y1 = points[(i + 1) % len(points)]
        a += x0 * y1 - x1 * y0
    return a * .5


def _inside(p, a, b, c):
    def cross(o, u, v):
        return (u[0] - o[0]) * (v[1] - o[1]) - (u[1] - o[1]) * (v[0] - o[0])
    d1, d2, d3 = cross(a, b, p), cross(b, c, p), cross(c, a, p)
    return not ((d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9) and (d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9))


def ear_clip(points):
    """Triangles (index triples, counter-clockwise) covering a simple polygon, concave or not."""
    idx = list(range(len(points)))
    if _area(points) < 0:
        idx.reverse()
    tris = []
    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = points[i0], points[i1], points[i2]
            if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 1e-9:
                continue  # reflex or degenerate corner
            if any(_inside(points[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            del idx[k]
            break
        else:
            break
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


def slab(m, points, z0, z1, name, mat):
    """Extrude a simple polygon of (x, y) between two heights, triangulating concave outlines
    properly (Model.plate fans from the first corner, which only suits a convex one)."""
    n = len(points)
    tris = ear_clip(points)
    verts = [(x, y, z0) for x, y in points] + [(x, y, z1) for x, y in points]
    faces = [(c, b, a) for a, b, c in tris] + [(a + n, b + n, c + n) for a, b, c in tris]
    ccw = _area(points) > 0
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i) if ccw else (j, i, n + i, n + j))
    return m.add(name, verts, faces, mat)


def outline(L, starboard, port):
    """Deck outline in metres from (t, y) pairs: starboard stern to bow, then port bow to stern."""
    return [(L * (t - .5), y) for t, y in starboard] + [(L * (t - .5), y) for t, y in port]


def offset_edges(points, d):
    """Each edge of a polygon pushed outward by `d`: [(a, b), ...] for catwalks and safety lines."""
    ccw = _area(points) > 0
    out = []
    for i in range(len(points)):
        a = np.array(points[i], float)
        b = np.array(points[(i + 1) % len(points)], float)
        e = b - a
        n = np.array((e[1], -e[0])) if ccw else np.array((-e[1], e[0]))
        ln = np.linalg.norm(n)
        if ln < 1e-6:
            continue
        n = n / ln * d
        out.append((a + n, b + n))
    return out


# --------------------------------------------------------------------------------------------
# Parked aircraft: deck-park shapes, wings spread, nothing hanging under them
# --------------------------------------------------------------------------------------------


def parked_hornet(m, L=18.3):
    """Super Hornet: long leading-edge root extensions, trapezoid wing, canted twin fins."""
    start = m.mark()
    m.fuselage(L, L * .048, nose=.30, tail=.22, taper=.55, segs=14)
    span = 13.6
    for s in (-1, 1):
        m.plate([(L * .06, s * .9), (-L * .22, s * 1.0), (-L * .26, s * span / 2), (-L * .15, s * span / 2)], -.09, .09, "wing")
        m.plate([(L * .30, s * .35), (L * .06, s * .95), (-L * .02, s * 1.2), (L * .02, s * .5)], -.08, .08, "lerx")
        m.plate([(-L * .31, s * .8), (-L * .47, s * .8), (-L * .47, s * 3.3), (-L * .41, s * 3.3)], -.06, .06, "stab")
        m.fin(-L * .20, L * .20, L * .08, L * .16, L * .12, y=s * 1.2, cant=-s * .34, thickness=.12)
        m.engine_pod(-L * .48, -L * .12, s * .62, -.35, L * .034)
        m.prism(-L * .12, L * .06, s * 1.05 - .35, s * 1.05 + .35, -.75, .1, .05, "intake")
    m.canopy(L * .22, 0, L * .04, L * .16, L * .055, L * .05)
    aw.aircraft_finish(m, L, start=start)


def parked_tomcat(m, L=19.1):
    """Tomcat parked with its wings swept right back over the tailplanes."""
    start = m.mark()
    m.fuselage(L, L * .045, nose=.30, tail=.20, taper=.6, segs=14)
    for s in (-1, 1):
        m.plate([(L * .20, s * .6), (-L * .10, s * 2.4), (-L * .22, s * 2.6), (L * .02, s * .9)], -.12, .12, "glove")
        m.plate([(-L * .06, s * 2.2), (-L * .44, s * 3.4), (-L * .47, s * 4.9), (-L * .14, s * 2.6)], .05, .2, "wing")
        m.plate([(-L * .34, s * 1.2), (-L * .50, s * 1.3), (-L * .50, s * 4.0), (-L * .42, s * 4.0)], -.1, .03, "stab")
        m.fin(-L * .26, L * .18, L * .07, L * .20, L * .11, y=s * 1.5, cant=-s * .08, thickness=.14)
        m.engine_pod(-L * .47, -L * .02, s * 1.45, -.3, L * .042)
    m.canopy(L * .24, 0, L * .045, L * .17, L * .05, L * .05)
    aw.aircraft_finish(m, L, start=start)


def parked_hawkeye(m, L=17.6):
    """Hawkeye: high straight wing, turboprops, rotodome on a pylon, four fins."""
    start = m.mark()
    m.fuselage(L, 1.2, nose=.18, tail=.32, taper=.45, segs=14)
    span = 24.6
    for s in (-1, 1):
        m.plate([(L * .08, s * 1.0), (-L * .06, s * 1.0), (-L * .04, s * span / 2), (L * .03, s * span / 2)], .75, .95, "wing")
        m.engine_pod(-L * .02, L * .20, s * 3.8, .55, .6)
        m.propeller(L * .21, s * 3.8, .55, 2.0)
        for yy in (1.2, 3.3):
            m.fin(-L * .36, 1.6, 1.1, 2.9, .6, y=s * yy, thickness=.1, z0=1.2)
    m.plate([(-L * .34, -3.9), (-L * .46, -3.9), (-L * .46, 3.9), (-L * .34, 3.9)], 1.15, 1.3, "stab")
    m.cbox(-L * .05, 0, 2.2, 1.6, .5, 1.8, "pylon")
    m.cylinder(-L * .05, 0, 3.1, 3.8, 3.66, 20, "rotodome", m="radome")
    aw.aircraft_finish(m, L, start=start)


def parked_rafale(m, L=15.3):
    """Rafale M: cropped delta, close-coupled canards, one fin."""
    start = m.mark()
    m.fuselage(L, L * .05, nose=.32, tail=.18, taper=.6, segs=14)
    for s in (-1, 1):
        m.plate([(L * .08, s * .7), (-L * .40, s * .8), (-L * .40, s * 5.4), (-L * .28, s * 5.4)], -.1, .1, "wing")
        m.plate([(L * .22, s * .6), (L * .12, s * .6), (L * .10, s * 2.2), (L * .14, s * 2.2)], .1, .2, "canard")
        m.prism(-L * .08, L * .12, s * .95 - .3, s * .95 + .3, -.7, .0, .05, "intake")
    m.fin(-L * .16, L * .26, L * .08, L * .20, L * .16, thickness=.12)
    m.engine_pod(-L * .46, -L * .10, 0, -.2, L * .045)
    m.canopy(L * .24, 0, L * .05, L * .16, L * .06, L * .05)
    aw.aircraft_finish(m, L, start=start)


def parked_helo(m, L=19.8, blades=4, radius=8.2, three_engine=False):
    """A naval helicopter on deck: cabin, tail boom, rotor spread."""
    m.fuselage(L * .62, 1.25, nose=.25, tail=.25, taper=.6, segs=12).translate((L * .12, 0, 1.4))
    m.cylinder(0, 1.7, -L * .45, -L * .05, .45, 8, "tail_boom", "x", r_top=.28)
    m.fin(-L * .38, 1.8, 1.0, 2.6, .9, thickness=.12, z0=1.9)
    m.cbox(L * .10, 0, 2.9, 3.8 if three_engine else 3.0, 1.6, .8, "engine_fairing")
    m.rotor(L * .10, 0, 3.4, radius, blades, .55)
    m.tail_rotor(-L * .42, .35, 3.4, 1.5)
    for s in (-1, 1):
        m.cylinder(L * .15, s * 1.3, 0, .4, .35, 8, "wheel", m="rubber")


def park(m, builder, length, spots, z, material="airframe"):
    """Aircraft on deck: (x, y, heading) spots, all one airframe finish so the deck park reads."""
    for xx, yy, heading in spots:
        mark = m.mark()
        builder(m, length)
        for p in m.since(mark):
            p.rotate((0, 0, 1), heading)
            p.translate((xx, yy, z))
            if p.name == "canopy":
                p.material = "glazing"
            elif p.material not in ("rubber", "titanium", "radome", "array_face"):
                p.material = material
            p.face_materials = None


# --------------------------------------------------------------------------------------------
# The flat-top: hull, deck, lifts, catwalks, sponsons
# --------------------------------------------------------------------------------------------


class FlatTop:
    """A flight-deck ship built up from the hull: the hull reaches the flight deck, which
    overhangs it on a thick gallery edge, with catwalks just below the deck edge."""

    def __init__(self, m, spec, L_wl, B, draft, deck_z, starboard, port, flare=1.18, fullness=.60,
                 transom=.86, bow_power=1.7, bulb=True, deck_thickness=1.6, gallery=4.2):
        self.m = m
        self.L = spec["length_m"]
        self.B = B
        self.draft = draft
        self.z = deck_z
        self.top = deck_z + .12
        # The loft's deck is cambered 12 % above its side; keep the crown under the flight deck.
        fb = (deck_z - deck_thickness - .3) / 1.12
        m.hull(L_wl, B, draft, fb, fb, stations=44, fullness=fullness, transom=transom, bow_power=bow_power,
               flare=flare, name="hull")
        self.hull = m.named("hull")[-1]
        if bulb:
            r = B * .085
            m.ellipsoid(L_wl * .5 - r * 2.7, 0, -draft * .6, r * 3.2, r, r * .9, 12, 6, "bulb", "antifouling")
        self.deck = outline(self.L, starboard, port)
        slab(m, self.deck, deck_z - deck_thickness, self.top, "flight_deck", "flight_deck")
        inner = [(x * .995, y * .985) for x, y in self.deck]
        slab(m, inner, deck_z - deck_thickness - gallery, deck_z - deck_thickness, "gallery", "naval_paint")
        # Catwalks run along the sides, not round the bow or the round-down.
        for a, b in offset_edges(self.deck, 1.1):
            e = b - a
            if np.linalg.norm(e) < 6.0 or abs(e[0]) < 2.5 * abs(e[1]):
                continue
            m.stripe((a[0], a[1], deck_z - 2.2), (b[0], b[1], deck_z - 2.2), 2.0, "deck_non_skid", "catwalk")
        for a, b in offset_edges(self.deck, -.7):
            if np.linalg.norm(b - a) < 6.0:
                continue
            m.stripe((a[0], a[1], self.top + .02), (b[0], b[1], self.top + .02), .35, "marking_white", "deck_edge_line")

    def x(self, t):
        return self.L * (t - .5)

    def half_breadth_at(self, t):
        """The hull's half-breadth near the gallery at a station, for openings on its side."""
        v = self.hull.verts
        xs = self.x(t)
        near = v[np.abs(v[:, 0] - xs) < self.L * .03]
        if len(near) == 0:
            return self.B * .5
        return float(np.abs(near[near[:, 2] > self.z * .5][:, 1]).max()) if (near[:, 2] > self.z * .5).any() else self.B * .5

    def lift(self, t0, t1, side, depth=15.0, edge=None):
        """A deck-edge lift on `side` (+1 port, -1 starboard): a platform let into the deck edge,
        outlined by its dark gap, over the hangar opening in the hull side below it."""
        m = self.m
        x0, x1 = self.x(t0), self.x(t1)
        y_edge = edge if edge is not None else side * self._edge_y((t0 + t1) * .5, side)
        y_in = y_edge - side * depth
        lo, hi = sorted((y_edge, y_in))
        m.box(x0, x1, lo, hi, self.top + .01, self.top + .05, "lift", "deck_non_skid")
        for a, b in (((x0, lo), (x1, lo)), ((x0, hi), (x1, hi)), ((x0, lo), (x0, hi)), ((x1, lo), (x1, hi))):
            m.stripe((a[0], a[1], self.top + .06), (b[0], b[1], self.top + .06), .3, "rubber", "lift_gap")
        hb = self.half_breadth_at((t0 + t1) * .5)
        m.box(x0 + 1.0, x1 - 1.0, side * hb - .25, side * hb + .25, self.z - 12.5, self.z - 3.2, "hangar_opening", "rubber")

    def _edge_y(self, t, side):
        """How far out the deck edge is on one side at a station."""
        xs = self.x(t)
        best = 0.0
        pts = self.deck
        for i in range(len(pts)):
            (xa, ya), (xb, yb) = pts[i], pts[(i + 1) % len(pts)]
            if (xa - xs) * (xb - xs) <= 0 and xa != xb:
                y = ya + (yb - ya) * (xs - xa) / (xb - xa)
                if y * side > best:
                    best = y * side
        return best

    def sponson(self, t, side, kind="ciws", out=2.5):
        """A weapons sponson hung off the deck edge: Phalanx or RAM on a cylinder, or a box
        launcher (Sea Sparrow, ESSM)."""
        m = self.m
        xx = self.x(t)
        yy = side * (self._edge_y(t, side) + out)
        z = self.z - 3.6
        m.cbox(xx, yy - side * out * .5, z - .8, 8.0, out * 2.2, 2.0, "sponson")
        lo, hi = sorted((yy - side * out * 1.6, yy + side * .4))
        m.prism(xx - 3.8, xx + 3.8, lo, hi, z - 1.8, z - 5.5, 1.3, "sponson_brace")  # tapers downward
        if kind == "box":
            m.cbox(xx, yy, z + 1.3, 4.2, 3.2, 1.6, "launcher", "naval_paint")
            m.box(xx + 2.1, xx + 2.16, yy - 1.4, yy + 1.4, z + .6, z + 2.0, "launcher_face", "rubber")
        elif kind == "ram":
            m.cylinder(xx, yy, z, z + 1.0, 1.1, 8, "ram_base")
            m.cbox(xx, yy, z + 2.1, 3.2, 1.8, 1.8, "ram_launcher")
            m.box(xx + 1.6, xx + 1.65, yy - .8, yy + .8, z + 1.3, z + 2.9, "ram_face", "rubber")
        else:
            m.ciws(xx, yy, z)

    def spot_circles(self, ts, y, r=7.0):
        for t in ts:
            self.m.circle(self.x(t), y, self.top + .03, r, .3)

    def angled_deck(self, t0, y0, angle_deg, t1, width=24.0, dashes=18):
        """The landing area: its two edge lines and a dashed centreline, `angle_deg` to port."""
        m = self.m
        a = math.radians(angle_deg)
        x0, x1 = self.x(t0), self.x(t1)
        y1 = y0 + (x1 - x0) * math.tan(a)
        z = self.top + .03
        for s in (-1, 1):
            m.stripe((x0, y0 + s * width / 2, z), (x1, y1 + s * width / 2, z), .4)
        for i in range(dashes):
            f0 = i / dashes
            f1 = f0 + .45 / dashes
            m.stripe((x0 + (x1 - x0) * f0, y0 + (y1 - y0) * f0, z + .01), (x0 + (x1 - x0) * f1, y0 + (y1 - y0) * f1, z + .01), .45,
                     "marking_white" if i % 2 else "marking_yellow")
        # The foul line where the landing area meets the bow: a red stripe across the deck.
        return y1

    def catapult(self, t0, t1, y0, y1):
        m = self.m
        z = self.top + .03
        a = (self.x(t0), y0, z)
        b = (self.x(t1), y1, z)
        m.stripe(a, b, .5, "rubber", "catapult_track")
        for s in (-1, 1):
            m.stripe((a[0], a[1] + s * .8, z), (b[0], b[1] + s * .8, z), .12)

    def finish(self):
        from artkit import split_hull_materials
        split_hull_materials(self.hull, self.draft, deck_material="flight_deck")


def island_block(m, x0, x1, y0, y1, z0, h, inset=.4, name="island"):
    return m.prism(x0, x1, y0, y1, z0, z0 + h, inset, name)


def glaze(m, x0, x1, y0, y1, z0, z1, forward=True):
    """A band of bridge windows round a block's sides and front."""
    for yy in (y0 - .03, y1 + .03):
        count = max(3, int((x1 - x0) / 1.7))
        for i in range(count):
            xx = x0 + .6 + i * (x1 - x0 - 1.2) / count
            m.box(xx, xx + .95, yy - .02, yy + .02, z0, z1, "bridge_window", "glazing")
    if forward:
        count = max(2, int((y1 - y0) / 1.6))
        for i in range(count):
            yy = y0 + .5 + i * (y1 - y0 - 1.0) / count
            m.box(x1 + .01, x1 + .05, yy, yy + .9, z0, z1, "bridge_window", "glazing")


def tower(m, x, y, z0, z1, base, top):
    """An enclosed mast: a faceted tower from a square base to a smaller top."""
    b, t = base / 2, top / 2
    verts = [(x - b, y - b, z0), (x + b, y - b, z0), (x + b, y + b, z0), (x - b, y + b, z0),
             (x - t, y - t, z1), (x + t, y - t, z1), (x + t, y + t, z1), (x - t, y + t, z1)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return m.add("integrated_mast", verts, faces)


def lattice_tripod(m, x, y, z0, z1, spread=3.2):
    """The tripod mast of the older U.S. islands: three legs to a platform."""
    top = np.array((x, y, z1))
    for dx, dy in ((spread, 0.0), (-spread * .6, spread * .8), (-spread * .6, -spread * .8)):
        m.rod((x + dx, y + dy, z0), top, .3, "mast_leg", "naval_paint", 6)
    m.cbox(x, y, z1, 3.6, 3.6, .5, "platform")


# --------------------------------------------------------------------------------------------
# U.S. carriers
# --------------------------------------------------------------------------------------------

NIMITZ_STARBOARD = [(0.0, -21), (.03, -25), (.24, -25), (.30, -31), (.53, -31), (.60, -27), (.86, -25), (.94, -19), (1.0, -13)]
NIMITZ_PORT = [(1.0, 13), (.94, 17), (.74, 22), (.66, 24), (.61, 41), (.52, 45), (.32, 42), (.14, 34), (.04, 27), (0.0, 22)]


def _us_carrier(m, spec, island_t, island_len, ford=False, era=2027):
    L = spec["length_m"]
    c = FlatTop(m, spec, L * .95, 40.8, 11.3, 19.5, NIMITZ_STARBOARD, NIMITZ_PORT, flare=1.15)
    x, z = c.x, c.top
    # The landing area, angled nine degrees to port, the bow catapults and the waist pair.
    c.angled_deck(.03, 0.0, 9.0, .56, 24.0)
    c.catapult(.70, .985, 7.0, 7.0)
    c.catapult(.70, .985, -9.0, -9.0)
    for y0 in (19.0, 31.0):
        c.catapult(.36, .56, y0 - 2.0, y0 + (L * .2) * math.tan(math.radians(9.0)) - 2.0)
    # Deck-edge lifts: two to starboard forward of the island and one aft of it, one to port aft.
    # The Ford gave up the second forward one; her island stands further aft and further out.
    lifts = [(.66, .72, -1), (.25, .31, -1), (.20, .26, 1)] if ford else [(.66, .72, -1), (.56, .62, -1), (.25, .31, -1), (.20, .26, 1)]
    for t0, t1, side in lifts:
        c.lift(t0, t1, side)
    i0 = x(island_t)
    i1 = i0 + island_len
    y_out, y_in = -31.0, -21.0 if not ford else -23.5
    if ford:
        y_out = -32.5
        # A smaller island set further aft, three flat radar faces and one enclosed mast.
        island_block(m, i0, i1, y_out, y_in, z, 13.0, .3)
        m.box(i0 + 2.0, i1 - 1.0, y_out + .6, y_in - .6, z + 13.0, z + 17.0, "bridge")
        for face, (xx, yy) in enumerate(((i1 - 2.5, (y_out + y_in) * .5), ((i0 + i1) * .5, y_in - .3), ((i0 + i1) * .5, y_out + .3))):
            if face == 0:
                m.front_array(i1 + .1, yy, z + 8.0, 5.0, 4.5, 1)
            else:
                m.radar_face(xx, yy, z + 8.0, 5.0, 4.5, 1 if yy > (y_out + y_in) * .5 else -1)
        glaze(m, i0 + 2.0, i1 - 1.0, y_out + .6, y_in - .6, z + 14.2, z + 16.2)
        tower(m, (i0 + i1) * .5, (y_out + y_in) * .5, z + 17.0, spec["mast_height_m"] - 4.0, 6.5, 2.8)
        m.mast((i0 + i1) * .5, (y_out + y_in) * .5, spec["mast_height_m"] - 4.0, spec["mast_height_m"] + 1.0, .35, 5.0)
        m.sphere(i0 + 2.0, (y_out + y_in) * .5, z + 19.0, 1.6)
    else:
        # The Nimitz island: a tall block in tiers, the navigation bridge and flying control
        # glazed at the top, the tripod mast with its search radars, and the SATCOM domes.
        island_block(m, i0, i1, y_out, y_in, z, 12.0, .3)
        m.prism(i0 + 1.5, i1 - 1.0, y_out + .5, y_in - .3, z + 12.0, z + 17.5, .4, "bridge")
        m.box(i0 - 2.5, i0 + 5.0, y_in - 1.5, y_in + 1.2, z + 14.0, z + 17.0, "bridge_glazed")  # flying control
        m.box(i1 - 6.0, i1 + 1.5, y_out + 1.0, y_in - 1.0, z + 17.5, z + 20.5, "pilothouse")
        glaze(m, i0 + 2.0, i1 - 1.5, y_out + .8, y_in - .6, z + 15.4, z + 17.0)
        glaze(m, i1 - 5.5, i1 + 1.5, y_out + 1.0, y_in - 1.0, z + 18.6, z + 20.0)
        glaze(m, i0 - 2.5, i0 + 5.0, y_in - 1.5, y_in + 1.2, z + 15.2, z + 16.7, forward=False)
        lattice_tripod(m, (i0 + i1) * .5, (y_out + y_in) * .5, z + 20.5, spec["mast_height_m"] - 3.0, 3.4)
        m.mast((i0 + i1) * .5, (y_out + y_in) * .5, spec["mast_height_m"] - 3.0, spec["mast_height_m"] + 1.5, .3, 6.0)
        # SPS-48 planar array forward, SPS-49 mesh aft.
        m.cylinder(i1 - 2.5, (y_out + y_in) * .5, z + 20.5, z + 22.0, .5, 8, "pedestal")
        m.cbox(i1 - 2.5, (y_out + y_in) * .5, z + 24.0, .8, 5.0, 4.4, "search_array", "array_face")
        m.cylinder(i0 + 2.5, (y_out + y_in) * .5, z + 17.5, z + 21.0, .45, 8, "pedestal")
        m.cbox(i0 + 2.5, (y_out + y_in) * .5, z + 22.3, .5, 7.5, 2.6, "search_array", "array_face")
        for yy in (y_out + 1.8, y_in - 1.8):
            m.sphere(i0 + 7.0, yy, z + 18.8, 1.5)
    # The island's aft funnel-less exhaust grilles and the big hull-number board are left out.
    # Sponson weapons: ESSM and RAM on the modern ships, Sea Sparrow and Phalanx in 1990.
    kinds = ("box", "box", "ciws", "ciws") if era == 1990 else ("box", "ram", "ram", "box")
    c.sponson(.88, -1, kinds[0])
    c.sponson(.82, 1, kinds[1])
    c.sponson(.06, -1, kinds[2])
    c.sponson(.07, 1, kinds[3])
    if era != 1990:
        c.sponson(.03, -1, "ciws", 1.5)
    # The deck park: fighters along the starboard bow and in the street by the lifts, a Hawkeye
    # and helicopters aft of the island, the landing area kept clear.
    fighter = parked_tomcat if era == 1990 else parked_hornet
    flen = 19.1 if era == 1990 else 18.3
    spots = [(x(.93), -12.0, math.radians(150)), (x(.89), -15.5, math.radians(150)), (x(.85), -18.5, math.radians(150)),
             (x(.78), -18.0, math.radians(120)), (x(.74), -12.0, math.radians(120)), (x(.93), 9.0, math.radians(200)),
             (x(.86), 13.0, math.radians(200))]
    park(m, fighter, flen, spots, z + 1.6)
    park(m, parked_hawkeye, 17.6, [(x(.58), -18.0, math.radians(95))], z + 1.2)
    park(m, parked_helo, 19.8, [(x(.20), -16.0, math.radians(80))], z)
    c.finish()
    return c


def build_nimitz(m, spec):
    _us_carrier(m, spec, .40, 38.0)


def build_ford(m, spec):
    _us_carrier(m, spec, .30, 30.0, ford=True)


def build_nimitz_1990(m, spec):
    _us_carrier(m, spec, .40, 38.0, era=1990)


# --------------------------------------------------------------------------------------------
# Queen Elizabeth
# --------------------------------------------------------------------------------------------

def build_queen_elizabeth(m, spec):
    L = spec["length_m"]
    starboard = [(0.0, -21), (.04, -23), (.16, -26), (.66, -27), (.80, -24), (.93, -17), (1.0, -9)]
    port = [(1.0, 21), (.90, 27), (.56, 36), (.34, 36), (.16, 28), (.04, 24), (0.0, 21)]
    c = FlatTop(m, spec, L * .95, 39.0, 11.0, 17.5, starboard, port, flare=1.14)
    x, z = c.x, c.top
    # The ski ramp on the port side of the bow.
    ramp = [(x(.86), z), (x(1.0), z), (x(1.0), z + 5.8), (x(.94), z + 3.3)]
    m.vplate(ramp, 0.0, 20.0, "ski_jump", "flight_deck")
    # Two islands to starboard: navigation forward under the long-range radar, flying control aft
    # under its own radar, with the two big lifts between and abaft them.
    for (t0, t1, h, glazed) in ((.57, .66, 15.0, "bridge"), (.29, .37, 12.0, "bridge_glazed")):
        island_block(m, x(t0), x(t1), -27.0, -18.5, z, h, .6)
        m.prism(x(t0) + 1.5, x(t1) - 1.0, -26.5, -19.0, z + h, z + h + 4.5, .5, glazed)
        glaze(m, x(t0) + 2.0, x(t1) - 1.5, -26.0, -19.5, z + h + 2.4, z + h + 3.8)
        m.funnel((x(t0) + x(t1)) * .5 - 3.0, -22.7, z + h + 4.5, 3.0, 4.0, 6.0)
    fx = (x(.57) + x(.66)) * .5
    m.cylinder(fx + 4.0, -22.7, z + 19.5, z + 22.0, .6, 8, "pedestal")
    m.cbox(fx + 4.0, -22.7, z + 23.8, 1.2, 8.5, 3.6, "search_array", "array_face")
    m.mast(fx - 4.0, -22.7, z + 19.5, spec["mast_height_m"] + 1.0, .4, 5.0)
    ax = (x(.29) + x(.37)) * .5
    m.cylinder(ax + 2.0, -22.7, z + 16.5, z + 18.5, .5, 8, "pedestal")
    m.cbox(ax + 2.0, -22.7, z + 19.6, .8, 4.6, 2.2, "search_array", "array_face")
    c.lift(.45, .53, -1, edge=-26.5)
    c.lift(.17, .25, -1, edge=-26.0)
    c.spot_circles((.12, .22, .32, .42, .52, .62), 20.0, 6.5)
    m.stripe((x(.02), 8.0, z + .03), (x(.86), 8.0, z + .03), .5)
    for t in (.12, .88):
        c.sponson(t, -1, "ciws", 1.5)
    c.sponson(.10, 1, "ciws", 1.5)
    park(m, aw.lightning_b, 15.4, [(x(.78), -12.0, math.radians(135)), (x(.73), -12.0, math.radians(135)), (x(.68), -12.0, math.radians(135)),
                                   (x(.24), 14.0, math.radians(90))], z + 1.4)
    park(m, lambda mm, l: parked_helo(mm, l, 5, 9.3, True), 22.8, [(x(.40), 12.0, math.radians(90)), (x(.08), -10.0, math.radians(20))], z)
    c.finish()


# --------------------------------------------------------------------------------------------
# Charles de Gaulle
# --------------------------------------------------------------------------------------------

def build_charles_de_gaulle(m, spec):
    L = spec["length_m"]
    starboard = [(0.0, -17.5), (.04, -20), (.28, -21), (.34, -25), (.66, -25), (.72, -21), (.93, -15), (1.0, -10)]
    port = [(1.0, 10), (.93, 14), (.72, 18), (.64, 20), (.58, 34), (.48, 38), (.28, 34), (.12, 26), (.03, 20), (0.0, 17.5)]
    c = FlatTop(m, spec, L * .94, 31.5, 9.4, 16.5, starboard, port, flare=1.15)
    x, z = c.x, c.top
    c.angled_deck(.03, 1.0, 8.3, .55, 22.0, 14)
    c.catapult(.72, .985, 2.0, 2.0)
    c.catapult(.38, .56, 17.0, 17.0 + L * .18 * math.tan(math.radians(8.3)))
    # A compact island forward of amidships under a tall mast; two lifts to starboard abaft it.
    i0, i1 = x(.57), x(.69)
    island_block(m, i0, i1, -25.0, -17.0, z, 10.0, .4)
    m.prism(i0 + 1.0, i1 - .5, -24.5, -17.5, z + 10.0, z + 14.0, .4, "bridge")
    glaze(m, i0 + 1.5, i1 - 1.0, -24.1, -17.9, z + 12.2, z + 13.5)
    m.funnel(i0 + 4.0, -21.0, z + 14.0, 3.0, 3.6, 5.0)
    m.mast(i1 - 5.0, -21.0, z + 14.0, spec["mast_height_m"] + 1.0, .4, 5.0)
    m.cbox(i1 - 5.0, -21.0, z + 19.0, 1.0, 6.0, 2.4, "search_array", "array_face")
    m.sphere(i1 - 1.5, -21.0, z + 16.0, 2.0)
    m.sphere(i0 + 1.5, -21.0, z + 16.0, 1.4)
    c.lift(.36, .43, -1, 13.0)
    c.lift(.24, .31, -1, 13.0)
    c.sponson(.84, -1, "box")
    c.sponson(.80, 1, "box")
    c.sponson(.08, -1, "box")
    c.sponson(.10, 1, "ram")
    park(m, parked_rafale, 15.3, [(x(.90), -9.0, math.radians(150)), (x(.86), -11.5, math.radians(150)), (x(.82), -14.0, math.radians(150)),
                                   (x(.76), -13.0, math.radians(120)), (x(.90), 7.0, math.radians(200))], z + 1.4)
    park(m, parked_hawkeye, 17.6, [(x(.50), -14.0, math.radians(95))], z + 1.2)
    park(m, parked_helo, 16.1, [(x(.18), -12.0, math.radians(80))], z)
    c.finish()


# --------------------------------------------------------------------------------------------
# Amphibious flat-tops
# --------------------------------------------------------------------------------------------

def build_america(m, spec):
    L = spec["length_m"]
    starboard = [(0.0, -16.5), (.03, -18.5), (.42, -18.5), (.46, -21), (.68, -21), (.72, -18.5), (.93, -15), (1.0, -10)]
    port = [(1.0, 10), (.93, 15), (.72, 18.5), (.50, 18.5), (.46, 23), (.38, 23), (.34, 18.5), (.03, 18.5), (0.0, 16.5)]
    c = FlatTop(m, spec, L * .96, 32.3, 7.9, 18.0, starboard, port, flare=1.08, fullness=.66, transom=.9)
    x, z = c.x, c.top
    # A long island to starboard with its bridge forward, one lift abaft it and one on the port edge.
    i0, i1 = x(.45), x(.67)
    island_block(m, i0, i1, -21.0, -13.5, z, 11.0, .4)
    m.prism(x(.58), i1 - .5, -20.5, -14.0, z + 11.0, z + 15.5, .4, "bridge")
    glaze(m, x(.58) + .5, i1 - 1.0, -20.1, -14.4, z + 13.6, z + 14.9)
    m.box(x(.47), x(.55), -20.0, -14.5, z + 11.0, z + 13.5, "bridge_glazed")
    for t in (.50, .56):
        m.funnel(x(t), -17.0, z + 11.0, 3.0, 3.0, 5.0)
    m.mast(x(.62), -17.2, z + 15.5, spec["mast_height_m"] + 1.0, .4, 5.0)
    m.cbox(x(.62), -17.2, z + 21.0, 1.0, 6.0, 2.2, "search_array", "array_face")
    m.sphere(x(.52), -17.2, z + 15.0, 1.4)
    c.lift(.22, .29, -1, 13.0)
    c.lift(.38, .46, 1, 12.0, edge=18.5)
    c.spot_circles((.10, .20, .30, .56, .66, .78, .88), 7.0, 6.0)
    m.stripe((x(.02), 7.0, z + .03), (x(.98), 7.0, z + .03), .4)
    c.sponson(.92, -1, "ram", 1.5)
    c.sponson(.05, 1, "ram", 1.5)
    c.sponson(.06, -1, "ciws", 1.5)
    c.sponson(.60, 1, "ciws", 1.5)
    park(m, aw.lightning_b, 15.4, [(x(.84), -10.0, math.radians(135)), (x(.79), -10.0, math.radians(135)), (x(.74), -10.0, math.radians(135))], z + 1.4)
    park(m, parked_helo, 19.8, [(x(.30), -9.0, math.radians(75)), (x(.14), -9.0, math.radians(75))], z)
    c.finish()


def build_mistral(m, spec):
    L = spec["length_m"]
    starboard = [(0.0, -16.2), (.05, -16.8), (.60, -16.8), (.63, -18.5), (.80, -18.5), (.83, -16.8), (.94, -13), (1.0, -8)]
    port = [(1.0, 8), (.94, 13), (.83, 16.8), (.05, 16.8), (0.0, 16.2)]
    c = FlatTop(m, spec, L * .97, 32.0, 6.3, 21.0, starboard, port, flare=1.02, fullness=.70, transom=.95, gallery=3.0)
    x, z = c.x, c.top
    # A tall, slab-sided hull with a high island well forward to starboard and six spots.
    i0, i1 = x(.63), x(.80)
    island_block(m, i0, i1, -18.0, -11.0, z, 9.0, .4)
    m.prism(x(.72), i1 - .5, -17.5, -11.5, z + 9.0, z + 13.0, .4, "bridge")
    glaze(m, x(.72) + .5, i1 - 1.0, -17.1, -11.9, z + 11.2, z + 12.5)
    m.funnel(x(.68), -14.5, z + 9.0, 4.0, 3.2, 5.0)
    m.mast(x(.76), -14.5, z + 13.0, spec["mast_height_m"] + 1.0, .4, 4.0)
    m.sphere(x(.76), -14.5, z + 18.0, 1.8)
    m.cbox(x(.70), -14.5, z + 15.0, .8, 4.0, 1.6, "search_array", "array_face")
    c.spot_circles((.10, .22, .34, .46, .58, .88), 2.0, 7.0)
    for t in (.12, .52):
        x0, x1 = x(t) - 6.0, x(t) + 6.0
        for a, b in (((x0, -6.5), (x1, -6.5)), ((x0, 6.5), (x1, 6.5)), ((x0, -6.5), (x0, 6.5)), ((x1, -6.5), (x1, 6.5))):
            m.stripe((a[0], a[1], z + .04), (b[0], b[1], z + .04), .3, "marking_yellow", "lift_outline")
    # The stern door of the well deck.
    m.box(-L * .5 * .97 - .3, -L * .5 * .97 + .1, -7.0, 7.0, 1.2, 10.0, "stern_door", "rubber")
    park(m, parked_helo, 16.1, [(x(.22), -6.0, math.radians(90)), (x(.46), -6.0, math.radians(90))], z)
    c.finish()


BUILDERS = {
    "usn_cvn_nimitz": build_nimitz,
    "usn_cvn_ford": build_ford,
    "cw90_nimitz": build_nimitz_1990,
    "rn_cvf_queen_elizabeth": build_queen_elizabeth,
    "fra_cvn_charles_de_gaulle": build_charles_de_gaulle,
    "usn_lha_america": build_america,
    "fra_lhd_mistral": build_mistral,
}
