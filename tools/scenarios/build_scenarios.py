"""Regenerate fictional missions using public platform identities and Natural Earth geography.

Every scenario is sited in real water. Positions come from latitude and longitude, coastlines are
Natural Earth outlines of the actual coasts, and the bases are the bases that are there. Ships carry
their real pennant numbers and squadrons their real designations, in the way any naval wargame
names its pieces.

What is invented is the war. There is no NATO-Russia conflict, no deployment resembling these,
and no operational plan behind any of it. Force compositions are plausible arrangements assembled
to make a specific tactical problem, not intelligence about anybody's actual dispositions, and
every performance number in the catalogue remains a game tuning value. See docs/REALISM.md.

    python3 tools/scenarios/build_scenarios.py  # build dependency: shapely==2.1.2
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geography as g
from operation_design import enhance

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "data", "scenarios")

DISCLAIMER = ("Real geography and real platform families; the conflict, the deployment and the "
              "tactical situation are fiction.")


class Scenario:
    def __init__(self, sid, name, lat0, lon0, extent, order, description,
                 sea_state=3, wind_kn=14, visibility_nm=10, start="2027-03-14T05:30:00",
                 player="BLUE", neutral_factions=None, seed=None, layer=(0, 0.0), cz_range_nm=0):
        self.d = {
            "id": sid, "name": name, "description": description + " " + DISCLAIMER,
            "start_time_utc": start, "player_faction": player,
            "map": {"center_nm": [0, 0], "extent_nm": extent,
                    "anchor_lat": lat0, "anchor_lon": lon0,
                    "anchor_note": ("World coordinates are nautical miles about this point; one "
                                    "minute of latitude is one mile and longitude is scaled by "
                                    "the cosine of the anchor latitude.")},
            "environment": {"sea_state": sea_state, "wind_kn": wind_kn,
                            "visibility_nm": visibility_nm,
                            "layer_depth_m": layer[0], "layer_strength": layer[1],
                            "cz_range_nm": cz_range_nm},
            "terrain": {"land": []}, "units": [], "order": order,
        }
        if neutral_factions:
            self.d["neutral_factions"] = neutral_factions
        if seed is not None:
            self.d["seed"] = seed
        self.lat0, self.lon0 = lat0, lon0
        self.extra_land = []
        self.height_m = None

    def meta(self, theatre, difficulty, duration, role, learning, intent, first_orders, setting_note=None, year=2027):
        """The commander-facing card: what the mission is for, how hard it is and what to do first."""
        self.d.update(theatre=theatre, year=year, difficulty=difficulty, duration_minutes=duration, role=role,
                      learning=learning, commander_intent=intent, first_orders=list(first_orders))
        if setting_note:
            self.d["setting_note"] = setting_note
        return self

    def site(self, platform, callsign, faction, lat, lon, **kw):
        """A fixed installation. It has to stand on charted land, or its radar horizon and the AI's
        idea of where it may be shot from are both wrong; the build fails loudly rather than
        shipping a battery in the water."""
        if not g.is_land(lat, lon):
            raise ValueError("%s: %s at %.3f, %.3f is not on charted land" % (self.d["id"], callsign, lat, lon))
        return self.unit(platform, callsign, faction, self.xy(lat, lon), 0, 0, **kw)

    def afloat(self, platform, callsign, faction, lat, lon, heading=0, speed=0.0, **kw):
        """A hull or boat; refuses a start position ashore."""
        if g.is_land(lat, lon):
            raise ValueError("%s: %s at %.3f, %.3f is ashore" % (self.d["id"], callsign, lat, lon))
        return self.unit(platform, callsign, faction, self.xy(lat, lon), heading, speed, **kw)

    def land(self, *keys):
        # Coast coverage is derived from the complete chart, not a whitelist of islands.
        pass
        return self

    def xy(self, lat, lon):
        return g.pos(lat, lon, self.lat0, self.lon0)

    def near(self, place, bearing=None, nm=0.0):
        return g.at(place, self.lat0, self.lon0, bearing, nm)

    def unit(self, platform, callsign, faction, at, heading=0, speed=0.0, **kw):
        u = {"platform": platform, "callsign": callsign, "faction": faction,
             "position_nm": at, "heading_deg": heading, "speed_kn": speed}
        if "patrol" in kw:
            u["patrol_nm"] = kw.pop("patrol")
        u.update(kw)
        self.d["units"].append(u)
        return self

    def objectives(self, text, victory, loss):
        self.d["objectives"] = {"text": text, "victory": victory, "loss": loss}
        return self

    def forces(self, text):
        self.d["forces"] = text
        return self

    def _frame(self):
        """Centre the chart on the action and widen it until everything placed is on it.

        Real geography puts a coastline where the coastline is, which is often a long way from
        where the ships are. A landmass that cannot be seen from anywhere on the chart is dead
        weight in the file and in the terrain raster, so it is dropped here rather than shipped.
        """
        xs, ys = [], []
        for u in self.d["units"]:
            xs.append(u["position_nm"][0])
            ys.append(u["position_nm"][1])
            for leg in u.get("patrol_nm", []):
                xs.append(leg[0])
                ys.append(leg[1])
        cx = round((min(xs) + max(xs)) / 2.0, 1)
        cy = round((min(ys) + max(ys)) / 2.0, 1)
        span = max(max(xs) - min(xs), max(ys) - min(ys))
        extent = max(self.d["map"]["extent_nm"], int(span * 1.35) + 20)
        self.d["map"]["center_nm"] = [cx, cy]
        self.d["map"]["extent_nm"] = extent
        half = extent / 2.0
        view = (cx - half, cy - half, cx + half, cy + half)
        kept, dropped = [], []
        for land in self.d["terrain"]["land"]:
            px = [p[0] for p in land["points_nm"]]
            py = [p[1] for p in land["points_nm"]]
            if min(px) > view[2] or max(px) < view[0] or min(py) > view[3] or max(py) < view[1]:
                dropped.append(land["name"])
            else:
                kept.append(land)
        self.d["terrain"]["land"] = kept
        return dropped

    def write(self):
        dropped = self._frame()
        land, labels = g.chart(self.lat0, self.lon0, self.d["map"]["center_nm"], self.d["map"]["extent_nm"], self.height_m)
        land.extend(self.extra_land)
        self.d["terrain"] = {"land": land, "source": "Natural Earth 1:10m land 5.1.1; public domain", "generalization_nm": 0.2}
        if self.extra_land:
            self.d["terrain"]["source"] += "; reclaimed outposts added from public imagery, approximate"
        self.d["map"]["labels"] = labels
        self.d["map"]["chart_region"] = g.region_of(self.lat0, self.lon0)
        # Where the coastline polygons stop. Beyond it the renderer falls back to the coarser
        # bathymetry raster's own coast, dimmed, rather than showing a straight clip line.
        self.d["map"]["charted_nm"] = g.charted_box(self.d["map"]["center_nm"], self.d["map"]["extent_nm"])
        self.d["map"]["chart_note"] = "Natural Earth 1:10m land and bathymetry · local projection · not for navigation"
        self.d["map"]["projection"] = "local_equirectangular"
        self.d.setdefault("force_note", "Fictional 2027 deployment; established platform fits. Reduced air detachments; no claim of actual readiness or deployment.")
        # Start on the fleet, with a separate theatre overview for distant land-based aviation.
        afloat = [u["position_nm"] for u in self.d["units"] if u["faction"] == self.d["player_faction"] and not any(word in u["platform"] for word in ("shore", "fighter", "mpa", "uav", "strike", "helo"))]
        if afloat and self.d["map"]["extent_nm"] > 600:
            lo = [min(p[i] for p in afloat) for i in (0,1)]
            hi = [max(p[i] for p in afloat) for i in (0,1)]
            self.d["map"]["focus_center_nm"] = [(lo[i]+hi[i])/2 for i in (0,1)]
            self.d["map"]["focus_extent_nm"] = max(280, max(hi[i]-lo[i] for i in (0,1))*1.8)
        # Detached aircraft identities are scenario callsigns, not invented squadron assignments.
        for u in self.d["units"]:
            for wing in u.get("air_wing", []):
                if wing["platform"].startswith("rfn_"):
                    wing["squadron"] = "Scenario air detachment"

        g.validate_scenario(self.d, platform_domain)
        enhance(self.d)
        path = os.path.join(OUT, self.d["id"] + ".json")
        with open(path, "w") as f:
            json.dump(self.d, f, indent=2)
            f.write("\n")
        wing = sum(sum(e["count"] for e in u["air_wing"])
                   for u in self.d["units"] if u.get("air_wing"))
        print("%-32s %3d listed + %3d authored aircraft | %d coast | extent %4d nm | centre %s%s"
              % (self.d["id"], len(self.d["units"]), wing, len(self.d["terrain"]["land"]),
                 self.d["map"]["extent_nm"], self.d["map"]["center_nm"],
                 ("  dropped off-chart: " + ", ".join(dropped)) if dropped else ""))


_DOMAINS = {}


def platform_domain(platform_id):
    """Domain of a catalogue platform, read once from its resource file."""
    if not _DOMAINS:
        import re
        for sub in os.listdir(os.path.join(ROOT, "data", "platforms")):
            folder = os.path.join(ROOT, "data", "platforms", sub)
            if not os.path.isdir(folder):
                continue
            for name in os.listdir(folder):
                if name.endswith(".tres"):
                    text = open(os.path.join(folder, name)).read()
                    m = re.search(r'^domain = "(\w+)"', text, re.M)
                    _DOMAINS[name[:-5]] = m.group(1) if m else "surface"
    return _DOMAINS.get(platform_id, "surface")


def lost(faction, text):
    return [{"id": "lose_" + faction.lower(), "type": "force_destroyed",
             "faction": faction, "text": text}]


def targets(names, text):
    return {"id":"targets", "type":"all_units_lost", "callsigns":names, "text":text}

def protected(names):
    return {"id":"protected", "type":"unit_lost", "callsigns":names, "text":"Protected vessel lost"}

def hold(hours):
    return {"id":"hold_watch", "type":"time_elapsed", "seconds":hours*3600, "text":f"Complete the {hours}-hour watch"}

def arrival(oid, names, center, radius, text):
    return {"id":oid, "type":"reach_area", "callsigns":names, "center_nm":center, "radius_nm":radius, "text":text}


# --- Carrier air wings ------------------------------------------------------------------------
# Real squadron designations and radio callsigns, at a strength sized for one scenario rather
# than a whole deployed air wing.

def cvw3(fighters=6, growlers=2, hawkeyes=2, tankers=2, asw=3, suw=1):
    return [
        {"platform": "usn_fighter_fa18e", "count": fighters, "squadron": "VFA-83", "callsign": "Rampager", "first_modex": 301},
        {"platform": "usn_fighter_fa18f", "count": 2, "squadron": "VFA-32", "callsign": "Gypsy", "first_modex": 101},
        {"platform": "usn_ea_ea18g", "count": growlers, "squadron": "VAQ-130", "callsign": "Zapper", "first_modex": 501},
        {"platform": "usn_aew_e2d", "count": hawkeyes, "squadron": "VAW-123", "callsign": "Screwtop", "first_modex": 601},
        {"platform": "usn_helo_mh60r", "count": asw, "squadron": "HSM-74", "callsign": "Swamp Fox", "first_modex": 701},
        {"platform": "usn_helo_mh60s", "count": suw, "squadron": "HSC-7", "callsign": "Dusty Dog", "first_modex": 611},
    ]


def red_air_regiment(bombers=0, foxhounds=0, flankers=0, mpa=0, orion=0, orlan=0, helix=0,
                     isr_patrol=None, strike_patrol=None):
    """A field's regiment. `isr_patrol` is the barrier the surveillance aircraft fly.

    Search aircraft are given a route rather than left to work one out. A patrol line towards the
    threat axis is how wide-area surveillance is actually flown, and on a chart this size an
    aircraft searching outward from its own airfield would spend the scenario getting there.
    """
    out = []
    if bombers:
        out.append({"platform": "rfn_bomber_tu22m3", "count": bombers, "squadron": "40 SAP", "callsign": "Backfire", "first_modex": 21})
    if foxhounds:
        out.append({"platform": "rfn_strike_mig31k", "count": foxhounds, "squadron": "174 IAP", "callsign": "Foxhound", "first_modex": 31})
    if flankers:
        out.append({"platform": "rfn_fighter_su35s", "count": flankers, "squadron": "159 IAP", "callsign": "Flanker", "first_modex": 41})
    if mpa:
        out.append({"platform": "rfn_mpa_il38n", "count": mpa, "squadron": "403 OPLAP", "callsign": "May", "first_modex": 51})
    if orion:
        out.append({"platform": "rfn_uav_orion", "count": orion, "squadron": "UAV det", "callsign": "Orion", "first_modex": 61})
    if orlan:
        out.append({"platform": "rfn_uav_orlan10", "count": orlan, "squadron": "UAV det", "callsign": "Orlan", "first_modex": 71})
    if isr_patrol:
        for entry in out:
            if entry["platform"] in ("rfn_mpa_il38n", "rfn_uav_orion", "rfn_uav_orlan10"):
                entry["patrol_nm"] = isr_patrol
    if strike_patrol:
        # A bomber regiment flies the raid on cueing and searches with its own radar. Leaving it
        # on the ground until somebody hands it a firing solution means it never leaves at all,
        # because the first thing the other side does is shoot down whoever was going to hand it
        # one. The route is the raid.
        for entry in out:
            if entry["platform"] in ("rfn_bomber_tu22m3", "rfn_strike_mig31k"):
                entry["patrol_nm"] = strike_patrol
    if helix:
        out.append({"platform": "rfn_helo_ka27", "count": helix, "squadron": "830 OKPLVP", "callsign": "Helix", "first_modex": 81})
    return out


# ==============================================================================================
# The scenarios
# ==============================================================================================

def bmd_picket():
    s = Scenario("aegis_bastion", "NORTH CAPE — BALLISTIC MISSILE DEFENCE", 71.0, 26.0, 340, 7,
                 sea_state=3, wind_kn=15, visibility_nm=9, start="2027-03-19T11:05:00",
                 neutral_factions=["NEUTRAL"],
                 description=('A fictional mixed missile raid threatens the carrier and replenishment ship north of the North Cape. A Flight III destroyer and a legacy BMD cruiser provide the principal defensive layers. Preserve the protected ships for four hours. Interception and flight profiles are game abstractions; interceptor suitability still matters.'))
    s.meta("Barents Sea", "Advanced", 30, "Air and missile defence commander",
           "Layered defence of a carrier and an auxiliary against ballistic and cruise missiles, interceptor suitability and finite magazines",
           "Keep Eisenhower and Maud alive through four hours. Match the interceptor to the round; SM-3 for ballistic, SM-2 for the rest.",
           ["Jack H. Lucas and Gettysburg are the ballistic-missile defence layer. Station them between the group and the Kola.",
            "Launch the Hawkeyes early so the Kinzhal carriers are seen before they release.",
            "The Kilo is inside the screen. The Seahawks hunt her while the Aegis ships look up."])
    s.land("kola_peninsula", "northern_norway")
    s.unit("usn_ddg_burke_iii", "USS Jack H. Lucas (DDG 125)", "BLUE", s.xy(71.3, 29.0), 90, 16,
           patrol=[s.xy(71.0, 30.5), s.xy(71.6, 27.5)])
    s.unit("usn_cg_ticonderoga", "USS Gettysburg (CG 64)", "BLUE", s.xy(71.5, 28.2), 90, 16,
           patrol=[s.xy(71.2, 29.8), s.xy(71.8, 26.8)])
    s.unit("usn_cvn_nimitz", "USS Dwight D. Eisenhower (CVN 69)", "BLUE", s.xy(71.6, 24.2), 60, 18,
           air_wing=cvw3(fighters=4, growlers=1, hawkeyes=2, tankers=2, asw=2, suw=1))
    s.unit("usn_ddg_arleigh_burke_iia", "USS Truxtun (DDG 103)", "BLUE", s.xy(71.4, 24.8), 60, 18)
    s.unit("rnon_ffg_fridtjof_nansen", "HNoMS Fridtjof Nansen (F 310)", "BLUE", s.xy(71.7, 23.6), 60, 18)
    s.unit("rnon_aux_maud", "HNoMS Maud (A 530)", "BLUE", s.xy(71.5, 22.8), 60, 16)
    s.unit("usn_ssn_virginia", "USS North Dakota (SSN 784)", "BLUE", s.xy(71.9, 27.6), 110, 9,
           depth_m=140, radar_on=False)
    s.unit("rfn_ffg_admiral_gorshkov", "Admiral Kasatonov (461)", "RED", s.xy(70.6, 33.0), 290, 17,
           patrol=[s.xy(71.2, 29.6), s.xy(70.3, 34.0)])
    s.unit("rfn_fsg_steregushchiy", "Soobrazitelny (531)", "RED", s.xy(70.4, 33.8), 290, 17,
           patrol=[s.xy(71.0, 30.4), s.xy(70.1, 34.6)])
    s.unit("rfn_ssk_kilo_877", "Kaluga (B-800)", "RED", s.xy(71.4, 31.4), 260, 5,
           depth_m=120, radar_on=False, patrol=[s.xy(71.3, 28.6), s.xy(71.5, 32.4)])
    s.unit("shore_air_station", "Monchegorsk Air Base", "RED", s.near("monchegorsk"), 0, 0,
           air_wing=red_air_regiment(foxhounds=3, flankers=4, orlan=1,
                                     isr_patrol=[s.xy(71.4, 30.5), s.xy(71.6, 25.0),
                                                 s.xy(70.8, 28.0)],
                                     strike_patrol=[s.xy(71.5, 29.0), s.xy(71.7, 24.5)]))
    s.unit("civ_merchant_bulk", "MV Northern Trader", "NEUTRAL", s.xy(71.1, 25.6), 95, 13,
           patrol=[s.xy(71.6, 21.0), s.xy(71.8, 30.0)])
    s.objectives("Keep the carrier and Maud alive through a four-hour air-defence watch. Protect neutral shipping.",
        [hold(4)],
        [protected(["USS Dwight D. Eisenhower (CVN 69)", "HNoMS Maud (A 530)", "MV Northern Trader"])])
    s.forces("NATO: 1 carrier (CVW-3 det), 1 BMD cruiser, 2 destroyers, 1 frigate, 1 replenishment ship, 1 submarine  ·  Russia: 1 frigate, 1 corvette, 1 submarine, Monchegorsk fighter regiment")
    return s


def carrier_qualification():
    s = Scenario("carrier_qualification", "CARRIER QUALIFICATION / AIR OPERATIONS", 67.2, 12.4, 150, 11,
                 sea_state=2, wind_kn=8, visibility_nm=16, start="2027-03-14T09:00:00",
                 description=("A fictional allied aviation exercise off Bodo with no opposing force. "
                              "Open AIR F3, choose a carrier or airfield, select an aircraft type and launch count, "
                              "then Execute & Resume. Once airborne, reopen Air Operations, choose an airframe "
                              "and LAND AT destination, and issue RETURN & LAND. Recover one aircraft aboard ship "
                              "and one at Bodo. CATOBAR, STOVL, helicopter and runway aircraft have different basing limits. "
                              "Advance time after issuing orders; landing is followed by a refuel/rearm cycle."))
    s.meta("Norwegian Sea", "Introductory", 15, "Air operations officer",
           "Launching, routing and recovering aircraft to carriers and an airfield; deck cycles and turnaround",
           "Recover one aircraft aboard a ship and one at Bodo. Nothing will shoot at you; the deck cycle is the exercise.",
           ["Open Air Operations (F3), pick Charles de Gaulle, a Rafale and a launch count, then Execute & Resume.",
            "Once airborne, reopen Air Operations, select the airframe and a landing destination, then Return & Land.",
            "Advance time. A recovered aircraft refuels and rearms before it can fly again."])
    s.unit("fra_cvn_charles_de_gaulle", "Charles de Gaulle (R 91)", "BLUE", s.xy(67.30, 12.20), 0, 0,
           air_wing=[{"platform": "fra_fighter_rafale_m", "count": 4, "callsign": "Marine", "first_modex": 11},
                     {"platform": "fra_aew_e2c", "count": 1, "callsign": "Hawkeye", "first_modex": 21},
                     {"platform": "nato_helo_nh90_nfh", "count": 1, "callsign": "Caiman", "first_modex": 31},
                     {"platform": "fra_helo_panther", "count": 1, "callsign": "Panther", "first_modex": 41}])
    s.unit("usn_lha_america", "USS America (LHA 6)", "BLUE", s.xy(67.20, 12.05), 0, 0,
           air_wing=[{"platform": "rn_fighter_f35b", "count": 3, "callsign": "Lightning", "first_modex": 51},
                     {"platform": "usn_helo_mh60r", "count": 2, "callsign": "Seahawk", "first_modex": 61}])
    s.unit("ita_ddg_horizon", "Andrea Doria (D 553)", "BLUE", s.xy(67.35, 12.0), 0, 0)
    # The generalized coastline excludes the real airport's coastal apron. This fictional
    # exercise uses an explicitly schematic marker two miles inland, not a runway survey.
    s.unit("shore_air_station", "Bodo training airfield", "BLUE", s.xy(67.28585, 14.44120), 260, 0,
           position_note="Schematic exercise field marker 2 nm inland of Bodo airport on the generalized chart.",
           air_wing=[{"platform": "usaf_fighter_f16c", "count": 3, "callsign": "Viper", "first_modex": 71},
                     {"platform": "raf_fighter_typhoon", "count": 2, "callsign": "Typhoon", "first_modex": 81},
                     {"platform": "usn_mpa_p8a", "count": 1, "callsign": "Poseidon", "first_modex": 91}])
    s.objectives("Complete a carrier landing and an airfield landing. Use AIR F3 to select aircraft and destinations.",
                 [{"id": "deck_recovery", "type": "aircraft_recovered", "faction": "BLUE", "facility": "deck", "count": 1,
                   "text": "Launch and recover one aircraft aboard ship"},
                  {"id": "field_recovery", "type": "aircraft_recovered", "faction": "BLUE", "facility": "airfield", "count": 1,
                   "text": "Launch and land one aircraft at a friendly airfield"}],
                 [protected(["Charles de Gaulle (R 91)", "USS America (LHA 6)"])])
    s.forces("Allied exercise: CATOBAR carrier, STOVL assault ship, Horizon destroyer and friendly runway; mixed fighter, AEW, ASW and patrol detachments. No opposing force.")
    return s


if __name__ == "__main__":
    # M35 kept one 2027 North Atlantic operation and the carrier-aviation exercise; the cut
    # missions remain in git history.
    for build in (bmd_picket, carrier_qualification):
        build().write()
