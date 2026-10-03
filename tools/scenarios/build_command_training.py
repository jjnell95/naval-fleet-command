"""Build short, assessed command exercises on the existing Norwegian Sea chart.

Run from the repository root. The two fictional drills use stock platforms, real sensor and
weapon code, and complete only after the player's accepted commands produce the taught result.
"""
import copy
import json
from pathlib import Path
from recognition_brief import apply_recognition_brief

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data/scenarios"


def task(key, text, after=None):
    return {"id": key, "type": "training_task", "practice": key, "text": text,
            "after": after or []}


def base(sid, name, description, order):
    passage = json.loads((OUT / "northern_passage.json").read_text())
    scenario = {key: copy.deepcopy(passage[key]) for key in ["map", "environment", "terrain"]}
    scenario["map"].update(center_nm=[0, 0], extent_nm=60, focus_center_nm=[0, 0], focus_extent_nm=32)
    scenario["environment"].update(sea_state=2, visibility_nm=8, layer_depth_m=0, layer_strength=0)
    scenario.update(id=sid, name=name, description=description, collection="exercises", order=order,
                    player_faction="BLUE", seed=31, year=2027, era="Modern", theatre="Norwegian Sea",
                    start_time_utc="2027-05-18T08:00:00", difficulty="Introductory", duration_minutes=10,
                    force_note="Fictional controlled exercise; stock platform performance and combat probabilities apply.",
                    setting_note="Original command practice, not a reconstruction of a real exercise.")
    return scenario


def missile_defence():
    s = base("training_missile_defence", "COMMAND PRACTICE / MISSILE DEFENCE",
             "Practice deliberate missile defence with one destroyer. Select manual defence before the exercise opponent enters. "
             "Wait for your radar's inbound report, pause to inspect it, then authorize interception with X. "
             "Credit requires an accepted interception order against a detected inbound and your destroyer surviving its resolution.", 92)
    s.update(role="Air-defence commander", learning="Manual interception, detected threat picture and finite defensive magazines",
             commander_intent="Select manual defence, engage the detected inbound, and keep the destroyer afloat.",
             first_orders=["Select USS Practice. Classic starts in manual missile defence; under Normal, open the Normal / Classic options button and enable Manual missile defence (X). The raid waits for manual defence.",
                           "Resume at 1x. When an inbound is reported, Space pauses. Select USS Practice and press X to authorize interception.",
                           "Defence shows detected threats. Resume and monitor the engagement; the exercise ends when the inbound resolves and the destroyer survives."])
    s["units"] = [{"platform": "usn_ddg_arleigh_burke_iia", "callsign": "USS Practice", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 90, "speed_kn": 0, "air_wing": []}]
    s["events"] = [{"id": "exercise_raid", "after": ["manual_defence"], "side": "RED", "audience": "BLUE",
                    "message": "Exercise control: opposing missile ship released. Hold radar coverage. Authorize interception when your watch reports an inbound.",
                    "reinforcements": [{"platform": "rfn_ffg_admiral_gorshkov", "callsign": "Exercise Opponent", "faction": "RED", "position_nm": [16, 0], "heading_deg": 270, "speed_kn": 0, "radar_on": True,
                                         "loadout": {"p800_oniks": 1}, "air_wing": []}]}]
    s["objectives"] = {"text": s["commander_intent"], "victory": [task("manual_defence", "Select manual missile defence"), task("manual_intercept", "Authorize interception of a detected inbound", ["manual_defence"]), task("defence_resolved", "Resolve the inbound and keep USS Practice afloat", ["manual_intercept"])],
                       "loss": [{"id": "ship_lost", "type": "unit_lost", "callsigns": ["USS Practice"], "text": "USS Practice was lost; retry and engage earlier"}, {"id": "deadline", "type": "time_elapsed", "seconds": 1800, "text": "Practice window ended; review the incomplete command task"}]}
    return apply_recognition_brief(s)


def asw():
    s = base("training_asw", "COMMAND PRACTICE / DELIBERATE SONAR",
             "An airborne Seahawk is near a controlled submarine datum. Deploy its dipping sonar and wait for the complete hover/lower/listen cycle. "
             "Inspect the passive bearing before ordering active sonar for range. Authorize a torpedo only after a measured fix, then recover the array deliberately. "
             "The exercise assesses orders and sensor reports; time alone earns no credit.", 93)
    s.update(role="ASW air commander", learning="Deliberate deployment, bearing uncertainty, active localization and attack authorization",
             commander_intent="Listen, inspect the bearing, localize, authorize a torpedo, and recover the array.",
             first_orders=["Select Seahawk Practice, already airborne near the datum. Orders > Sensors > Deploy dipping sonar. Resume until LISTENING appears.",
                           "Inspect the passive contact: POSITION states bearing only. Then select Seahawk and order Active sonar to obtain a measured range.",
                           "Inspect the measured contact and explicitly fire one torpedo. Raise dipping sonar and wait until STOWED. Exercise control's recognition brief identifies the opposing submarine family."])
    s["units"] = [{"platform": "usn_helo_mh60r", "callsign": "Seahawk Practice", "faction": "BLUE", "position_nm": [0, 0], "heading_deg": 90, "speed_kn": 1},
                  {"platform": "rfn_ssk_kilo", "callsign": "Exercise Submarine", "faction": "RED", "position_nm": [1.5, 0], "heading_deg": 0, "speed_kn": 5, "depth_m": 60, "radar_on": False, "loadout": {}, "ai_posture": "breakout", "patrol_nm": [[1.5, 2], [1.5, -2]]}]
    keys = [("dip_listen", "Deploy the array and reach LISTENING"), ("passive_datum", "Inspect the passive bearing and unresolved range"), ("active_fix", "Order active sonar and obtain a measured fix"), ("authorize_attack", "Explicitly authorize a torpedo against the measured fix"), ("recover_array", "Raise the array and wait for STOWED")]
    s["objectives"] = {"text": s["commander_intent"], "victory": [task(key, text, [keys[i - 1][0]] if i else []) for i, (key, text) in enumerate(keys)],
                       "loss": [{"id": "aircraft_lost", "type": "unit_lost", "callsigns": ["Seahawk Practice"], "text": "Seahawk Practice was lost"}, {"id": "deadline", "type": "time_elapsed", "seconds": 1800, "text": "Practice window ended; review the incomplete sonar task"}]}
    return apply_recognition_brief(s)


if __name__ == "__main__":
    for scenario in [missile_defence(), asw()]:
        path = OUT / f"{scenario['id']}.json"
        path.write_text(json.dumps(scenario, indent=2) + "\n")
        print(path.relative_to(ROOT))
