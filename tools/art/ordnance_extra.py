"""The two remaining gallery bodies: a stubby cone-nosed rocket and a blunt torpedo."""
import math

from ordnance_bodies import fin_set, ogive, zone_materials


def cone_body(m, L, R, heavy=False):
    """A plain cylinder with a conical nose and a flared skirt; the heavy one has a step."""
    profile = [(-L / 2, R * .9), (-L / 2 + L * .06, R), (L * .18, R)]
    if heavy:
        profile += [(L * .20, R * .8), (L * .34, R * .8)]
    profile += [(L * .50, R * .08)]
    body = m.revolve(profile, 24, "weapon_body", "missile_body")
    zone_materials(body, L)
    fin_set(m, -L * .34, L * .14, -L * .46, R * (1.6 if heavy else 2.2), 4)


def blunt_body(m, L, R, boosted=False):
    """Rounded nose, parallel body, cruciform tail fins and a bronze propeller."""
    ogive(m, L, R, blunt=True)
    for i in range(7):
        o = m.plate([(-L * .50, 0), (-L * .48, R * 1.5), (-L * .46, R * 1.7), (-L * .45, 0)], -.018, .018, "propeller", "bronze")
        o.rotate((1, 0, 0), math.tau * i / 7)
    fin_set(m, -L * .27, L * .11, -L * .36, R * 1.7, 4, .026, 0.0, "tail_fin")
    if boosted:
        m.cylinder(0, 0, -L * .50, -L * .28, R * 1.2, 24, "booster", "x", m="missile_body")
        fin_set(m, -L * .36, L * .12, -L * .46, R * 3.0, 4, .02, math.pi / 4, "booster_fin")
