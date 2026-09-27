"""Deck mounts for the gallery: a turret with a barrel, or a Gatling mount under its dome."""
import math
import re


def mount(m, kind, words):
    calibre = 0
    found = re.search(r"(\d+)\s*mm", words)
    if found:
        calibre = int(found.group(1))
    if "ciws" in words or "barrel" in words:
        gatling(m, big="eleven" in words)
    elif "twin" in words:
        twin_mount(m)
    elif calibre and calibre < 57:
        light_mount(m)
    else:
        turret(m, big=calibre >= 100)


def light_mount(m):
    m.cylinder(0, 0, -.4, .0, .9, 24, "base", m="naval_paint")
    m.cylinder(0, 0, .0, .9, .45, 16, "pedestal", m="naval_paint")
    m.prism(-1.1, .7, -.8, .8, .9, 2.1, .25, "shield", "naval_paint")
    m.cbox(-.9, 0, 2.3, .8, .9, .5, "sight", "array_face")
    m.cylinder(0, 1.55, .6, 3.4, .07, 10, "barrel", "x", m="titanium")


def turret(m, big=True):
    s = 1.0 if big else .72
    m.cylinder(0, 0, -.4, .0, 1.6 * s, 24, "base", m="naval_paint")
    m.prism(-2.0 * s, 1.5 * s, -1.5 * s, 1.5 * s, 0, 2.8 * s, .65 * s, "turret", "naval_paint")
    m.cylinder(0, 1.6 * s, 1.0 * s, 7.3 * s, .16 * s, 16, "barrel", "x", m="titanium")


def twin_mount(m):
    m.cylinder(0, 0, -.4, .0, 1.0, 24, "base", m="naval_paint")
    m.cylinder(0, 0, .0, 1.2, .55, 16, "pedestal", m="naval_paint")
    m.cbox(-.2, 0, 1.5, 1.6, 1.4, .8, "cradle", "naval_paint")
    m.prism(-.9, .1, -1.1, 1.1, .9, 2.3, .2, "shield", "naval_paint")
    for off in (-.4, .4):
        m.cylinder(off, 1.7, .1, 3.6, .07, 10, "barrel", "x", m="titanium")


def gatling(m, big=False):
    s = 1.25 if big else 1.0
    m.cylinder(0, 0, -1, 0, 1.0 * s, 24, "base", m="naval_paint")
    m.cbox(0, 0, .8 * s, 1.8 * s, 1.5 * s, 1.6 * s, "mount", "naval_paint")
    m.cylinder(-.35 * s, 0, 1.2 * s, 2.7 * s, .72 * s, 24, "radome", m="radome")
    cap = m.revolve([(0, .72 * s), (.25 * s, .69 * s), (.48 * s, .54 * s), (.65 * s, .30 * s), (.72 * s, .001)], 24, "radome", "radome")
    cap.rotate((0, 1, 0), -math.pi / 2)
    cap.translate((-.35 * s, 0, 2.7 * s))
    m.cbox(.1 * s, .93 * s, .65 * s, 1.4 * s, .55 * s, 1.35 * s, "feed_housing", "naval_paint")
    barrels = 11 if big else 6
    for i in range(barrels):
        a = i * math.tau / barrels
        m.cylinder(math.cos(a) * .13 * s, .45 * s + math.sin(a) * .13 * s, .5 * s, 2.35 * s, .043, 8, "barrel", "x", m="titanium")
