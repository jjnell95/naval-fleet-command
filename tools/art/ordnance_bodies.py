"""The slender revolved body shared by the gallery's guided-weapon icons."""
import math


def zone_materials(part, L):
    """Dark nose cap, a yellow ring and a metal tail section on the revolved body."""
    mats = []
    for f in part.faces:
        c = part.verts[list(f)].mean(axis=0)
        if c[0] > L * .27:
            mats.append("seeker")
        elif -L * .38 < c[0] < -L * .29:
            mats.append("marking_yellow")
        elif c[0] < -L * .4:
            mats.append("titanium")
        else:
            mats.append("missile_body")
    part.face_materials = mats


def fin_set(m, x_le, root, tip_x, span, count=4, thickness=.023, phase=0.0, name="tail_fin"):
    for k in range(count):
        o = m.plate([(x_le, 0), (x_le - root, 0), (tip_x - root * .35, span), (tip_x, span)], -thickness, thickness, name, "titanium")
        o.rotate((1, 0, 0), k * math.tau / count + phase)


def ogive(m, L, R, blunt=False, name="weapon_body"):
    profile = [(-L / 2, .04), (-L / 2 + L * .09, R), (L * .26, R)]
    for i in range(1, 13):
        t = i / 12
        power = .45 if blunt else 1.1
        profile.append((L * .26 + L * .24 * t, R * max(.005, math.cos(t * math.pi / 2) ** power)))
    body = m.revolve(profile, 24, name, "missile_body")
    zone_materials(body, L)
    return body


def slender_body(m, L, R, tail=3.0, canards=False, strakes=False, booster=False, wings=False, ducts=0):
    ogive(m, L, R)
    fin_set(m, -L * .26, L * .16, -L * .39, R * tail, 4)
    if strakes:
        for k in range(4):
            o = m.plate([(-L * .15, 0), (L * .08, 0), (-L * .05, R * tail * 1.2), (-L * .22, R * tail * 1.2)], -.018, .018, "mid_fin", "titanium")
            o.rotate((1, 0, 0), k * math.tau / 4)
    if canards:
        for k in range(4):
            o = m.plate([(L * .20, 0), (L * .30, 0), (L * .25, R * 2.2), (L * .18, R * 2.2)], -.015, .015, "canard", "titanium")
            o.rotate((1, 0, 0), k * math.tau / 4)
    if booster:
        m.cylinder(0, 0, -L * .50, -L * .20, R * 1.15, 24, "booster", "x", m="missile_body")
        fin_set(m, -L * .32, L * .14, -L * .44, R * 2.6, 4, .02, math.pi / 4, "booster_fin")
    if wings:
        for sign in (-1, 1):
            m.plate([(-L * .08, 0), (L * .06, 0), (-L * .01, sign * L * .22), (-L * .12, sign * L * .22)], -.015, .015, "cruise_wing", "titanium")
        m.cbox(-L * .12, 0, -R * 1.25, L * .22, R * .9, R * .7, "intake_fairing", "missile_body")
    for k in range(ducts):
        angle = k * math.tau / ducts + math.pi / 4
        yy, zz = R * 1.14 * math.cos(angle), R * 1.14 * math.sin(angle)
        m.cylinder(yy, zz, -L * .31, L * .15, R * .48, 12, "duct", "x", m="missile_body")
        m.cylinder(yy, zz, L * .15, L * .152, R * .35, 12, "duct_mouth", "x", m="rubber")
