"""Regenerate data/scenarios from real geography and real orders of battle.

Every scenario is sited in real water. Positions come from latitude and longitude, coastlines are
coarse outlines of the actual coasts, and the bases are the bases that are there. Ships carry
their real pennant numbers and squadrons their real designations, in the way any naval wargame
names its pieces.

What is invented is the war. There is no NATO-Russia conflict, no deployment resembling these,
and no operational plan behind any of it. Force compositions are plausible arrangements assembled
to make a specific tactical problem, not intelligence about anybody's actual dispositions, and
every performance number in the catalogue remains a game tuning value. See docs/REALISM.md.

    python3 tools/scenarios/build_scenarios.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geography as g

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "data", "scenarios")

DISCLAIMER = ("Real geography and real platform families; the conflict, the deployment and the "
              "tactical situation are fiction.")


class Scenario:
    def __init__(self, sid, name, lat0, lon0, extent, order, description,
                 sea_state=3, wind_kn=14, visibility_nm=10, start="2027-03-14T05:30:00",
                 player="BLUE", neutral_factions=None, seed=None):
        self.d = {
            "id": sid, "name": name, "description": description + " " + DISCLAIMER,
            "start_time_utc": start, "player_faction": player,
            "map": {"center_nm": [0, 0], "extent_nm": extent,
                    "anchor_lat": lat0, "anchor_lon": lon0,
                    "anchor_note": ("World coordinates are nautical miles about this point; one "
                                    "minute of latitude is one mile and longitude is scaled by "
                                    "the cosine of the anchor latitude.")},
            "environment": {"sea_state": sea_state, "wind_kn": wind_kn,
                            "visibility_nm": visibility_nm},
            "terrain": {"land": []}, "units": [], "order": order,
        }
        if neutral_factions:
            self.d["neutral_factions"] = neutral_factions
        if seed is not None:
            self.d["seed"] = seed
        self.lat0, self.lon0 = lat0, lon0

    def land(self, *keys):
        for k in keys:
            self.d["terrain"]["land"].append(g.landmass(k, self.lat0, self.lon0))
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


def destroy(faction, text):
    return [{"id": "kill_" + faction.lower(), "type": "force_destroyed",
             "faction": faction, "text": text}]


def lost(faction, text):
    return [{"id": "lose_" + faction.lower(), "type": "force_destroyed",
             "faction": faction, "text": text}]


# --- Carrier air wings ------------------------------------------------------------------------
# Real squadron designations and radio callsigns, at a strength sized for one scenario rather
# than a whole deployed air wing.

def cvw8(fighters=6, f35=4, growlers=2, hawkeyes=2, tankers=2, asw=3, suw=1):
    return [
        {"platform": "usn_fighter_fa18e", "count": fighters, "squadron": "VFA-87", "callsign": "Warparty", "first_modex": 301},
        {"platform": "usn_fighter_fa18f", "count": 2, "squadron": "VFA-11", "callsign": "Ripper", "first_modex": 101},
        {"platform": "usn_fighter_f35c", "count": f35, "squadron": "VFA-34", "callsign": "Joker", "first_modex": 201},
        {"platform": "usn_ea_ea18g", "count": growlers, "squadron": "VAQ-142", "callsign": "Gray Wolf", "first_modex": 501},
        {"platform": "usn_aew_e2d", "count": hawkeyes, "squadron": "VAW-124", "callsign": "Bear Ace", "first_modex": 601},
        {"platform": "usn_uav_mq25", "count": tankers, "squadron": "VUQ-10", "callsign": "Fire Hawk", "first_modex": 701},
        {"platform": "usn_helo_mh60r", "count": asw, "squadron": "HSM-70", "callsign": "Spartan", "first_modex": 701},
        {"platform": "usn_helo_mh60s", "count": suw, "squadron": "HSC-9", "callsign": "Trident", "first_modex": 611},
    ]


def cvw3(fighters=6, growlers=2, hawkeyes=2, tankers=2, asw=3, suw=1):
    return [
        {"platform": "usn_fighter_fa18e", "count": fighters, "squadron": "VFA-83", "callsign": "Rampager", "first_modex": 301},
        {"platform": "usn_fighter_fa18f", "count": 2, "squadron": "VFA-32", "callsign": "Gypsy", "first_modex": 101},
        {"platform": "usn_ea_ea18g", "count": growlers, "squadron": "VAQ-130", "callsign": "Zapper", "first_modex": 501},
        {"platform": "usn_aew_e2d", "count": hawkeyes, "squadron": "VAW-123", "callsign": "Screwtop", "first_modex": 601},
        {"platform": "usn_uav_mq25", "count": tankers, "squadron": "VUQ-10", "callsign": "Fire Hawk", "first_modex": 701},
        {"platform": "usn_helo_mh60r", "count": asw, "squadron": "HSM-74", "callsign": "Swamp Fox", "first_modex": 701},
        {"platform": "usn_helo_mh60s", "count": suw, "squadron": "HSC-7", "callsign": "Dusty Dog", "first_modex": 611},
    ]


def cvf(f35=6, merlin=3, crowsnest=2, wildcat=1):
    return [
        {"platform": "rn_fighter_f35b", "count": f35, "squadron": "617 Sqn", "callsign": "Dambuster", "first_modex": 11},
        {"platform": "rn_helo_merlin_hm2", "count": merlin, "squadron": "820 NAS", "callsign": "Merlin", "first_modex": 11},
        {"platform": "rn_aew_crowsnest", "count": crowsnest, "squadron": "820 NAS", "callsign": "Crowsnest", "first_modex": 21},
        {"platform": "rn_helo_wildcat", "count": wildcat, "squadron": "815 NAS", "callsign": "Wildcat", "first_modex": 31},
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

def iceland_faroe_gap():
    s = Scenario("giuk_passage", "ICELAND-FAROE GAP", 63.4, -15.0, 340, 3, sea_state=4, wind_kn=22,
                 visibility_nm=6, start="2027-03-02T02:10:00",
                 description=(
                   "The Iceland-Faroe Ridge: 270 miles of shallow water between two coastlines, and "
                   "the eastern half of the gap every Northern Fleet boat bound for the Atlantic has "
                   "to cross. A Kilo is somewhere in it, running slow and deep on batteries. You have "
                   "a Virginia holding the northern approach, a barrier force on the surface, and a "
                   "Poseidon out of Keflavik with sixty buoys. Find it before it is through."))
    s.land("iceland", "faroes")
    s.unit("usn_ssn_virginia", "USS Delaware (SSN 791)", "BLUE", s.xy(63.9, -16.4), 110, 8,
           depth_m=120, radar_on=False)
    s.unit("usn_ddg_arleigh_burke_iia", "USS Jason Dunham (DDG 109)", "BLUE", s.xy(63.3, -14.6), 75, 14,
           patrol=[s.xy(63.2, -17.6), s.xy(63.4, -12.0)])
    s.unit("rnon_ffg_fridtjof_nansen", "HNoMS Roald Amundsen (F 311)", "BLUE", s.xy(62.9, -13.2), 285, 14,
           radar_on=False, patrol=[s.xy(62.8, -11.4), s.xy(63.0, -16.6)])
    s.unit("shore_air_station", "Keflavik Air Base", "BLUE", s.near("keflavik"), 0, 0,
           air_wing=[{"platform": "usn_mpa_p8a", "count": 2, "squadron": "VP-8", "callsign": "Fighting Tiger", "first_modex": 21},
                     {"platform": "usn_uav_mq4c", "count": 1, "squadron": "VUP-19", "callsign": "Triton", "first_modex": 51}])
    s.unit("rfn_ssk_kilo", "Vladikavkaz (B-459)", "RED", s.xy(64.3, -13.6), 200, 5,
           depth_m=110, radar_on=False, ai_posture="breakout",
           patrol=[s.xy(63.5, -14.4), s.xy(62.3, -15.6), s.xy(61.4, -16.8)])
    s.objectives("Hold the ridge. The boat does not have to be sunk if it cannot get past you.",
                 destroy("RED", "Destroy the transiting submarine"),
                 lost("BLUE", "Barrier force destroyed"))
    s.forces("NATO: 1 attack submarine, 1 destroyer, 1 frigate, Keflavik patrol det  ·  Russia: 1 diesel submarine")
    return s


def norwegian_sea_shadow():
    s = Scenario("north_atlantic_shadow_line", "NORWEGIAN SEA — SHADOW LINE", 68.0, 8.0, 260, 1,
                 sea_state=4, wind_kn=20, start="2027-03-14T05:30:00",
                 description=(
                   "Open water 200 miles west of the Lofoten wall. A Russian surface group is running "
                   "south-west for the Atlantic and a NATO surface action group is somewhere ahead of "
                   "it. Nobody has a firm position on anybody. Both frigates carry a helicopter, and "
                   "in this much sea room the aircraft is how either side finds the other first."))
    s.land("northern_norway")
    s.unit("usn_ddg_arleigh_burke_iia", "USS Truxtun (DDG 103)", "BLUE", s.xy(67.4, 6.9), 45, 16)
    s.unit("rnon_ffg_fridtjof_nansen", "HNoMS Roald Amundsen (F 311)", "BLUE", s.xy(67.6, 7.6), 45, 16,
           radar_on=False)
    s.unit("rfn_ffg_admiral_gorshkov", "Admiral Gorshkov (454)", "RED", s.xy(68.7, 9.6), 225, 15,
           patrol=[s.xy(67.2, 6.0), s.xy(69.0, 10.5)])
    s.unit("rfn_fsg_steregushchiy", "Stoikiy (545)", "RED", s.xy(68.5, 10.4), 225, 15,
           patrol=[s.xy(67.0, 7.0), s.xy(69.2, 11.5)])
    s.objectives("Find the Russian group and destroy it without losing your own ships.",
                 destroy("RED", "Destroy the Russian surface group"),
                 lost("BLUE", "NATO surface action group destroyed"))
    s.forces("NATO: 1 destroyer, 1 frigate (2 embarked helicopters)  ·  Russia: 1 frigate, 1 corvette (1 embarked helicopter)")
    return s


def faroe_shetland_gate():
    s = Scenario("atlantic_gate", "FAROE-SHETLAND CHANNEL", 61.0, -3.5, 260, 4, sea_state=5,
                 wind_kn=28, visibility_nm=5, start="2027-03-05T21:40:00",
                 description=(
                   "The channel between the Faroes and Shetland is 150 miles wide and the deep water "
                   "in it is narrower than that. A Northern Fleet surface action group led by a Slava "
                   "is running for it at speed, shooting as it goes, and it is not turning back. The "
                   "gate is yours to hold with three escorts and whatever Lossiemouth can put up."))
    s.land("faroes", "shetland", "orkney", "north_scotland", "hebrides")
    s.unit("usn_ddg_arleigh_burke_iia", "USS Forrest Sherman (DDG 98)", "BLUE", s.xy(60.8, -3.9), 340, 18)
    s.unit("rnon_ffg_fridtjof_nansen", "HNoMS Thor Heyerdahl (F 314)", "BLUE", s.xy(60.6, -2.9), 340, 18,
           radar_on=False)
    s.unit("dnk_ffg_iver_huitfeldt", "HDMS Niels Juel (F 363)", "BLUE", s.xy(60.5, -4.8), 20, 18)
    s.unit("shore_air_station", "RAF Lossiemouth", "BLUE", s.near("lossiemouth"), 0, 0,
           air_wing=[{"platform": "usn_mpa_p8a", "count": 2, "squadron": "120 Sqn", "callsign": "Poseidon", "first_modex": 1}])
    s.unit("rfn_cg_slava", "Marshal Ustinov (055)", "RED", s.xy(62.4, -4.6), 195, 22,
           ai_posture="breakout", patrol=[s.xy(60.9, -4.2), s.xy(59.4, -5.6)])
    s.unit("rfn_ffg_admiral_gorshkov", "Admiral Kasatonov (461)", "RED", s.xy(62.6, -3.6), 195, 22,
           ai_posture="breakout", patrol=[s.xy(61.1, -3.4), s.xy(59.6, -4.8)])
    s.unit("rfn_ddg_udaloy", "Vice-Admiral Kulakov (626)", "RED", s.xy(62.2, -5.5), 195, 22,
           ai_posture="breakout", patrol=[s.xy(60.7, -5.0), s.xy(59.2, -6.4)])
    s.objectives("Stop the breakout. Ships that get past the channel are into open ocean.",
                 destroy("RED", "Destroy the Russian surface action group"),
                 lost("BLUE", "Channel force destroyed"))
    s.forces("NATO: 1 destroyer, 2 frigates, Lossiemouth patrol det  ·  Russia: 1 cruiser, 1 frigate, 1 destroyer")
    return s


def baltic():
    s = Scenario("baltic_sentinel", "GOTLAND BASIN", 56.8, 18.5, 220, 2, sea_state=2, wind_kn=10,
                 visibility_nm=12, start="2027-02-18T14:20:00", neutral_factions=["WHITE"],
                 description=(
                   "The Baltic is small, shallow, crowded and watched from every shore. Two NATO "
                   "escorts are covering the shipping lane east of Gotland while Baltic Fleet units "
                   "work the same water. Merchant traffic is dense, the land is close enough to hide "
                   "behind, and everything anybody does is inside somebody's missile envelope."))
    s.land("gotland", "oland", "bornholm", "south_sweden", "baltic_east_shore",
           "baltic_south_shore", "estonian_isles")
    s.unit("dnk_ffg_iver_huitfeldt", "HDMS Peter Willemoes (F 362)", "BLUE", s.xy(57.0, 19.4), 160, 14,
           patrol=[s.xy(56.2, 19.8), s.xy(57.6, 19.2)])
    s.unit("deu_fsg_braunschweig", "FGS Magdeburg (F 261)", "BLUE", s.xy(56.4, 18.9), 20, 14,
           patrol=[s.xy(55.8, 18.4), s.xy(57.2, 19.6)])
    s.unit("rfn_fsg_steregushchiy", "Soobrazitelny (531)", "RED", s.xy(55.9, 20.2), 340, 16,
           patrol=[s.xy(56.9, 20.4), s.xy(55.4, 19.4)])
    s.unit("rfn_fsg_buyan_m", "Zelyony Dol (602)", "RED", s.xy(55.4, 20.0), 340, 14,
           patrol=[s.xy(56.4, 20.6), s.xy(55.0, 19.8)])
    s.unit("civ_merchant_bulk", "MV Baltic Trader", "WHITE", s.xy(56.6, 19.0), 200, 12,
           patrol=[s.xy(55.2, 18.0), s.xy(57.8, 20.0)])
    s.unit("civ_merchant_bulk", "MV Gotland Star", "WHITE", s.xy(57.2, 18.9), 170, 13,
           patrol=[s.xy(55.4, 19.2), s.xy(58.2, 19.4)])
    s.unit("civ_fishing_trawler", "FV Stormfagel", "WHITE", s.xy(56.9, 18.7), 90, 6,
           patrol=[s.xy(56.5, 19.6), s.xy(57.2, 17.6)])
    s.objectives("Keep the lane open. Merchant traffic is protected and the shore is watching.",
                 destroy("RED", "Destroy the Russian units in the basin"),
                 lost("BLUE", "NATO escort group destroyed"))
    s.forces("NATO: 1 frigate, 1 corvette (drone det)  ·  Russia: 1 corvette, 1 missile ship  ·  Neutral: dense merchant traffic")
    return s


def vestfjorden_asw():
    s = Scenario("northern_sentry", "VESTFJORDEN APPROACHES", 68.8, 13.5, 220, 5, sea_state=3,
                 wind_kn=16, visibility_nm=8, start="2027-03-09T08:00:00",
                 description=(
                   "A Kilo is working the water outside Vestfjorden, inside the Lofoten wall's radar "
                   "shadow and a long way from any deep basin it could hide in. Andoya has a Poseidon "
                   "and a Triton. Your two escorts have three helicopters between them. Russian "
                   "fighters are already airborne out of the Kola and will be overhead before you "
                   "finish the search."))
    s.land("northern_norway")
    s.unit("usn_ddg_arleigh_burke_iia", "USS Bulkeley (DDG 84)", "BLUE", s.xy(68.4, 12.6), 30, 14,
           patrol=[s.xy(68.2, 11.9), s.xy(69.1, 14.2)])
    s.unit("rnon_ffg_fridtjof_nansen", "HNoMS Fridtjof Nansen (F 310)", "BLUE", s.xy(68.6, 13.4), 210, 14,
           radar_on=False, patrol=[s.xy(69.0, 14.6), s.xy(68.0, 12.2)])
    s.unit("shore_air_station", "Andoya Air Station", "BLUE", s.near("andoya"), 0, 0,
           air_wing=[{"platform": "usn_mpa_p8a", "count": 2, "squadron": "333 Skv", "callsign": "Pelican", "first_modex": 21},
                     {"platform": "usn_uav_mq4c", "count": 1, "squadron": "333 Skv", "callsign": "Triton", "first_modex": 51},
                     {"platform": "nato_helo_nh90_nfh", "count": 1, "squadron": "337 Skv", "callsign": "Bardu", "first_modex": 41}])
    s.unit("rfn_ssk_kilo", "Magnitogorsk (B-471)", "RED", s.xy(69.2, 12.0), 200, 4,
           depth_m=140, radar_on=False,
           patrol=[s.xy(68.5, 11.4), s.xy(68.1, 13.2), s.xy(69.0, 13.8)])
    s.unit("rfn_strike_su30sm", "Flogger 11", "RED", s.xy(69.6, 17.0), 250, 420,
           patrol=[s.xy(68.9, 13.0), s.xy(69.8, 16.4)])
    s.unit("rfn_strike_su30sm", "Flogger 12", "RED", s.xy(69.7, 17.3), 250, 420,
           patrol=[s.xy(68.6, 12.4), s.xy(69.9, 16.8)])
    s.unit("rfn_uav_orlan10", "Orlan 71", "RED", s.xy(69.4, 15.6), 230, 60,
           patrol=[s.xy(68.7, 13.4), s.xy(69.5, 15.9)])
    s.objectives("Find and kill the submarine. The aircraft overhead are a problem to be managed, not the mission.",
                 destroy("RED", "Destroy the Russian submarine and the aircraft over the fjord"),
                 lost("BLUE", "Escort group destroyed"))
    s.forces("NATO: 1 destroyer, 1 frigate, Andoya patrol det  ·  Russia: 1 diesel submarine, 2 strike aircraft, 1 UAV")
    return s


def norwegian_sea_convoy():
    s = Scenario("northern_shield", "NORWEGIAN SEA — REPLENISHMENT GROUP", 66.5, 3.5, 280, 6,
                 sea_state=5, wind_kn=26, visibility_nm=6, start="2027-03-11T19:15:00",
                 description=(
                   "HNoMS Maud is carrying the fuel the whole northern effort runs on, and a Yasen is "
                   "somewhere between her and the Norwegian coast. She is slow, she is loud, and she "
                   "is worth more than either of her escorts. The auxiliary has a flight deck of her "
                   "own, which gives you a third helicopter and a second place to land one."))
    s.land("mid_norway")
    s.unit("rnon_aux_maud", "HNoMS Maud (A 530)", "BLUE", s.xy(65.9, 2.6), 40, 15,
           patrol=[s.xy(67.4, 6.4), s.xy(68.0, 9.0)])
    s.unit("usn_ddg_arleigh_burke_iia", "USS Ralph Johnson (DDG 114)", "BLUE", s.xy(66.1, 2.2), 40, 15)
    s.unit("rnon_ffg_fridtjof_nansen", "HNoMS Otto Sverdrup (F 312)", "BLUE", s.xy(65.7, 3.1), 40, 15,
           radar_on=False)
    s.unit("rfn_ssn_yasen_m", "Kazan (K-561)", "RED", s.xy(67.2, 5.4), 240, 12,
           depth_m=180, radar_on=False,
           patrol=[s.xy(66.4, 3.6), s.xy(65.6, 1.8), s.xy(66.8, 1.2)])
    s.unit("rfn_mpa_tu142", "Bear 71", "RED", s.xy(68.4, 8.2), 230, 360,
           patrol=[s.xy(66.2, 2.4), s.xy(68.6, 8.8)])
    s.objectives("Get the replenishment ship through. Losing her loses the scenario however the escorts fare.",
                 destroy("RED", "Destroy the submarine and the patrol aircraft shadowing the group"),
                 lost("BLUE", "Replenishment group destroyed"))
    s.forces("NATO: 1 replenishment ship, 1 destroyer, 1 frigate (3 embarked helicopters)  ·  Russia: 1 nuclear attack submarine, 1 patrol aircraft")
    return s


def barents_strike():
    s = Scenario("arctic_shield", "BARENTS SEA — ARCTIC SHIELD", 71.5, 28.0, 460, 8, sea_state=4,
                 wind_kn=24, visibility_nm=7, start="2027-03-21T04:45:00",
                 neutral_factions=["NEUTRAL"], seed=13,
                 description=(
                   "A carrier strike group is operating north of the North Cape, inside the reach of "
                   "everything the Kola has. Olenya can put Backfires up, Monchegorsk has Foxhounds "
                   "with Kinzhal, Severomorsk-1 flies the patrol aircraft and the drones, and a "
                   "Northern Fleet surface group is at sea to the east. The air wing is the only thing "
                   "that reaches back this far, and the tankers are what let it."))
    s.land("kola_peninsula", "northern_norway", "bear_island")
    # Blue: carrier strike group, north-west of the North Cape.
    s.unit("usn_cvn_nimitz", "USS Dwight D. Eisenhower (CVN 69)", "BLUE", s.xy(72.0, 24.0), 70, 20,
           air_wing=cvw3(fighters=6, growlers=2, hawkeyes=2, tankers=2, asw=3, suw=1))
    s.unit("usn_cg_ticonderoga", "USS Gettysburg (CG 64)", "BLUE", s.xy(72.1, 24.6), 70, 20)
    s.unit("usn_ddg_burke_iii", "USS Jack H. Lucas (DDG 125)", "BLUE", s.xy(71.9, 24.8), 70, 20)
    s.unit("usn_ffg_constellation", "USS Constellation (FFG 62)", "BLUE", s.xy(71.8, 23.4), 70, 20)
    s.unit("rn_ddg_type45", "HMS Dragon (D 35)", "BLUE", s.xy(72.2, 23.5), 70, 20)
    s.unit("usn_ssn_virginia", "USS Delaware (SSN 791)", "BLUE", s.xy(72.4, 27.0), 90, 10,
           depth_m=150, radar_on=False)
    # Red: Northern Fleet surface group off the Murman coast.
    s.unit("rfn_cg_slava", "Marshal Ustinov (055)", "RED", s.xy(70.8, 34.5), 300, 18,
           patrol=[s.xy(71.4, 30.0), s.xy(70.4, 35.5)])
    s.unit("rfn_ddg_udaloy", "Vice-Admiral Kulakov (626)", "RED", s.xy(70.6, 35.2), 300, 18,
           patrol=[s.xy(71.2, 30.8), s.xy(70.2, 36.2)])
    s.unit("rfn_ffg_admiral_gorshkov", "Admiral Gorshkov (454)", "RED", s.xy(71.0, 33.8), 300, 18,
           patrol=[s.xy(71.6, 29.4), s.xy(70.6, 34.8)])
    s.unit("rfn_ssn_yasen_m", "Kazan (K-561)", "RED", s.xy(72.2, 31.0), 280, 14,
           depth_m=200, radar_on=False, patrol=[s.xy(72.4, 26.5), s.xy(72.0, 32.0)])
    # Red: the Kola air complex, each field flying what it actually flies.
    s.unit("shore_air_station", "Olenya Air Base", "RED", s.near("olenya"), 0, 0,
           air_wing=red_air_regiment(bombers=4, flankers=2,
                                     strike_patrol=[s.xy(72.6, 28.0), s.xy(72.4, 22.0),
                                                    s.xy(71.4, 20.0)]))
    s.unit("shore_air_station", "Monchegorsk Air Base", "RED", s.near("monchegorsk"), 0, 0,
           air_wing=red_air_regiment(foxhounds=2, flankers=2,
                                     strike_patrol=[s.xy(72.2, 26.5), s.xy(71.8, 22.5)]))
    s.unit("shore_air_station", "Severomorsk-1", "RED", s.near("severomorsk_1"), 0, 0,
           air_wing=red_air_regiment(mpa=2, orion=2, orlan=2, helix=1,
                                     isr_patrol=[s.xy(72.4, 30.0), s.xy(72.6, 24.0),
                                                 s.xy(71.6, 21.5), s.xy(71.0, 27.0)]))
    s.unit("civ_merchant_bulk", "MV Arctic Voyager", "NEUTRAL", s.xy(71.6, 26.0), 100, 13,
           patrol=[s.xy(71.2, 20.0), s.xy(71.9, 31.0)])
    s.unit("civ_fishing_trawler", "FV Nordkapp", "NEUTRAL", s.xy(71.4, 27.4), 200, 7,
           patrol=[s.xy(71.35, 25.2), s.xy(71.5, 28.8)])
    s.objectives("Break the Northern Fleet surface group and the aircraft that come for you.",
                 destroy("RED", "Destroy the Russian surface group and its supporting aircraft"),
                 lost("BLUE", "Carrier strike group destroyed"))
    s.forces("NATO: 1 carrier (CVW-3 det), 1 cruiser, 2 destroyers, 1 frigate, 1 submarine  ·  Russia: 1 cruiser, 1 destroyer, 1 frigate, 1 submarine, 3 air bases")
    return s


def bmd_picket():
    s = Scenario("aegis_bastion", "NORTH CAPE — BALLISTIC MISSILE DEFENCE", 71.0, 26.0, 340, 7,
                 sea_state=3, wind_kn=15, visibility_nm=9, start="2027-03-19T11:05:00",
                 neutral_factions=["NEUTRAL"],
                 description=(
                   "Monchegorsk has MiG-31s with Kinzhal and the strike group is inside their reach. "
                   "A Flight III Burke and a BMD cruiser are stationed as a picket to the east of the "
                   "carrier, which is the only place their interceptors are worth anything. The "
                   "Hawkeyes are what turn a launch warning into a firing solution; everything else "
                   "depends on how early the picket sees the shot."))
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
    s.unit("rfn_fsg_steregushchiy", "Gremyashchiy (337)", "RED", s.xy(70.4, 33.8), 290, 17,
           patrol=[s.xy(71.0, 30.4), s.xy(70.1, 34.6)])
    s.unit("rfn_ssk_kilo", "Kaluga (B-800)", "RED", s.xy(71.4, 31.4), 260, 5,
           depth_m=120, radar_on=False, patrol=[s.xy(71.3, 28.6), s.xy(71.5, 32.4)])
    s.unit("shore_air_station", "Monchegorsk Air Base", "RED", s.near("monchegorsk"), 0, 0,
           air_wing=red_air_regiment(foxhounds=3, flankers=4, orlan=1,
                                     isr_patrol=[s.xy(71.4, 30.5), s.xy(71.6, 25.0),
                                                 s.xy(70.8, 28.0)],
                                     strike_patrol=[s.xy(71.5, 29.0), s.xy(71.7, 24.5)]))
    s.unit("civ_merchant_bulk", "MV Northern Trader", "NEUTRAL", s.xy(71.1, 25.6), 95, 13,
           patrol=[s.xy(70.9, 21.0), s.xy(71.4, 30.0)])
    s.objectives("Hold the picket line and keep the carrier alive under ballistic attack.",
                 destroy("RED", "Destroy the Russian surface units, submarine and strike aircraft"),
                 lost("BLUE", "Task group destroyed"))
    s.forces("NATO: 1 carrier (CVW-3 det), 1 BMD cruiser, 2 destroyers, 1 frigate, 1 replenishment ship, 1 submarine  ·  Russia: 1 frigate, 1 corvette, 1 submarine, Monchegorsk fighter regiment")
    return s


def joint_task_force():
    s = Scenario("northern_vigil", "NORWEGIAN SEA — JOINT TASK FORCE", 69.0, 6.0, 440, 9,
                 sea_state=4, wind_kn=22, visibility_nm=8, start="2027-03-24T06:30:00",
                 neutral_factions=["NEUTRAL"], seed=7,
                 description=(
                   "Two carriers in the same body of water, which is the point of the scenario: a "
                   "CATOBAR deck flying Hawkeyes and tankers alongside a STOVL deck whose early "
                   "warning comes off a helicopter. A Northern Fleet surface group is pushing "
                   "south-west and the Kola is flying everything it has. There is more airpower here "
                   "than you can sensibly keep airborne at once, and the deck cycle is the constraint "
                   "that decides what you actually get."))
    s.land("northern_norway", "mid_norway", "jan_mayen")
    # US carrier strike group.
    s.unit("usn_cvn_ford", "USS Gerald R. Ford (CVN 78)", "BLUE", s.xy(68.4, 4.4), 50, 20,
           air_wing=cvw8(fighters=6, f35=4, growlers=2, hawkeyes=2, tankers=2, asw=3, suw=1))
    s.unit("usn_ddg_burke_iii", "USS Jack H. Lucas (DDG 125)", "BLUE", s.xy(68.5, 4.9), 50, 20)
    s.unit("usn_ddg_arleigh_burke_iia", "USS Jason Dunham (DDG 109)", "BLUE", s.xy(68.3, 3.9), 50, 20)
    s.unit("fra_ffg_fremm", "FS Aquitaine (D 650)", "BLUE", s.xy(68.2, 4.7), 50, 20)
    s.unit("rnon_aux_maud", "HNoMS Maud (A 530)", "BLUE", s.xy(68.1, 3.6), 50, 18)
    s.unit("rn_ssn_astute", "HMS Astute (S 119)", "BLUE", s.xy(69.2, 7.4), 60, 11,
           depth_m=170, radar_on=False)
    # UK carrier strike group, operating to the south-west.
    s.unit("rn_cvf_queen_elizabeth", "HMS Queen Elizabeth (R 08)", "BLUE", s.xy(67.3, 1.8), 45, 18,
           air_wing=cvf(f35=6, merlin=3, crowsnest=2, wildcat=1))
    s.unit("rn_ddg_type45", "HMS Defender (D 36)", "BLUE", s.xy(67.4, 2.3), 45, 18)
    s.unit("rn_ffg_type26", "HMS Glasgow (F 88)", "BLUE", s.xy(67.2, 1.3), 45, 18)
    s.unit("shore_air_station", "Evenes Air Station", "BLUE", s.near("evenes"), 0, 0,
           air_wing=[{"platform": "usn_fighter_f35c", "count": 2, "squadron": "332 Skv", "callsign": "Viking", "first_modex": 51},
                     {"platform": "usn_uav_mq4c", "count": 1, "squadron": "VUP-19", "callsign": "Triton", "first_modex": 61}])
    # Russian surface group and the Kola.
    s.unit("rfn_cg_slava", "Marshal Ustinov (055)", "RED", s.xy(70.4, 12.6), 215, 20,
           ai_posture="breakout", patrol=[s.xy(68.8, 8.0), s.xy(67.0, 3.0)])
    s.unit("rfn_ffg_admiral_gorshkov", "Admiral Gorshkov (454)", "RED", s.xy(70.6, 13.4), 215, 20,
           ai_posture="breakout", patrol=[s.xy(69.0, 8.8), s.xy(67.2, 3.8)])
    s.unit("rfn_fsg_steregushchiy", "Soobrazitelny (531)", "RED", s.xy(70.2, 13.9), 215, 20,
           patrol=[s.xy(69.2, 10.0), s.xy(70.8, 14.4)])
    s.unit("rfn_ssk_kilo", "Vladikavkaz (B-459)", "RED", s.xy(68.6, 8.6), 250, 5,
           depth_m=130, radar_on=False, patrol=[s.xy(68.2, 5.6), s.xy(68.9, 9.4)])
    s.unit("shore_air_station", "Kola Air Complex", "RED", s.xy(69.6, 17.6), 0, 0,
           air_wing=red_air_regiment(bombers=4, foxhounds=2, flankers=4, mpa=1, orion=2, orlan=1,
                                     isr_patrol=[s.xy(69.6, 10.0), s.xy(68.2, 5.0),
                                                 s.xy(66.8, 2.0), s.xy(68.4, 9.0)],
                                     strike_patrol=[s.xy(69.2, 9.0), s.xy(68.4, 4.0),
                                                    s.xy(67.4, 2.0)]))
    s.unit("civ_merchant_bulk", "MV Northern Trader", "NEUTRAL", s.xy(68.0, 6.4), 210, 13,
           patrol=[s.xy(66.6, 2.4), s.xy(69.4, 10.0)])
    s.unit("civ_fishing_trawler", "FV Havbris", "NEUTRAL", s.xy(67.8, 5.2), 40, 7,
           patrol=[s.xy(67.4, 4.0), s.xy(68.3, 6.6)])
    s.objectives("Two air wings, one sea. Break the Russian surface group and hold the air over it.",
                 destroy("RED", "Destroy the Russian surface group and its supporting aircraft"),
                 lost("BLUE", "Joint task force destroyed"))
    s.forces("NATO: 2 carriers (CVW-8 and UK CSG dets), 1 destroyer squadron, 1 frigate, 1 replenishment ship, 1 submarine, Evenes det  ·  Russia: 1 cruiser, 1 frigate, 1 corvette, 1 submarine, Kola air complex")
    return s


def sandbox():
    s = Scenario("sandbox_m1", "VESTFJORDEN EXERCISE AREA", 68.2, 12.0, 180, 10, sea_state=2,
                 wind_kn=8, visibility_nm=14, start="2027-01-08T09:00:00",
                 description=(
                   "A quiet range inside the Lofoten wall with one ship on each side and nothing "
                   "complicated happening. Use it to learn the plot, the orders, the deck cycle and "
                   "what a helicopter actually buys you before taking any of it somewhere it matters."))
    s.land("northern_norway")
    s.unit("usn_ddg_arleigh_burke_iia", "USS Arleigh Burke (DDG 51)", "BLUE", s.xy(67.9, 11.2), 45, 12)
    s.unit("rfn_fsg_steregushchiy", "Exercise target", "RED", s.xy(68.5, 13.0), 225, 10,
           patrol=[s.xy(68.0, 11.6), s.xy(68.7, 13.6)])
    s.objectives("Nothing is at stake. Sink the target when you feel like it.",
                 destroy("RED", "Sink the exercise target"),
                 lost("BLUE", "Own ship lost"))
    s.forces("NATO: 1 destroyer (2 embarked helicopters)  ·  Opposing force: 1 corvette")
    return s


if __name__ == "__main__":
    for build in (norwegian_sea_shadow, baltic, iceland_faroe_gap, faroe_shetland_gate,
                  vestfjorden_asw, norwegian_sea_convoy, bmd_picket, barents_strike,
                  joint_task_force, sandbox):
        build().write()
