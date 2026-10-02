"""Aircraft, helicopter and ordnance builders for build_models.py.

Original stylised recognition shapes: planform, tail and engine arrangement for the aircraft,
external proportions for the weapons. Nose or bow at +X, Y to port, Z up, metres.
"""
import math

import numpy as np

from artkit import Model

# --------------------------------------------------------------------------------------------
# Aircraft finish
# --------------------------------------------------------------------------------------------


def aircraft_finish(m, L, radome_from=.33, start=0):
    """Radome zone on the fuselage, dark intakes and metal nozzles on the engines."""
    for p in list(m.parts[start:]):
        if p.name == "fuselage":
            mats = []
            for f in p.faces:
                c = p.verts[list(f)].mean(axis=0)
                mats.append("array_face" if c[0] > L * radome_from else p.material)
            p.face_materials = mats
        elif p.name == "engine":
            lo, hi = p.bounds()
            r = (hi[1] - lo[1]) * .5
            cy, cz = (lo[1] + hi[1]) * .5, (lo[2] + hi[2]) * .5
            m.cylinder(cy, cz, lo[0] - .025, lo[0] + .08, r * .84, 14, "nozzle", "x", m="titanium")
            m.cylinder(cy, cz, lo[0] - .032, lo[0] - .026, r * .65, 14, "exhaust", "x", m="rubber")
            if hi[0] > 0:
                m.cylinder(cy, cz, hi[0] + .01, hi[0] + .025, r * .85, 14, "intake", "x", m="rubber")


def flanker(m, L, canards=False, twin_seat=False, missiles=True):
    """Twin-engine Flanker planform: broad LERX, widely spaced engines, twin vertical fins."""
    start = m.mark()
    m.fuselage(L, L * .05, nose=.32, tail=.28, taper=.5, segs=20)
    span = L * .67
    for s in (-1, 1):
        m.plate([(L * .02, 0), (-L * .30, 0), (-L * .28, s * span / 2), (-L * .16, s * span / 2)], -.15, .15, "wing")
        m.plate([(L * .32, s * L * .04), (L * .02, s * L * .04), (-L * .02, s * L * .13)], -.14, .14, "lerx")
        m.plate([(-L * .34, s * L * .05), (-L * .46, s * L * .05), (-L * .46, s * L * .22), (-L * .40, s * L * .22)], -.12, .12, "stab")
        m.fin(-L * .24, L * .18, L * .06, L * .17, L * .10, y=s * L * .10)
        m.engine_pod(-L * .50, -L * .10, s * L * .07, -.6, L * .035)
        m.cbox(L * .0, s * L * .07, -.5, L * .22, L * .06, L * .06, "intake")
        if canards:
            m.plate([(L * .26, s * L * .05), (L * .16, s * L * .05), (L * .17, s * L * .15)], .30, .42, "canard")
        if missiles:
            for yy in (.24, .36):
                m.cylinder(s * span / 2 * yy * 2 * .5 + s * L * .02, -.55, -L * .30, -L * .30 + L * .17, L * .008, 8, "missile", "x", m="missile_body")
    m.cylinder(0, -.2, -L * .50, -L * .40, L * .02, 10, "tail_stinger", "x")
    m.canopy(L * .19, 0, L * .05, L * (.24 if twin_seat else .17), L * .06, L * .055)
    aircraft_finish(m, L, start=start)


def parked_flanker(m, L):
    flanker(m, L, canards=True, missiles=False)


def parked_lightning(m, L):
    lightning_b(m, L)


def lightning_b(m, L):
    """The STOVL Lightning airframe, drawn for a deck park."""
    start = m.mark()
    m.fuselage(L, L * .066, nose=.31, tail=.30, segs=20, taper=.55)
    span = 10.7
    for s in (-1, 1):
        m.plate([(L * .13, s * .78), (-L * .27, s * .88), (-L * .245, s * span / 2), (-L * .17, s * span / 2)], -.055, .055, "wing")
        m.plate([(L * .27, s * .62), (L * .10, s * 1.37), (-L * .31, s * 1.45), (-L * .4, s * .7)], -.40, .35, "chines")
        m.plate([(-L * .26, s * .60), (-L * .49, s * .63), (-L * .49, s * L * .22), (-L * .39, s * L * .23)], -.05, .05, "stab")
        m.fin(-L * .27, L * .19, L * .06, L * .145, L * .12, y=s * L * .075, cant=-s * .44, thickness=.09)
        m.prism(-L * .15, L * .13, s * 1.10 - .29, s * 1.10 + .29, -.55, .35, .1, "intake_fairing")
    m.engine_pod(-L * .505, -L * .18, 0, -.20, L * .047)
    m.canopy(L * .19, 0, L * .062, L * .18, L * .075, L * .054)
    m.cylinder(0, 0, L * .067, L * .068, L * .056, 16, "lift_fan_door")
    aircraft_finish(m, L, start=start)


def build_j15(m, spec):
    flanker(m, spec["length_m"], canards=True)


def build_j16(m, spec):
    flanker(m, spec["length_m"], canards=False, twin_seat=True)


def build_h6j(m, spec):
    start = m.mark()
    L = spec["length_m"]
    span = 33.0
    m.fuselage(L, L * .043, nose=.20, tail=.32, taper=.30, segs=20)
    r = L * .043
    for s in (-1, 1):
        x_le, x_te = L * .10, -L * .22
        tip_le = x_le - span * .30
        m.plate([(x_le, s * r), (x_te, s * r), (tip_le - 3.4, s * span / 2), (tip_le, s * span / 2)], -.28, .28, "wing")
        # Engines buried in the wing roots: long nacelles beside the fuselage with open intakes.
        m.engine_pod(-L * .27, L * .17, s * (r + 1.35), -.25, 1.25)
        m.plate([(-L * .36, s * .6), (-L * .47, s * .6), (-L * .49, s * L * .18), (-L * .43, s * L * .18)], -.12, .12, "stab")
        for k, frac in enumerate((.30, .42, .54)):
            yy = s * span / 2 * frac
            xc = x_le - (span / 2 * frac) * .60 - 3.5
            m.cbox(xc, yy, -1.15, 1.2, .3, .9, "pylon")
            m.cylinder(yy, -1.9, xc - 3.5, xc + 3.5, .36, 10, "missile", "x", m="missile_body")
    m.fin(-L * .30, L * .18, L * .07, L * .16, L * .11)
    m.ellipsoid(L * .30, 0, -r * .8, L * .05, r * .5, r * .45, 12, 5, "chin_radome", "array_face")
    m.canopy(L * .36, 0, r * .85, L * .08, r * 1.2, r * .55, "glazing")
    aircraft_finish(m, L, radome_from=.44, start=start)


def build_a6e(m, spec):
    """A-6E TRAM Intruder: bulbous side-by-side cockpit nose with the refuelling probe ahead of the
    canopy and the TRAM turret under the chin, a mid-mounted moderately swept wing, J52 nacelles
    along the lower fuselage sides, a tall swept fin and two Harpoons on the inboard pylons."""
    start = m.mark()
    L = spec["length_m"]
    half = 8.08
    r = L * .052
    m.fuselage(L, r, nose=.30, tail=.42, taper=.32, segs=18)
    for s in (-1, 1):
        x_le, x_te = L * .10, -L * .14
        tip_le = x_le - half * .47
        m.plate([(x_le, s * r), (x_te, s * r), (tip_le - 1.5, s * half), (tip_le, s * half)], -.16, .16, "wing")
        m.plate([(-L * .37, s * .5), (-L * .48, s * .5), (-L * .48, s * L * .19), (-L * .41, s * L * .19)], -.10, .10, "stab")
        m.engine_pod(-L * .24, L * .17, s * (r + .25), -r * .55, r * .42)
        for k, frac in enumerate((.30, .58)):
            yy = s * half * frac
            xc = x_le - half * frac * .47 - .9
            m.cbox(xc, yy, -.55, 1.4, .25, .6, "pylon")
            if k == 0:
                m.cylinder(yy, -1.15, xc - 2.0, xc + 2.0, .17, 10, "missile", "x", m="missile_body")
    m.fin(-L * .30, L * .21, L * .08, L * .25, L * .12)
    m.canopy(L * .25, 0, r * .85, L * .17, r * 1.75, r * .72)
    m.cylinder(0, r * 1.25, L * .33, L * .47, .07, 8, "refuel_probe", "x", m="titanium")
    m.ellipsoid(L * .40, 0, -r * .80, .42, .40, .34, 10, 5, "tram_turret", "glazing")
    aircraft_finish(m, L, radome_from=.40, start=start)


def turboprop_transport(m, L, span, rotodome=False, mad=False, chin=False):
    """The Y-8/Y-9 family: fat fuselage, high straight wing, four turboprops, big fin."""
    start = m.mark()
    r = L * .062
    shift = L * .04 if mad else 0.0
    m.fuselage(L - 2 * shift, r, nose=.16, tail=.36, taper=.15, segs=20).translate((shift, 0, 0))
    m.wedge(-L * .50 + 2 * shift, -L * .18, -r * .75, r * .75, -r * .95, -r * .1, "tail_upsweep", forward=False)
    x_le = L * .10
    for s in (-1, 1):
        m.plate([(x_le, s * r * .6), (x_le - L * .16, s * r * .6), (x_le - L * .13, s * span / 2), (x_le - L * .04, s * span / 2)], r * .55, r * .55 + .55, "wing")
        m.plate([(-L * .38, s * .5), (-L * .48, s * .5), (-L * .50, s * L * .18), (-L * .44, s * L * .18)], r * .2, r * .2 + .3, "stab")
        for frac in (.26, .50):
            yy = s * span / 2 * frac
            m.engine_pod(x_le - L * .14, x_le + L * .08, yy, r * .30, .80)
            m.propeller(x_le + L * .08 + .1, yy, r * .30, 2.2, 6)
    m.fin(-L * .30, L * .22, L * .08, L * .21, L * .10, thickness=.3)
    m.vplate([(-L * .10, r * .9), (-L * .30, r * .9), (-L * .30, r * 1.6)], -.12, .12, "dorsal_fillet")
    m.canopy(L * .36, 0, r * .75, L * .07, r * 1.2, r * .5, "glazing")
    if rotodome:
        m.cylinder(-L * .04, 0, r + 2.2, r + 3.0, L * .11, 24, "rotodome", m="radome")
        m.cbox(-L * .04, 0, r + 1.2, L * .06, 1.4, 2.0, "pylon")
        for s in (-1, 1):
            m.rod((-L * .09, s * 1.2, r * .9), (-L * .03, s * L * .05, r + 2.2), .12, "strut", "airframe", 6)
    if mad:
        m.cylinder(0, r * .35, -L * .50, -L * .41, .16, 8, "mad_boom", "x", m="array_face")
    if chin:
        m.ellipsoid(L * .34, 0, -r * .85, L * .05, r * .6, r * .45, 12, 5, "chin_radome", "array_face")
        m.box(-L * .08, L * .12, -r * .55, r * .55, -r * 1.05, -r * .85, "weapons_bay")
    aircraft_finish(m, L, radome_from=.44, start=start)


def build_kj500(m, spec):
    turboprop_transport(m, spec["length_m"], 38.0, rotodome=True)


def build_y8q(m, spec):
    turboprop_transport(m, spec["length_m"], 38.0, mad=True, chin=True)


def build_p1(m, spec):
    start = m.mark()
    L = spec["length_m"]
    span = 35.4
    r = L * .049
    m.fuselage(L * .92, r, nose=.15, tail=.30, taper=.2, segs=20).translate((L * .04, 0, 0))
    x_le = L * .07
    for s in (-1, 1):
        o = m.plate([(x_le, s * r * .6), (x_le - L * .16, s * r * .6), (x_le - L * .17, s * span / 2), (x_le - L * .11, s * span / 2)], -r * .70, -r * .70 + .5, "wing")
        o.rotate((1, 0, 0), s * .07)
        m.plate([(-L * .36, s * .5), (-L * .46, s * .5), (-L * .48, s * L * .16), (-L * .42, s * L * .16)], r * .1, r * .1 + .3, "stab")
        for frac in (.24, .44):
            yy = s * span / 2 * frac
            m.engine_pod(x_le - L * .13, x_le + L * .03, yy, -r * .95 - .3 + frac * 1.2, .78)
    m.fin(-L * .26, L * .20, L * .07, L * .20, L * .12, thickness=.3)
    m.cylinder(0, r * .3, -L * .50, -L * .41, .15, 8, "mad_boom", "x", m="array_face")
    m.box(-L * .18, L * .02, -r * .55, r * .55, -r * 1.02, -r * .9, "weapons_bay")
    m.canopy(L * .38, 0, r * .72, L * .07, r * 1.2, r * .5, "glazing")
    aircraft_finish(m, L, radome_from=.42, start=start)


def build_f2(m, spec):
    start = m.mark()
    L = spec["length_m"]
    half = 5.55
    m.fuselage(L, L * .044, nose=.31, tail=.31, taper=.40, segs=18)
    for s in (-1, 1):
        m.plate([(L * .09, s * L * .04), (-L * .27, s * L * .04), (-L * .26, s * half), (-L * .13, s * half)], -.07, .07, "wing")
        m.plate([(L * .24, s * L * .03), (L * .03, s * L * .105), (-L * .19, s * L * .075)], -.12, .04, "lerx")
        m.plate([(-L * .32, s * L * .025), (-L * .48, s * L * .025), (-L * .48, s * L * .19), (-L * .37, s * L * .20)], -.04, .05, "stab")
        m.cylinder(s * half, 0, -L * .29, -L * .11, .06, 8, "tip_rail", "x", m="titanium")
        m.cylinder(s * half * .55, -.45, -L * .27, -L * .02, .16, 8, "missile", "x", m="missile_body")
    m.fin(-L * .22, L * .26, L * .085, L * .19, L * .14)
    m.engine_pod(-L * .5, -L * .16, 0, 0, L * .036)
    m.engine_pod(-L * .12, L * .15, 0, -L * .048, L * .034)
    m.canopy(L * .22, 0, L * .044, L * .22, L * .067, L * .056)
    aircraft_finish(m, L, start=start)


def build_mohajer6(m, spec):
    start = m.mark()
    L = spec["length_m"]
    span = 10.0
    body = m.fuselage(L * .78, .32, nose=.22, tail=.30, taper=.55, segs=14)
    body.translate((L * .08, 0, 0))
    for s in (-1, 1):
        m.plate([(L * .12, s * .3), (L * .12 - 1.0, s * .3), (L * .12 - .9, s * span / 2), (L * .12, s * span / 2)], .22, .34, "wing")
        m.box(-L * .50, L * .05, s * 1.4 - .11, s * 1.4 + .11, .05, .30, "tail_boom")
        m.vplate([(-L * .40, .1), (-L * .50, .1), (-L * .50, 1.25), (-L * .44, 1.25)], s * 1.4 - .04, s * 1.4 + .04, "fin")
        m.cylinder(s * 2.2, -.12, L * .0, L * .0 + 1.5, .08, 8, "missile", "x", m="missile_body")
    m.plate([(-L * .50, -1.4), (-L * .42, -1.4), (-L * .42, 1.4), (-L * .50, 1.4)], 1.10, 1.18, "stab")
    m.propeller(L * .08 - L * .39 - .15, 0, 0, .70, 2)
    m.sphere(L * .30, 0, -.30, .22, 10, "seeker", "sensor_ball")
    m.canopy(L * .32, 0, .22, 1.0, .5, .25, "glazing")
    aircraft_finish(m, L, radome_from=.45, start=start)


# --------------------------------------------------------------------------------------------
# Helicopters
# --------------------------------------------------------------------------------------------


def seahawk(m, L, blades=4, radar=True, torpedoes=True):
    prof = [(L * .40, 0.0), (L * .36, L * .05), (L * .28, L * .075), (L * .10, L * .08),
            (-L * .08, L * .075), (-L * .14, L * .05), (-L * .16, L * .035), (-L * .42, L * .03),
            (-L * .44, L * .02), (-L * .45, 0.0)]
    cab = m.revolve(prof, segs=14, name="cabin")
    cab.scale((1.0, 1.0, .85))
    m.cbox(L * .08, 0.0, L * .07, L * .30, L * .12, L * .05, "engine_deck")
    m.plate([(-L * .36, -L * .14), (-L * .30, -L * .14), (-L * .30, L * .14), (-L * .36, L * .14)], 0.0, .1, "stabilator")
    m.vplate([(-L * .42, 0.0), (-L * .36, .03), (-L * .38, L * .14), (-L * .44, L * .15)], -.1, .1, "fin")
    m.tail_rotor(-L * .42, L * .06, L * .10, L * .14, 4)
    m.cylinder(L * .06, 0.0, L * .09, L * .13, L * .012, 8, "rotor_mast")
    m.rotor(L * .06, 0, L * .13, L * .41, blades, .5, .4)
    if radar:
        m.cbox(-L * .02, 0.0, -L * .07, L * .10, L * .09, L * .03, "radar_box", "array_face")
    for s in (-1, 1):
        m.cylinder(s * L * .07, -L * .075, L * .20, L * .22, L * .02, 8, "wheel", "x", m="rubber")
        m.cylinder(s * L * .11, L * .02, L * .02, L * .26, L * .012, 8, "stub_wing", "x")
        if torpedoes:
            m.cylinder(s * L * .11, -L * .03, L * .04, L * .19, L * .014, 8, "torpedo", "x", m="missile_body")
    m.cylinder(0, -L * .06, -L * .43, -L * .38, L * .015, 8, "tail_wheel", "x", m="rubber")
    m.canopy(L * .29, 0, L * .03, L * .13, L * .11, L * .06, "glazing")


def build_z20f(m, spec):
    seahawk(m, spec["length_m"], blades=5, radar=True)


def build_sh60k(m, spec):
    seahawk(m, spec["length_m"], blades=4, radar=True)


def dauphin(m, L):
    """Compact cabin and an enclosed fenestron: the Dauphin family's recognition features."""
    m.fuselage(L * .64, L * .074, nose=.23, tail=.31, taper=.37, segs=14)
    m.cbox(-L * .27, 0, L * .015, L * .36, L * .036, L * .048, "tail_boom")
    m.cbox(L * .025, 0, L * .074, L * .28, L * .096, L * .045, "engine_deck")
    m.canopy(L * .215, 0, L * .027, L * .13, L * .11, L * .078, "glazing")
    m.vplate([(-L * .37, L * .015), (-L * .46, L * .015), (-L * .44, L * .054), (-L * .39, L * .054)], -.11, .11, "fin_lower")
    m.vplate([(-L * .45, L * .170), (-L * .38, L * .177), (-L * .407, L * .248), (-L * .455, L * .248)], -.11, .11, "fin_upper")
    cx, cz, outer, inner = -L * .408, L * .11, L * .073, L * .052
    vertices = []
    for yy, rr in ((-.12, outer), (.12, outer), (-.12, inner), (.12, inner)):
        vertices += [(cx + rr * math.cos(i * math.tau / 24), yy, cz + rr * math.sin(i * math.tau / 24)) for i in range(24)]
    faces = []
    for i in range(24):
        j = (i + 1) % 24
        faces += [(i, j, 24 + j, 24 + i), (48 + i, 72 + i, 72 + j, 48 + j), (i, 48 + i, 48 + j, j), (24 + i, 24 + j, 72 + j, 72 + i)]
    m.add("fenestron_shroud", vertices, faces)
    for i in range(10):
        a = i * math.tau / 10
        m.vplate([(cx, cz), (cx + inner * math.cos(a), cz + inner * math.sin(a)), (cx + inner * math.cos(a + .13), cz + inner * math.sin(a + .13))], -.025, .025, "tail_rotor", "rubber")
    m.cylinder(L * .02, 0, L * .10, L * .17, L * .012, 12, "rotor_mast")
    m.rotor(L * .02, 0, L * .17, L * .43, 4, .42, .24)
    for s in (-1, 1):
        m.plate([(-L * .30, 0), (-L * .37, 0), (-L * .37, s * L * .14), (-L * .315, s * L * .14)], L * .027, L * .036, "tailplane")
        m.cylinder(s * L * .06, -L * .06, L * .05, L * .07, L * .016, 8, "wheel", "x", m="rubber")
    m.cbox(L * .12, 0, -L * .03, L * .10, L * .08, L * .03, "radar_box", "array_face")


def build_z9c(m, spec):
    dauphin(m, spec["length_m"])


def super_frelon(m, L, radar_box=False, torpedoes=False):
    """A big three-engined boat-hulled helicopter with sponsons and a six-blade rotor."""
    r = L * .075
    body = m.fuselage(L * .62, r, nose=.22, tail=.24, taper=.45, segs=16)
    body.translate((L * .07, 0, 0))
    m.box(-L * .06, L * .28, -r * .82, r * .82, -r * 1.05, -r * .35, "boat_hull")
    m.wedge(L * .28, L * .36, -r * .82, r * .82, -r * 1.05, -r * .35, "bow_chine", forward=False)
    for s in (-1, 1):
        m.ellipsoid(L * .02, s * (r + .8), -r * .55, L * .11, .75, .65, 12, 5, "sponson")
        m.cylinder(s * (r + .8), -r * 1.1, L * .0, L * .04, .35, 8, "wheel", "x", m="rubber")
    m.prism(-L * .50, -L * .17, -r * .35, r * .35, r * .05, r * .70, .15, "tail_boom")
    m.vplate([(-L * .44, r * .6), (-L * .50, r * .6), (-L * .49, r * 2.3), (-L * .46, r * 2.3)], -.12, .12, "fin")
    m.plate([(-L * .49, -r * 1.3), (-L * .44, -r * 1.3), (-L * .44, 0), (-L * .49, 0)], r * 1.6, r * 1.7, "tailplane")
    m.tail_rotor(-L * .475, -r * .40, r * 1.9, L * .09, 5)
    for yy in (-r * .45, 0.0, r * .45):
        m.cylinder(yy, r * 1.05, L * .0, L * .24, .48, 10, "engine", "x")
    m.cylinder(L * .05, 0, r * 1.0, r * 1.5, L * .014, 10, "rotor_mast")
    m.rotor(L * .05, 0, r * 1.5, L * .40, 6, .55, .2)
    m.canopy(L * .32, 0, r * .55, L * .10, r * 1.4, r * .55, "glazing")
    m.cylinder(L * .27, 0, -r * 1.05, -r * .55, .25, 8, "nose_wheel", m="rubber")
    if radar_box:
        m.box(-L * .20, -L * .04, -r * .75, r * .75, -r * 1.45, -r * 1.05, "radar_box", "array_face")
    if torpedoes:
        for s in (-1, 1):
            m.cylinder(s * (r + 1.1), -r * .15, L * .02, L * .16, L * .012, 8, "torpedo", "x", m="missile_body")
        m.box(-L * .12, -L * .02, -r * .5, r * .5, -r * 1.25, -r * 1.05, "sonobuoy_launcher")


def build_z18j(m, spec):
    super_frelon(m, spec["length_m"], radar_box=True)


def build_z18f(m, spec):
    super_frelon(m, spec["length_m"], torpedoes=True)


BUILDERS = {
    "cw90_a6e": build_a6e,
    "pla_bomber_h6j": build_h6j,
    "pla_fighter_j15": build_j15,
    "pla_fighter_j16": build_j16,
    "pla_aew_kj500": build_kj500,
    "pla_mpa_y8q": build_y8q,
    "jmsdf_mpa_p1": build_p1,
    "jasdf_fighter_f2": build_f2,
    "irn_uav_mohajer6": build_mohajer6,
    "pla_helo_z9c": build_z9c,
    "pla_helo_z20f": build_z20f,
    "pla_aew_z18j": build_z18j,
    "pla_helo_z18f": build_z18f,
    "jmsdf_helo_sh60k": build_sh60k,
}


from build_ordnance import weapon_model  # noqa: E402,F401
