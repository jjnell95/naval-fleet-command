"""Refined, original aircraft and submarine recognition meshes.

X forward, Y port, Z up; dimensions in metres. Public class proportions and visible
recognition features, not engineering drawings. Clean flight / submerged recognition
poses: no permanently extended submarine masts or decorative missile loadouts.
Register AFTER the earlier builders. See assets/README.md for regeneration.
"""
import math
from functools import partial

import numpy as np


def loft(m, stations, name, material, segs=32):
    """Elliptical sections (x, half-width, half-height, centre-height)."""
    verts = [(x, ry * math.cos(a), z + rz * math.sin(a))
             for x, ry, rz, z in stations
             for a in np.linspace(0, math.tau, segs, endpoint=False)]
    faces = []
    for i in range(len(stations) - 1):
        for j in range(segs):
            k = (j + 1) % segs
            faces.append((i * segs + j, i * segs + k, (i + 1) * segs + k, (i + 1) * segs + j))
    faces.extend([tuple(range(segs - 1, -1, -1)), tuple(range((len(stations) - 1) * segs, len(verts)))])
    return m.add(name, verts, faces, material, smooth=65)


def foil(m, stations, name="wing", material="airframe", side=1):
    """Tapered airfoil: (span position, leading X, chord, height, thickness).

    Rounded leading edges and fine trailing edges replace the old rectangular plates.
    Also used for submarine control surfaces; no aerodynamic performance is implied.
    """
    section = [(0, 0), (.06, .32), (.22, .50), (.48, .39), (.78, .19), (1, .01),
               (1, -.01), (.78, -.19), (.48, -.39), (.22, -.50), (.06, -.32)]
    verts = [(le - u * chord, side * y, z + v * thick)
             for y, le, chord, z, thick in stations for u, v in section]
    n = len(section)
    faces = []
    for i in range(len(stations) - 1):
        for j in range(n):
            k = (j + 1) % n
            faces.append((i * n + j, i * n + k, (i + 1) * n + k, (i + 1) * n + j))
    faces.extend([tuple(range(n - 1, -1, -1)), tuple(range((len(stations) - 1) * n, len(verts)))])
    return m.add(name, verts, faces, material, smooth=48)


def duct(m, x0, x1, radius, thickness, y=0, z=0, material="titanium", name="nozzle"):
    """Open annular duct with a visible inner wall; never a capped solid cylinder."""
    n = 32
    verts = [(x, y + r * math.cos(a), z + r * math.sin(a))
             for x, r in ((x0, radius), (x1, radius * .94),
                          (x1, radius * .94 - thickness), (x0, radius - thickness))
             for a in np.linspace(0, math.tau, n, endpoint=False)]
    faces = [(i * n + j, i * n + (j + 1) % n, ((i + 1) % 4) * n + (j + 1) % n,
              ((i + 1) % 4) * n + j) for i in range(4) for j in range(n)]
    return m.add(name, verts, faces, material, smooth=48)


def cockpit(m, L, x=.22, length=.20, width=.07, base=.044, height=.038, twin=False):
    m.canopy(L * x, 0, L * base, L * length, L * width, L * height, "canopy_gold")
    # Thin transverse canopy bow follows the glazing instead of a block on the fuselage.
    for t in ([.64, .32] if twin else [.67]):
        xx = L * (x - length / 2 + length * t)
        r = math.sin(math.pi * t) ** .65
        points = [(xx, L * width * .505 * r * math.cos(a),
                   L * (base + height * 1.015 * r * math.sin(a)))
                  for a in np.linspace(0, math.pi, 13)]
        for a, b in zip(points, points[1:]):
            m.rod(a, b, L * .001, "canopy_frame", "airframe", 5)


def jet_engine(m, L, y, z, radius, front=-.04, back=-.50):
    loft(m, [(L * back, radius * .85, radius * .85, z),
             (L * (back + .06), radius, radius, z),
             (L * front, radius, radius, z)], "engine_fairing", "airframe", 24).translate((0, y, 0))
    duct(m, L * (back - .012), L * (back + .04), radius * .9, radius * .10, y, z)
    m.cylinder(y, z, L * (back + .032), L * (back + .038), radius * .76, 24,
               "exhaust_recess", "x", m="rubber")


def intake(m, L, x, y, z, width, height):
    # Inclined side intake lip and inset dark throat, with a short blended fairing.
    for s in (-1, 1):
        yy = s * y
        p = m.prism(L * (x - .14), L * x, yy - width / 2, yy + width / 2,
                    z - height / 2, z + height / 2, width * .10, "intake_fairing", "airframe")
        m.box(L * x + .001, L * x + .009, yy - width * .40, yy + width * .40,
              z - height * .37, z + height * .32, "intake_throat", "rubber")


def jet_body(m, L, width=.046, height=.043, broad=.075, material="airframe", blunt=False):
    sections = [(-.49, .032, .028, -.008), (-.38, broad * .82, height * .70, -.005),
                (-.19, broad, height * .86, 0), (.01, broad, height, 0),
                (.18, width, height, .005), (.30, width * .90, height * .91, .002),
                (.40, width * .58, height * .63, -.002), (.47, width * .24, height * .26, -.005),
                (.50, .001, .001, -.006)]
    if blunt:
        sections[-3] = (.40, width * .85, height * .52, -.002)
    p = loft(m, [(x * L, y * L, z * L, c * L) for x, y, z, c in sections], "fuselage", material)
    p.face_materials = ["array_face" if p.verts[list(f), 0].mean() > L * .325 else material for f in p.faces]


def twin_fighter(m, spec, kind="hornet", twin=False, canards=False):
    L = spec["length_m"]
    tomcat, flanker = kind == "tomcat", kind == "flanker"
    span = 17.0 if tomcat else (14.7 if flanker else 13.62)
    body_mat = "airframe_blue" if flanker else "airframe"
    jet_body(m, L, broad=.085 if tomcat or flanker else .065, material=body_mat)
    for s in (-1, 1):
        if tomcat:
            foil(m, [(.5, L * .25, L * .52, 0, .7), (L * .16, L * .07, L * .31, 0, .32)], "glove", body_mat, s)
            wing = [(L * .14, L * .06, L * .22, .04, .35),
                    (span / 2, -L * .29, L * .082, .08, .09)]
        else:
            wing = [(L * .045, L * .08, L * .37, 0, L * .023),
                    (L * .18, -L * .015, L * .265, .04, L * .016),
                    (span / 2, -L * (.17 if flanker else .12), L * .105, .10, L * .004)]
            foil(m, [(L * .035, L * .29, L * .43, .10, L * .030),
                     (L * .125, L * .065, L * .28, .02, L * .008)], "lerx", body_mat, s)
        foil(m, wing, material=body_mat, side=s)
        foil(m, [(L * .04, -L * .29, L * .20, 0, L * .016),
                 (L * .23, -L * .40, L * .10, .02, L * .004)], "stabilator", body_mat, s)
        m.fin(-L * .23, L * .22, L * .075, L * .16, L * .14,
              y=s * L * (.095 if tomcat or flanker else .065), cant=-s * (.08 if tomcat or flanker else .35),
              thickness=L * .007, z0=L * .014, m=body_mat)
        jet_engine(m, L, s * L * (.078 if tomcat or flanker else .039), -L * .021, L * .033)
        if canards:
            foil(m, [(L * .035, L * .26, L * .105, .30, .14),
                     (L * .16, L * .16, L * .043, .25, .05)], "canard", body_mat, s)
        tipx = wing[-1][1] - wing[-1][2] * .5
        if not tomcat:
            m.cylinder(s * span / 2, .10, tipx - L * .05, tipx + L * .05, L * .003,
                       10, "tip_rail", "x", m="titanium")
        # A short trailing hinge is visible at inspection distances, not a white outline.
        a, b = wing[-2], wing[-1]
        m.rod((a[1] - a[2] * .80, s * a[0], a[3] + a[4] * .17),
              (b[1] - b[2] * .80, s * b[0], b[3] + b[4] * .20), L * .0007, "flap_hinge", "array_face", 5)
    intake(m, L, .075 if tomcat else .06, L * (.083 if tomcat or flanker else .062),
           -L * .024, L * .052, L * .055)
    cockpit(m, L, x=.22, length=.245 if twin or tomcat else .19, twin=twin or tomcat)
    if flanker:
        m.fuselage(L * .14, L * .019, nose=.15, tail=.25, segs=20,
                   name="tail_stinger", m=body_mat).translate((-L * .44, 0, -.10))
    if kind == "growler":
        for s in (-1, 1):
            m.fuselage(L * .20, .23, segs=20, name="wingtip_receiver", m="airframe_light").translate((-L * .17, s * span / 2, .12))
            m.fuselage(L * .24, .30, segs=20, name="jammer_pod", m="airframe_light").translate((-L * .14, s * L * .20, -.85))
            m.cbox(-L * .14, s * L * .20, -.45, 1.0, .15, .65, "pod_pylon", "airframe")


def lightning(m, spec, carrier=False):
    L = spec["length_m"]
    span = 13.1 if carrier else 10.7
    jet_body(m, L, width=.056, height=.055, broad=.086)
    for s in (-1, 1):
        foil(m, [(L * .046, L * .15, L * .42, -.05, .46),
                 (1.85, L * .05, L * .35, -.05, .24),
                 (span / 2, -L * .17, L * .083, -.02, .065)], side=s)
        foil(m, [(L * .045, -L * .255, L * .235, -.02, .18),
                 (L * .235, -L * .395, L * .10, .02, .065)], "stabilator", side=s)
        m.fin(-L * .22, L * .235, L * .09, L * .16, L * .155,
              y=s * L * .078, cant=-s * .46, z0=.23, thickness=.11, m="airframe")
        # Shoulder chine follows the body; no gaps between separate wing-root slabs.
        foil(m, [(L * .035, L * .29, L * .60, .10, .34),
                 (L * .10, L * .13, L * .46, .01, .17)], "chine", side=s)
        if carrier:
            # Outboard wing fold, drawn flush in the flight pose.
            m.rod((-L * .10, s * 4.4, .055), (-L * .24, s * 4.4, .055), .012,
                  "wing_fold", "array_face", 5)
    intake(m, L, .19, L * .068, -.20, .58, .67)
    jet_engine(m, L, 0, -.10, L * .045)
    cockpit(m, L, x=.22, length=.21, width=.084, base=.057, height=.049)
    if not carrier:
        # Closed lift-fan door follows the upper fuselage, without a raised disc.
        m.ellipsoid(-.20, 0, L * .054, .79, .66, .042, 28, 6, "lift_fan_door", "airframe_light")


def delta_fighter(m, spec, kind="rafale"):
    L = spec["length_m"]
    span = {"rafale": 10.9, "typhoon": 10.95, "gripen": 8.4}[kind]
    jet_body(m, L, width=.040, height=.043, broad=.052)
    for s in (-1, 1):
        foil(m, [(L * .03, L * .19, L * .53, -.06, .31),
                 (span / 2, -L * .255, L * .06, .06, .05)], side=s)
        foil(m, [(L * .034, L * .31, L * .13, .25, .13),
                 (L * .16, L * .225, L * .045, .25, .05)], "canard", side=s)
    m.fin(-L * .23, L * .26, L * .075, L * .215, L * .15, z0=.2, thickness=.13, m="airframe")
    if kind == "gripen":
        jet_engine(m, L, 0, -.08, L * .034)
    else:
        for s in (-1, 1):
            jet_engine(m, L, s * L * .029, -.12, L * .028)
    if kind == "typhoon":
        intake(m, L, .19, L * .022, -L * .048, L * .039, L * .041)
    else:
        intake(m, L, .20, L * .050, -L * .015, L * .035, L * .043)
    cockpit(m, L, x=.265, length=.195, base=.046, height=.040)


def falcon(m, spec, f2=False):
    L = spec["length_m"]
    half = 5.55 if f2 else 4.98
    mat = "airframe_blue" if f2 else "airframe"
    jet_body(m, L, width=.039, height=.042, broad=.047, material=mat)
    for s in (-1, 1):
        foil(m, [(.45, L * .13, L * .39, 0, .31), (half, -L * .12, L * .105, .02, .06)], material=mat, side=s)
        foil(m, [(.30, L * .27, L * .47, .02, .22), (L * .10, L * .05, L * .28, .02, .08)], "lerx", mat, s)
        foil(m, [(.35, -L * .30, L * .18, -.05, .17), (L * .21, -L * .385, L * .10, -.05, .04)], "stabilator", mat, s)
        m.fin(-L * .27, L * .12, L * .035, L * .068, L * .05, y=s * .48,
              cant=math.pi - s * .15, z0=-.30, thickness=.07, m=mat, name="ventral_fin")
        m.cylinder(s * half, .02, -L * .27, -L * .085, .045, 10, "tip_rail", "x", m="titanium")
    m.fin(-L * .18, L * .31, L * .095, L * .22, L * .185, z0=.22, thickness=.15, m=mat)
    jet_engine(m, L, 0, 0, L * .037)
    loft(m, [(-L * .16, .43, .34, -.51), (L * .12, .45, .36, -.60),
             (L * .17, .36, .29, -.62)], "chin_intake", mat, 24)
    m.cylinder(0, -.62, L * .17, L * .171, .29, 24, "intake_throat", "x", m="rubber").scale((1, 1.25, 1), (0, 0, -.62))
    cockpit(m, L, x=.25, length=.23, width=.074, base=.044, height=.047)


def glazed_panel(m, L, body_sections, corners, side):
    """Inset framed panes conform to the curved body instead of sitting above the nose."""
    sections = np.asarray(body_sections)
    # Tessellate the curved patch: a single flat quad cuts through the loft.
    points, faces = [], []
    n = 7
    corners = np.asarray(corners)
    for inset in (-.012, .025):
        for v in np.linspace(0, 1, n):
            for u in np.linspace(0, 1, n):
                x, a = ((1 - u) * (1 - v) * corners[0] + u * (1 - v) * corners[1]
                        + u * v * corners[2] + (1 - u) * v * corners[3])
                ry, rz, z = [np.interp(L * x, sections[:, 0], sections[:, i])
                             for i in (1, 2, 3)]
                angle = math.radians(a)
                points.append((L * x, side * (ry + inset) * math.sin(angle),
                               z + (rz + inset) * math.cos(angle)))
    for offset in (0, n * n):
        for row in range(n - 1):
            for col in range(n - 1):
                a = offset + row * n + col
                f = (a, a + 1, a + n + 1, a + n)
                faces.append(f if offset else tuple(reversed(f)))
    perimeter = list(range(n)) + [i * n + n - 1 for i in range(1, n)]
    perimeter += list(range(n * n - 2, n * (n - 1) - 1, -1))
    perimeter += [i * n for i in range(n - 2, 0, -1)]
    for a, b in zip(perimeter, perimeter[1:] + perimeter[:1]):
        faces.append((a, b, b + n * n, a + n * n))
    m.add("cockpit_windows", points, faces, "glazing", smooth=65)


def patrol(m, spec, kind="poseidon", advanced=False):
    L = spec["length_m"]
    hawkeye, orion, viking = kind == "hawkeye", kind == "orion", kind == "viking"
    span = {"poseidon": 37.64, "hawkeye": 24.56, "orion": 30.4, "viking": 20.93}[kind]
    r = L * (.058 if hawkeye else .073 if viking else .044 if orion else .048)
    # Orion's MAD boom is included in the catalogue length, not an extra appendage.
    tail_x = -.40 if orion else -.50
    body_sections = [(L * tail_x, .04, .07, r * .25), (-L * .33, r * .50, r * .60, r * .20),
             (-L * .18, r, r, 0), (L * .28, r, r, 0),
             (L * .37, r * .90, r * .86, 0), (L * .425, r * .71, r * .63, -r * .07),
             (L * .47, r * .37, r * .32, -r * .18), (L * .49, r * .14, r * .15, -r * .21),
             (L * .50, .01, .01, -r * .22)]
    loft(m, body_sections, "fuselage", "airframe_light")
    wz = r * (.75 if hawkeye or viking else -.55 if not orion else .0)
    sweep = L * (.055 if hawkeye else .07 if viking else .09 if orion else .30)
    root = L * (.22 if viking else .16)
    for s in (-1, 1):
        foil(m, [(r * .45, L * .10, root, wz, r * .26),
                 (span * .22, L * .07 - sweep * .40, root * .64, wz + .15, r * .17),
                 (span / 2, L * .10 - sweep, L * .045, wz + .55, .09)],
             material="airframe_light", side=s)
        tail_z = r * .45 + L * .18 if viking else r * .35
        foil(m, [(0, -L * .31, L * .16, tail_z, .22),
                 (L * (.25 if hawkeye else .18), -L * .405, L * .065, tail_z + .15, .07)],
             "tailplane", "airframe_light", s)
        for fraction in ((.32, .65) if orion else (.30,) if hawkeye else (.32,)):
            yy = s * span / 2 * fraction
            ex = L * .085 - sweep * fraction
            ez = wz - r * (.25 if orion or hawkeye else .95)
            er = r * (.40 if orion else .55)
            loft(m, [(ex - L * .13, er * .5, er * .5, ez),
                     (ex - L * .07, er, er, ez), (ex + L * .035, er, er, ez),
                     (ex + L * .055, er * .80, er * .80, ez)],
                 "nacelle", "airframe_light", 24).translate((0, yy, 0))
            if hawkeye or orion:
                m.propeller(ex + L * .06, yy, ez, 2.05 if hawkeye else 2.0, 8 if advanced else 4)
            else:
                duct(m, ex + L * .050, ex + L * .065, er * .82, er * .10, yy, ez, "airframe_light", "intake_lip")
                m.cylinder(yy, ez, ex + L * .057, ex + L * .058, er * .68, 24, "fan_shadow", "x", m="rubber")
                m.cbox(ex - .5, yy, (ez + wz) / 2, L * .075, .24, abs(ez - wz), "pylon", "airframe_light")
        if hawkeye:
            for yy in (L * .09, L * .24):
                m.fin(-L * .34, L * .125, L * .075, L * .13, L * .03,
                      y=s * yy, z0=r * .32, thickness=.10, m="airframe_light")
    if not hawkeye:
        m.fin(-L * .235, L * .25, L * .07, L * .18, L * .17,
              z0=r * .45, thickness=.22, m="airframe_light")
    if hawkeye:
        m.prism(-L * .14, L * .015, -.32, .32, r * .6, r * 2.6, .1, "radar_pylon", "airframe_light")
        m.ellipsoid(-L * .10, 0, r * 2.65, 3.66, 3.66, .42, 48, 10, "rotodome", "array_face")
    if orion:
        m.cylinder(0, r * .25, -L * .5, -L * .36, .10, 16, "mad_boom", "x", m="array_face")
    for s in (-1, 1):
        for pane in [[(.387, 6), (.425, 7), (.434, 40), (.390, 47)],
                     [(.345, 48), (.382, 48), (.390, 73), (.345, 74)]]:
            glazed_panel(m, L, body_sections, pane, s)
        for xx in (-.08, .05, .17):
            if not hawkeye:
                m.ellipsoid(L * xx, s * r * .998, r * .08, .16, .022, .21, 12, 6, "observer_window", "glazing")
    m.box(-L * .12, L * .10, -r * .5, r * .5, -r * 1.005, -r * .96, "weapons_bay", "array_face")


def bear_patrol(m, spec):
    """Tu-142: swept shoulder wings, long inboard nacelles and four pairs of propellers."""
    L = spec["length_m"]
    skin = "airframe_light"
    body = [(L * x, y, z, h) for x, y, z, h in [
        (-.50, .07, .10, .48), (-.43, .65, .77, .40), (-.28, 1.30, 1.38, .19),
        (-.12, 1.53, 1.56, .02), (.27, 1.55, 1.58, 0), (.35, 1.45, 1.48, .04),
        (.40, 1.22, 1.29, .08), (.44, .95, .85, -.12), (.49, .36, .35, -.20),
        (.50, .06, .07, -.20)]]
    loft(m, body, "fuselage", skin)
    m.ellipsoid(L * .15, 0, -1.24, 3.0, 1.40, .87, 24, 8, "belly_fairing", "array_face")
    m.fin(-L * .263, 9.25, 3.3, 7.4, 6.8, z0=.98, thickness=.40, m=skin)
    for side in (-1, 1):
        foil(m, [(.65, L * .147, 8.8, .45, 1.10), (8.1, L * .070, 7.5, .67, .83),
                 (17.2, -L * .06, 4.8, 1.02, .48), (24.8, -L * .166, 2.22, 1.32, .18)],
             material=skin, side=side)
        foil(m, [(.37, -L * .328, 6.1, .77, .50), (9.0, -L * .445, 2.4, 1.28, .16)],
             "tailplane", skin, side)
        for pane in [[(.368, 6), (.397, 6), (.417, 48), (.377, 48)],
                     [(.339, 51), (.373, 52), (.382, 76), (.341, 77)]]:
            glazed_panel(m, L, body, pane, side)
        for span_pos, leading_x, aft in [(7.9, 3.9, -12.5), (15.8, -1.9, -5.4)]:
            y = side * span_pos
            z = .56
            stations = [(aft, .10, .20, .25), (-3.2, .61, .70, .10),
                        (-.8, .77, .83, .03), (1.9, .81, .82, 0), (2.4, .48, .53, 0)]
            loft(m, [(leading_x + x, ry, rz, z + h) for x, ry, rz, h in stations],
                 "nacelle", skin, 24).translate((0, y, 0))
            # Two separated four-blade rows, with opposite blade sweep and a shared axis.
            for row, spin in enumerate((1, -1)):
                hub_x = leading_x + 2.45 + row * .48
                m.cylinder(y, z, hub_x - .11, hub_x + .13, .47, 16, "propeller_hub", "x", m="titanium")
                for blade in range(4):
                    outline = [(.26, -.10), (.91, -.23), (2.35, -.18), (2.83, -.05),
                               (2.79, .12), (1.32, .26), (.40, .17)]
                    p = m.plate([(r, spin * chord) for r, chord in outline], -.05, .05,
                                "propeller_blade", "rubber")
                    p.rotate((0, 1, 0), -math.pi / 2)
                    p.rotate((1, 0, 0), blade * math.pi / 2 + row * math.pi / 4 + .12)
                    p.translate((hub_x, y, z))
            m.ellipsoid(leading_x + 3.10, y, z, .59, .46, .46, 20, 6,
                        "spinner", "airframe_light")


def seahawk_romeo(m, spec):
    """MH-60R: glazed naval cabin, fixed wheels, exposed canted tail rotor and low belly fairing."""
    L = spec["length_m"]
    skin = "airframe"
    body = [(L * x, y, z, h) for x, y, z, h in [
        (-.204, .30, .41, .35), (-.156, .72, .79, .19), (-.098, 1.12, 1.14, .04),
        (-.044, 1.27, 1.29, .00), (.165, 1.31, 1.29, .01), (.223, 1.22, 1.25, .03),
        (.272, 1.08, 1.06, .00), (.312, .86, .66, -.23), (.347, .53, .37, -.33),
        (.364, .12, .14, -.35)]]
    loft(m, body, "cabin", skin)
    loft(m, [(-L*.44, .19, .19, .99), (-L*.33, .32, .30, .86),
             (-L*.21, .45, .41, .59), (-L*.13, .63, .60, .35)], "tail_boom", skin, 20)
    loft(m, [(-2.28, .30, .21, 1.01), (-1.71, .68, .43, 1.15),
             (1.85, .72, .45, 1.23), (2.96, .49, .26, 1.13)], "rotor_fairing", skin, 20)
    for side in (-1, 1):
        for pane in [[(.224, 4), (.257, 4), (.318, 44), (.280, 54)],
                     [(.160, 41), (.221, 34), (.273, 58), (.165, 86)],
                     [(.080, 45), (.147, 45), (.145, 87), (.081, 87)],
                     [(-.017, 52), (.061, 50), (.062, 84), (-.018, 84)]]:
            glazed_panel(m, L, body, pane, side)
        # Paired exhaust fairings, proud of the roof and blended into the cabin shoulders.
        loft(m, [(-1.89, .23, .23, 1.20), (-1.08, .43, .44, 1.28),
                 (1.32, .48, .43, 1.32), (1.95, .39, .32, 1.26)],
             "engine_housing", skin, 16).translate((0, side * .76, 0))
        m.cylinder(side*.76, 1.26, 1.94, 1.96, .255, 16, "intake", "x", m="rubber")
        foil(m, [(.07, -L*.294, 1.40, .81, .14), (2.08, -L*.320, .90, .90, .08)],
             "stabilator", skin, side)
        wheel_x = L * .12
        m.rod((wheel_x, side*.92, -.57), (wheel_x-.17, side*1.53, -1.15), .085,
              "main_gear", "titanium", 8)
        m.cylinder(wheel_x-.17, -1.16, side*1.54-.12, side*1.54+.12, .36, 20,
                   "main_wheel", "y", m="rubber")
        m.cylinder(wheel_x-.17, -1.16, side*1.55-.13, side*1.55+.13, .14, 14,
                   "wheel_hub", "y", m=skin)
    # Naval tailwheel is forward of the stabilator, below the joint of the cabin and tail.
    m.rod((-L*.152, 0, -.21), (-L*.166, 0, -.93), .105, "tail_gear", "titanium", 10)
    for y in (-.135, .135):
        m.cylinder(-L*.166, -.96, y-.083, y+.083, .24, 18, "tail_wheel", "y", m="rubber")
    m.ellipsoid(2.72, 0, -1.12, 1.02, .69, .33, 24, 8, "belly_fairing", skin)
    m.fin(-L*.40, 1.04, .62, 2.13, .47, z0=.83, thickness=.28, m=skin)
    mark = m.mark()
    m.tail_rotor(-L*.429, -.28, 2.68, 1.68, 4)
    for part in m.since(mark):
        part.rotate((1, 0, 0), math.radians(-16), (-L*.429, -.28, 2.68))
    m.cylinder(L*.049, 0, 1.40, 2.48, .17, 16, "rotor_mast", m="titanium")
    m.rotor(L*.049, 0, 2.48, 8.17, 4, .47, .28)


# Hull beam, sail centre/length/height (fractions of L or radius), plane location,
# tail and propulsor are class-specific. Small fittings are illustrative.
SUBS = {
    "usn_ssn_virginia": (10.4, .155, .14, 1.04, "bow", "cross", "jet"),
    "rn_ssn_astute": (11.3, .14, .17, 1.10, "bow", "cross", "jet"),
    "fra_ssn_suffren": (8.8, .18, .14, 1.08, "bow", "x", "jet"),
    "rfn_ssn_yasen_m": (13.0, .17, .15, .98, "bow", "cross", "screw"),
    "rfn_ssk_kilo": (9.9, .11, .20, 1.18, "bow", "cross", "screw"),
    "rfn_ssk_kilo_877": (9.9, .11, .20, 1.18, "bow", "cross", "screw"),
    "swe_ssk_gotland": (6.2, .16, .17, 1.45, "sail", "x", "screw"),
    "cw90_los_angeles": (10.0, .15, .15, 1.16, "sail", "cross", "screw"),
    "cw90_victor3": (10.6, .12, .17, 1.17, "bow", "cross", "screw"),
    "pla_ssn_type093b": (11.0, .13, .16, 1.12, "sail", "cross", "screw"),
    "pla_ssk_type039a": (8.4, .13, .19, 1.26, "sail", "cross", "screw"),
    "jmsdf_ssk_taigei": (9.1, .14, .18, 1.14, "sail", "x", "screw"),
    "irn_ssm_ghadir": (2.8, .11, .16, 1.40, "bow", "cross", "screw"),
}


def submarine(m, spec):
    sid, L = spec["id"], spec["length_m"]
    beam, sx, sl, sh, planes, tail, propulsor = SUBS[sid]
    R = beam / 2
    diesel = any(k in sid for k in ("kilo", "gotland", "type039", "taigei", "ghadir"))
    # A tangent-rounded sonar bow and tapered afterbody, not a spindle with a pointed bow.
    stations = [(-.485, .13), (-.46, .21), (-.42, .43), (-.36, .72),
                (-.28, .94), (-.19, 1), (.20, 1), (.30, 1), (.36, .97),
                (.41, .88), (.45, .72), (.48, .46), (.497, .17), (.5, .005)]
    hull = loft(m, [(x * L, r * R, r * R * (1.04 if diesel else 1), 0) for x, r in stations],
                "outer_hull", "rubber", 48)
    # Subtle bow-cap boundary in the same dark family, never a bright metal ring.
    hull.face_materials = ["boot_topping" if hull.verts[list(f), 0].mean() > L * .39 else "rubber" for f in hull.faces]
    if diesel or sid == "rn_ssn_astute":
        # Faired casing merges into the circular pressure-hull envelope.
        loft(m, [(-L * .32, .08, .05, R * .90), (-L * .22, R * .42, R * .14, R * .93),
                 (L * .25, R * .40, R * .14, R * .93), (L * .38, .06, .04, R * .92)],
             "upper_casing", "rubber", 24)
    # Loft the sail vertically with an oval plan and a smaller rounded crown.
    n = 32
    verts = []
    for z, size, shift in ((R * .82, 1.05, 0), (R * 1.10, 1, 0),
                           (R * (1 + sh * .88), .88, -L * .008), (R * (1 + sh), .76, -L * .012)):
        for a in np.linspace(0, math.tau, n, endpoint=False):
            # Rounded leading/trailing edges; fairly straight sides in the middle.
            xx = math.cos(a)
            yy = math.copysign(abs(math.sin(a)) ** .5, math.sin(a))
            verts.append((L * sx + shift + L * sl * .5 * size * xx, R * .27 * size * yy, z))
    faces = [(i * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n,
              (i + 1) * n + j) for i in range(3) for j in range(n)]
    faces.extend([tuple(range(n - 1, -1, -1)), tuple(range(3 * n, 4 * n))])
    m.add("sail", verts, faces, "rubber", smooth=60)
    for a in ([math.pi / 4 + i * math.pi / 2 for i in range(4)] if tail == "x" else
              [i * math.pi / 2 for i in range(4)]):
        foil(m, [(R * .20, -L * .36, L * .10, 0, R * .13),
                 (R * 1.75, -L * .395, L * .052, 0, R * .035)],
             "x_rudder" if tail == "x" else "stern_fin", "rubber").rotate((1, 0, 0), a)
    px = L * (sx + .025 if planes == "sail" else .315)
    pz = R * (1 + sh * .56) if planes == "sail" else R * .18
    for s in (-1, 1):
        foil(m, [(R * (.15 if planes == "sail" else .82), px, L * .060, pz, R * .10),
                 (R * 1.62, px - L * .012, L * .034, pz, R * .025)],
             planes + "_plane", "rubber", s)
    top = R * (1 + sh)
    # Retracted mast heads and flush hatches; the model does not imply active sensors.
    for t, radius in ((-.035, .028), (0, .021), (.027, .016)):
        m.cylinder(L * (sx + t) - L * .01, 0, top * .987, top + R * .035,
                   R * radius * 1.8, 16, "retracted_mast", m="boot_topping")
    for x in (-L * .12, L * .285):
        m.cylinder(x, 0, R * 1.001, R * 1.012, min(.70, R * .15), 24,
                   "escape_hatch", m="boot_topping")
    if sid == "cw90_victor3":
        m.fuselage(L * .15, R * .26, nose=.28, tail=.28, segs=28,
                   name="towed_array_pod", m="rubber").translate((-L * .385, 0, R * 1.60))
    if sid == "pla_ssn_type093b":
        loft(m, [(-L * .17, .02, .02, R * .95), (-L * .12, R * .43, R * .20, R),
                 (L * .03, R * .43, R * .20, R), (L * .05, .02, .02, R * .95)],
             "dorsal_fairing", "rubber", 24)
    if propulsor == "jet":
        duct(m, -L * .51, -L * .463, R * .58, R * .085, material="rubber", name="pumpjet_shroud")
        for a in np.linspace(0, math.tau, 7, endpoint=False):
            foil(m, [(R * .10, -L * .47, L * .019, 0, R * .02),
                     (R * .50, -L * .474, L * .014, 0, R * .01)], "stator", "boot_topping").rotate((1, 0, 0), a)
    else:
        # Skewed, pitched blades, visibly distinct from the stationary tailplanes.
        for a in np.linspace(0, math.tau, 5 if "ghadir" in sid else 7, endpoint=False):
            p = m.vplate([(-L * .490, R * .11), (-L * .502, R * .45),
                          (-L * .495, R * .85), (-L * .478, R * .91),
                          (-L * .475, R * .66), (-L * .484, R * .14)],
                         -R * .035, R * .035, "screw_blade", "bronze")
            p.rotate((0, 0, 1), .30, (-L * .49, 0, 0)).rotate((1, 0, 0), a)
    m.revolve([(-L * .518, .015), (-L * .504, R * .15), (-L * .474, R * .15)],
              24, "propulsor_hub", "boot_topping" if propulsor == "jet" else "bronze")
    for part in m.parts:
        if part.material == "rubber":
            part.material = "submarine_coating"
        if part.face_materials:
            part.face_materials = ["submarine_coating" if mat == "rubber" else mat for mat in part.face_materials]
    m.waterline_z = R * .72


BUILDERS = {sid: submarine for sid in SUBS}
BUILDERS.update({
    "usn_fighter_fa18e": partial(twin_fighter, kind="hornet"),
    "usn_fighter_fa18f": partial(twin_fighter, kind="hornet", twin=True),
    "usn_ea_ea18g": partial(twin_fighter, kind="growler", twin=True),
    "cw90_f14a": partial(twin_fighter, kind="tomcat", twin=True),
    "rfn_fighter_su35s": partial(twin_fighter, kind="flanker"),
    "rfn_strike_su30sm": partial(twin_fighter, kind="flanker", twin=True, canards=True),
    "pla_fighter_j15": partial(twin_fighter, kind="flanker", canards=True),
    "pla_fighter_j16": partial(twin_fighter, kind="flanker", twin=True),
    "usn_fighter_f35c": partial(lightning, carrier=True),
    "rn_fighter_f35b": lightning,
    "fra_fighter_rafale_m": delta_fighter,
    "raf_fighter_typhoon": partial(delta_fighter, kind="typhoon"),
    "swe_fighter_gripen_c": partial(delta_fighter, kind="gripen"),
    "usaf_fighter_f16c": falcon,
    "jasdf_fighter_f2": partial(falcon, f2=True),
    "usn_mpa_p8a": patrol,
    "rfn_mpa_tu142": bear_patrol,
    "usn_helo_mh60r": seahawk_romeo,
    "cw90_p3c": partial(patrol, kind="orion"),
    "cw90_s3a": partial(patrol, kind="viking"),
    "usn_aew_e2d": partial(patrol, kind="hawkeye", advanced=True),
    "fra_aew_e2c": partial(patrol, kind="hawkeye"),
    "cw90_e2c": partial(patrol, kind="hawkeye"),
})
