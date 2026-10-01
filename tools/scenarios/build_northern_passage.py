"""Generate M31's original introductory escort using the existing scenario/geography builder.

Run from the repository root: python3 tools/scenarios/build_northern_passage.py
Dispositions, timings, readiness and combat performance are fictional gameplay assumptions.
"""
from math import dist
from build_scenarios import Scenario


def build():
    s = Scenario("northern_passage", "NORTHERN PASSAGE", 67.0, 11.7, 110, 0,
                 seed=31, sea_state=3, wind_kn=12, visibility_nm=9,
                 start="2027-05-18T08:00:00", neutral_factions=["NEUTRAL"],
                 description=("An allied freighter is making a short passage off the Norwegian coast. "
                              "Two Russian surface combatants have entered the approaches, among civilian traffic. "
                              "Your task is to deliver the freighter, not clear the sea of every opposing ship. "
                              "There is time to put a Seahawk airborne before the surface forces close. "
                              "Broken clouds and light drizzle hang over a moderate sea."))
    # Original authored weather for this fictional mission. Cloud/rain affect presentation;
    # the existing sea state and visibility continue to govern sensor conditions.
    s.d["environment"]["cloud_cover"] = 0.65
    s.d["environment"]["rain_intensity"] = 0.12
    cargo = "MV Northern Light"
    burke = "USS Truxtun (DDG 103)"
    nansen = "HNoMS Roald Amundsen (F 311)"
    route = [[3, 0], [3, 5]]
    route_length = sum(dist(a, b) for a, b in zip([[0, 0]] + route, route))
    assert abs(route_length - 8.0) < 1e-9
    s.d["route_validation"] = {"route_length_nm": route_length, "ordered_speed_kn": 15,
                               "nominal_travel_seconds": route_length / 15 * 3600,
                               "deadline_seconds": 2700,
                               "note": "Turning and the exit radius are measured separately in validation-m31.json."}
    # Start at command scale; the regional pane retains the full theatre and coastline.
    s.d["map"]["focus_center_nm"] = [14, 3]
    s.d["map"]["focus_extent_nm"] = 32
    s.meta("Norwegian Sea", "Introductory", 30, "Escort commander",
           "Reconnaissance, emissions, protecting a moving civilian asset, and finite missile defence",
           "Bring Northern Light into the exit box before 08:45Z. Keep neutral traffic alive; enemy destruction is optional.",
           ["Northern Light is already following an eight-mile dogleg at 15 knots. The escorts are following her; keep that screen together.",
            "While paused, press Air / F3, select Truxtun and the Seahawk, then Launch. Once airborne, choose Patrol and click two corners near the convoy to repeat a search circuit. Recover early when threats close; right-click water gives a transit order instead.",
            "Click a contact to inspect it without losing your selected ship. Right-click an unknown to investigate it; use the Seahawk so the escorts stay with the convoy. Right-click a classified hostile to attack it: the ship closes to range, chooses the weapon and keeps firing until the contact is destroyed. Shift+right-click a contact for a stated salvo or the full firing board. Automatic defence is on."],
           setting_note="Original fictional 2027 operation, not a reconstruction of a real conflict or a 1999 order of battle.")
    s.d["force_note"] = ("Represented families: Arleigh Burke Flight IIA, Fridtjof Nansen, Project 22350, Project 20380, "
                         "and MH-60R. The single US helicopter detachment, readiness, magazines, sensor performance, "
                         "hit probabilities and deployments are representative gameplay assumptions; see DATA_SOURCES.md. "
                         "The freighter uses the existing generic bulk carrier's 15-knot cap and is under your navigation orders; all merchant names are fictional.")
    s.d["operation_plan"] = [
        {"title": "01 / Establish the picture", "task": "Launch reconnaissance, inspect unknowns and keep the escorts with the freighter. The opposing commander must detect and classify its own targets."},
        {"title": "02 / Protect the passage", "task": "Keep radar coverage and defensive magazines available as the freighter turns north. Use NSM against classified hostile surface contacts if useful; do not chase them away from the convoy."},
        {"title": "03 / Deliver the ship", "task": "Reach the exit within 45 minutes, with no neutral sinking caused by your weapons. Review losses, ammunition and observed events in the debrief."},
    ]
    s.unit("usn_ddg_arleigh_burke_iia", burke, "BLUE", [1, 1], 90, 15,
           formation_leader=cargo, formation_offset_nm=[-1, 1],
           air_wing=[{"platform": "usn_helo_mh60r", "count": 1, "callsign": "Seahawk", "first_modex": 11}])
    s.unit("rnon_ffg_fridtjof_nansen", nansen, "BLUE", [1, -1], 90, 15,
           formation_leader=cargo, formation_offset_nm=[1, 1], air_wing=[])
    s.unit("civ_merchant_bulk", cargo, "BLUE", [0, 0], 90, 15,
           patrol=route, follow_route=True, air_wing=[])
    s.unit("rfn_ffg_admiral_gorshkov", "Admiral Gorshkov", "RED", [30, 4], 270, 16,
           radar_on=True, ai_posture="breakout", patrol=[[10, 4], [10, -4]], air_wing=[])
    s.unit("rfn_fsg_steregushchiy", "Stoikiy", "RED", [36, -4], 270, 16,
           radar_on=False, patrol=[[25, -4], [15, -2]], air_wing=[])
    s.unit("civ_merchant_bulk", "MV Skerry Trader", "NEUTRAL", [5, -3], 0, 14, air_wing=[])
    s.unit("civ_merchant_bulk", "MV Coastal Star", "NEUTRAL", [13, 6], 270, 12, air_wing=[])
    s.objectives("Deliver Northern Light before 08:45Z without sinking a neutral vessel.",
                 [{"id": "deliver_freighter", "type": "reach_area", "callsigns": [cargo],
                   "center_nm": route[-1], "radius_nm": 0.35, "count": 1,
                   "text": "Escort Northern Light into the exit box"}],
                 [{"id": "freighter_lost", "type": "unit_lost", "callsigns": [cargo], "text": "Northern Light was lost"},
                  {"id": "deadline", "type": "time_elapsed", "seconds": 2700, "text": "The 45-minute passage deadline expired"},
                  {"id": "civilian_loss", "type": "unit_lost", "caused_by": "BLUE",
                   "callsigns": ["MV Skerry Trader", "MV Coastal Star"], "text": "Your force sank a neutral vessel"}])
    s.forces("Your command: Burke IIA destroyer, Nansen frigate, one MH-60R and the escorted freighter. Opposition: Gorshkov frigate and Steregushchiy corvette. Two neutral merchants share the approaches.")
    return s


if __name__ == "__main__":
    build().write()
