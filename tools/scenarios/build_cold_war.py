"""Build the self-contained 1990 catalogue and four fictional Cold War missions.

Run: python3 tools/scenarios/build_cold_war.py (shapely==2.1.2, as other chart builders).
The existing modern catalogue is never rewritten. All period systems use cw90_ IDs.
Public identity sources and limitations: docs/COLD_WAR_1990.md.
"""
from pathlib import Path
import json
import math
import geography as g

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ("PUBLIC: period identity and broad fit, docs/COLD_WAR_1990.md. "
          "GAMEPLAY_ESTIMATE: ranges, signatures, hit probability, damage, timings and tactical magazines. "
          "A 1990 recognition model, not measured operational performance.")
PLATFORMS, WEAPONS, SENSORS = {}, {}, {}


def ident(name):
    return "cw90_" + name


def packed(items):
    return "PackedStringArray(" + ", ".join(json.dumps(v) for v in items) + ")"


def resource(kind, key, data, packed_fields=()):
    cls = {"platforms": "PlatformSpec", "weapons": "WeaponSpec", "sensors": "SensorSpec"}[kind]
    script = {"platforms": "platform_spec", "weapons": "weapon_spec", "sensors": "sensor_spec"}[kind]
    output = ROOT / "data" / kind / ("cold_war" if kind == "platforms" else "")
    output.mkdir(parents=True, exist_ok=True)
    fields = {"id": ident(key), **data, "source_status": SOURCE}
    lines = [f'[gd_resource type="Resource" script_class="{cls}" load_steps=2 format=3]', "",
             f'[ext_resource type="Script" path="res://scripts/data/{script}.gd" id="1"]', "",
             '[resource]', 'script = ExtResource("1")']
    for k, v in fields.items():
        text = packed(v) if k in packed_fields else json.dumps(v, ensure_ascii=False)
        lines.append(f"{k} = {text}")
    (output / (ident(key) + ".tres")).write_text("\n".join(lines) + "\n")
    {"platforms": PLATFORMS, "weapons": WEAPONS, "sensors": SENSORS}[kind][ident(key)] = fields


def radar(key, name, surface, air, rate=.8):
    resource("sensors", key, dict(display_name=name, kind="radar", emits=True,
             range_surface_nm=float(surface), range_air_nm=float(air), antenna_height_m=24.0,
             classify_rate=rate))


def sonar(key, name, passive, active, depth=0, hover=False, cz=False):
    resource("sensors", key, dict(display_name=name, kind="sonar", emits=False,
             range_surface_nm=0.0, range_air_nm=0.0, antenna_height_m=0.0, classify_rate=.85,
             passive_sensitivity_nm=float(passive), active_range_nm=float(active),
             bearing_accuracy_deg=1.8, self_noise_tolerance=.45, array_depth_m=float(depth),
             requires_hover=hover, cz_capable=cz))


def weapon(key, name, kind, targets, reach, speed, damage, **kw):
    d = dict(display_name=name, family=name, type=kind, target_types=targets,
             guidance="fire_control_directed" if kind in ["sam", "ciws"] else "active_radar_homing",
             profile="high" if kind in ["sam", "aam"] else "sea_skimming",
             max_range_nm=float(reach), min_range_nm=1.0, speed_kn=float(speed),
             damage=float(damage), base_pk=.58, salvo_default=2, launch_interval_s=3.0,
             seeker_range_nm=5.0, turn_rate_deg_s=60.0 if kind in ["sam", "aam", "ciws"] else 16.0)
    if kind == "torpedo":
        d.update(guidance="acoustic_homing", profile="subsurface", min_range_nm=.4,
                 seeker_range_nm=2.0, turn_rate_deg_s=12.0, launch_interval_s=20.0,
                 run_to_enable_nm=.7, acoustic_signature=.65, soft_kill_resistance=.7)
    if kind in ["gun", "ciws"]:
        d.update(profile="direct", min_range_nm=.1, seeker_range_nm=0.0,
                 guidance="ballistic" if kind == "gun" else "radar_directed", salvo_default=1,
                 launch_interval_s=1.0)
    d.update(kw)
    resource("weapons", key, d, ["target_types"])


def platform(key, name, short, nation, category, sensors, weapons, **kw):
    d = dict(display_name=name + " (1990)", short_name=short, nation=nation, category=category,
             domain="surface", max_speed_kn=30.0, cruise_speed_kn=16.0, turn_rate_deg_s=2.5,
             accel_kn_s=.22, health=100.0, signature_factor=1.0, mast_height_m=27.0,
             sensor_ids=[ident(v) for v in sensors], weapon_loadout={ident(k): v for k, v in weapons.items()},
             decoy_count=12, fire_control_channels=2, role=category.capitalize(),
             service_note="Period baseline; only systems represented by the game are listed.")
    if "default_air_wing" in kw:
        kw["default_air_wing"] = {ident(k): v for k, v in kw["default_air_wing"].items()}
    d.update(kw)
    resource("platforms", key, d, ["sensor_ids"])


def catalogue():
    radar("sps49", "AN/SPS-49 air-search radar", 28, 145)
    radar("sps48c", "AN/SPS-48C air-search radar", 30, 165)
    radar("spy1a", "AN/SPY-1A Aegis radar", 35, 180, 1.1)
    radar("aps124", "AN/APS-124 LAMPS III radar", 65, 35)
    radar("aps115", "AN/APS-115 Orion radar", 100, 95)
    radar("aps125", "AN/APS-series Hawkeye radar (period baseline)", 130, 250, 1.1)
    radar("aps116", "AN/APS-116 Viking radar", 85, 70)
    radar("awg9", "AN/AWG-9 Tomcat radar", 50, 130, 1.0)
    radar("fregat", "Fregat / Top Plate search radar", 32, 130)
    radar("mr320", "MR-320 Topaz / Strut Pair radar", 26, 55)
    radar("pn_a", "PNA Down Beat bomber radar", 160, 80)
    radar("osminog", "Osminog helicopter search radar", 55, 25)
    radar("civil_nav", "Civil navigation radar (period abstraction)", 14, 0, .3)
    sonar("sqs56", "AN/SQS-56 hull sonar", 10, 8)
    sonar("sqs53b", "AN/SQS-53B hull sonar", 13, 12, cz=True)
    sonar("sqr19", "AN/SQR-19 passive towed array", 22, 0, 120, cz=True)
    sonar("bqq5", "AN/BQQ-5 sonar suite", 25, 13, cz=True)
    sonar("mgk355", "MGK-355 Polinom sonar suite", 20, 12, cz=True)
    sonar("mgk335", "MGK-335 Platina hull sonar", 11, 8)
    sonar("mgk400", "MGK-400 Rubikon sonar", 19, 10, cz=True)
    sonar("aqs13", "AN/AQS-13 Sea King dipping sonar", 13, 9, 90, True)
    sonar("vgs3", "VGS-3 Ros-V dipping sonar", 12, 9, 90, True)
    for key, name in [("slq32", "AN/SLQ-32(V) electronic support"),
                      ("alr45", "AN/ALR-45/50 aircraft warning suite"),
                      ("soviet_esm", "Soviet passive ESM (period abstraction)")]:
        resource("sensors", key, dict(display_name=name, kind="esm", emits=False,
                 range_surface_nm=0.0, range_air_nm=0.0, esm_gain=1.65, classify_rate=.65))

    weapon("harpoon", "RGM-84 Harpoon Block 1C", "asm", ["surface"], 65, 480, 42,
           salvo_default=4, base_pk=.78, altitude_m=10.0)
    weapon("sm1mr", "RIM-66E SM-1MR", "sam", ["missile", "air"], 23, 1800, 38, base_pk=.48)
    weapon("sm2mr", "RIM-66 SM-2MR Block II", "sam", ["missile", "air"], 45, 2000, 40,
           vls_pack=1, base_pk=.54)
    weapon("sea_sparrow", "RIM-7M NATO Sea Sparrow", "sam", ["missile", "air"], 10, 1900, 32,
           base_pk=.49, min_range_nm=.8)
    weapon("mk46", "Mk 46 Mod 5 lightweight torpedo", "torpedo", ["subsurface"], 6, 45, 65,
           seeker_range_nm=1.7, run_to_enable_nm=.3)
    weapon("mk48", "Mk 48 Mod 4 heavyweight torpedo", "torpedo", ["surface", "subsurface"], 22, 50, 92,
           base_pk=.74)
    weapon("aim54a", "AIM-54A Phoenix", "aam", ["air"], 65, 2300, 50,
           guidance="inertial_active", base_pk=.52, min_range_nm=3.0, altitude_m=10000.0)
    weapon("aim9m", "AIM-9M Sidewinder", "aam", ["air"], 8, 1600, 34,
           guidance="infrared_homing", base_pk=.65, min_range_nm=.5, altitude_m=6000.0)
    weapon("mk45", "Mk 45 5-inch/54 gun", "gun", ["surface"], 11, 1500, 5, base_pk=.65)
    weapon("mk75", "Mk 75 76 mm gun", "gun", ["surface"], 8, 1600, 3, base_pk=.65)
    weapon("phalanx", "Phalanx Block 0/1 CIWS", "ciws", ["missile", "air"], 1.2, 2200, 15,
           base_pk=.40)
    weapon("moskit", "P-270 Moskit / SS-N-22 Sunburn", "asm", ["surface"], 60, 1350, 62,
           base_pk=.72, defensive_difficulty=1.65, salvo_default=4, altitude_m=15.0)
    weapon("p500", "P-500 Bazalt / SS-N-12 Sandbox", "asm", ["surface"], 220, 1350, 80,
           base_pk=.65, defensive_difficulty=1.55, profile="high", altitude_m=4000.0, salvo_default=4)
    weapon("shtil", "M-22 Uragan / SA-N-7 Gadfly", "sam", ["missile", "air"], 19, 1900, 38,
           base_pk=.49)
    weapon("fort", "S-300F Fort / SA-N-6 Grumble", "sam", ["missile", "air"], 45, 2300, 42,
           base_pk=.52)
    weapon("kinzhal", "3K95 Kinzhal / SA-N-9 Gauntlet", "sam", ["missile", "air"], 7, 1700, 30,
           base_pk=.51, min_range_nm=.6)
    weapon("osa_m", "Osa-M / SA-N-4 Gecko", "sam", ["missile", "air"], 5, 1600, 26,
           base_pk=.43, min_range_nm=.7)
    weapon("ak130", "AK-130 twin 130 mm gun", "gun", ["surface"], 12, 1500, 7, base_pk=.66)
    weapon("ak100", "AK-100 100 mm gun", "gun", ["surface"], 10, 1500, 5, base_pk=.64)
    weapon("ak176", "AK-176 76 mm gun", "gun", ["surface"], 8, 1500, 3, base_pk=.64)
    weapon("ak630", "AK-630 CIWS", "ciws", ["missile", "air"], 1.1, 2100, 14, base_pk=.37)
    weapon("set65", "SET-65 anti-submarine torpedo", "torpedo", ["subsurface"], 8, 40, 68)
    weapon("test71", "TEST-71M torpedo", "torpedo", ["subsurface"], 10, 40, 72)
    weapon("53_65", "53-65K wake-homing torpedo", "torpedo", ["surface"], 10, 45, 90,
           guidance="wake_homing_abstracted", base_pk=.64)
    weapon("rastrub", "Rastrub-B / SS-N-14 ASW delivery", "torpedo", ["subsurface"], 25, 240, 65,
           guidance="rocket_delivery_abstracted", run_to_enable_nm=.3)
    weapon("kh22", "Kh-22 / AS-4 Kitchen", "asm", ["surface"], 180, 1900, 90,
           profile="high", altitude_m=12000.0, base_pk=.59, defensive_difficulty=1.6, salvo_default=1)
    weapon("p120", "P-120 Malakhit / SS-N-9 Siren", "asm", ["surface"], 60, 560, 65,
           base_pk=.69, altitude_m=40.0, salvo_default=3)
    weapon("at1", "AT-1M helicopter ASW torpedo", "torpedo", ["subsurface"], 4, 35, 60,
           run_to_enable_nm=.3)

    platform("perry", "Oliver Hazard Perry long-hull frigate", "FFG Perry", "USA", "frigate",
             ["sps49", "sqs56", "slq32"], {"sm1mr":32, "harpoon":8, "mk46":12, "mk75":260, "phalanx":60},
             length_m=138.1, displacement_t=4100.0, health=90.0, max_speed_kn=29.0,
             fire_control_channels=1, aircraft_capacity=2, default_air_wing={"sh60b":1},
             role="Convoy escort / local air defence / ASW", service_note="Long-hull LAMPS III fit: Mk 13 magazine holds 32 SM-1MR plus 8 Harpoon (40 total), Mk 32 torpedoes, one represented SH-60B. No VLS, ASROC or ESSM.")
    platform("spruance", "Spruance-class destroyer, DD-963 fit", "DD Spruance", "USA", "destroyer",
             ["sps49", "sqs53b", "sqr19", "slq32"], {"harpoon":8, "sea_sparrow":24, "mk46":12, "mk45":400, "phalanx":100},
             length_m=171.6, displacement_t=8000.0, health=110.0, aircraft_capacity=2, vls_cells=61,
             default_air_wing={"sh60b":2}, role="ASW screen / surface strike",
             service_note="USS Spruance after its 1986-87 VLS/SQS-53B/SQR-19/LAMPS III refit. Land-attack Tomahawk magazine is outside these missions and omitted. No box ASROC, VL-ASROC, SM-2 or ESSM is fitted in this playable loadout.")
    platform("ticonderoga", "Ticonderoga-class VLS cruiser, CG-52 fit", "CG Ticonderoga", "USA", "cruiser",
             ["spy1a", "sqs53b", "sqr19", "slq32"], {"sm2mr":80, "harpoon":8, "mk46":12, "mk45":400, "phalanx":100},
             length_m=172.8, displacement_t=9600.0, health=135.0, aircraft_capacity=2, vls_cells=122,
             fire_control_channels=4, default_air_wing={"sh60b":2}, role="Aegis area air defence",
             service_note="Bunker Hill CG-52 period VLS fit with SPY-1A and SM-2MR; land-attack stores omitted. No ballistic-missile defence, SM-3, SM-6, ESSM or VL-ASROC.")
    platform("nimitz", "Nimitz-class aircraft carrier", "CVN Nimitz", "USA", "carrier",
             ["sps48c", "slq32"], {"sea_sparrow":24, "phalanx":120},
             length_m=332.8, displacement_t=96500.0, health=400.0, signature_factor=3.0,
             max_speed_kn=30.0, turn_rate_deg_s=1.0, accel_kn_s=.1, mast_height_m=50.0,
             aircraft_capacity=70, aviation_facility="catobar", launch_spots=4, recovery_spots=1,
             default_air_wing={"f14a":4,"e2c":1,"s3a":2,"sh3h":2},
             role="Fleet air defence / aviation command",
             service_note="1990 recognition fit: F-14A+, E-2C, S-3A and SH-3H, Sea Sparrow and Phalanx. Nine represented aircraft are a reduced scenario detachment, not the complete historical air wing. Strike squadrons are omitted.")
    platform("los_angeles", "Los Angeles-class attack submarine", "SSN Los Angeles", "USA", "nuclear attack submarine",
             ["bqq5"], {"mk48":20}, domain="subsurface", length_m=110.3, displacement_t=6900.0,
             max_speed_kn=30.0, cruise_speed_kn=7.0, health=70.0, signature_factor=.25,
             acoustic_signature=.12, max_depth_m=300.0, patrol_depth_m=150.0, depth_rate_m_s=2.0,
             has_datalink=False, fire_control_channels=0, role="Barrier patrol / passive ASW",
             service_note="Early Los Angeles-class boat with BQQ-5 and Mk 48 Mod 4. No Virginia-class sensors, VLS or post-1990 torpedo upgrade is inferred.")
    platform("sovremenny", "Sovremennyy-class missile destroyer", "DDG Sovremennyy", "USSR", "destroyer",
             ["fregat","mgk335","soviet_esm"], {"moskit":8,"shtil":48,"ak130":400,"ak630":100,"set65":8},
             length_m=156.5, displacement_t=7900.0, health=112.0, aircraft_capacity=1,
             default_air_wing={"ka27":1}, fire_control_channels=3,
             role="Surface strike / fleet air defence", service_note="Project 956 period baseline: 8 Moskit, two single-arm Uragan launchers, AK-130 and AK-630. No vertical-launch Shtil-1, Kalibr or modern Russian refit.")
    platform("udaloy", "Udaloy I-class ASW destroyer", "DD Udaloy I", "USSR", "destroyer",
             ["fregat","mgk355","soviet_esm"], {"rastrub":8,"kinzhal":64,"ak100":400,"ak630":100,"set65":8},
             length_m=163.5, displacement_t=7600.0, health=108.0, aircraft_capacity=2,
             default_air_wing={"ka27":2}, role="ASW prosecution / local air defence",
             service_note="Late-1980s Udaloy I baseline, represented by Admiral Tributs: Polinom, Rastrub-B, naval Kinzhal and two Ka-27. Rastrub's separate surface mode is omitted.")
    platform("slava", "Slava-class missile cruiser", "CG Slava", "USSR", "cruiser",
             ["fregat","mgk335","soviet_esm"], {"p500":16,"fort":64,"osa_m":40,"ak130":400,"ak630":120,"set65":10},
             length_m=186.4, displacement_t=11200.0, health=145.0, aircraft_capacity=1,
             default_air_wing={"ka27":1}, fire_control_channels=4,
             role="Long-range surface strike / area air defence",
             service_note="Project 1164 period P-500 Bazalt fit. Slava retains its Soviet name; P-1000 Vulkan and the later name Moskva are not used. Targeting support is simplified.")
    platform("victor3", "Victor III-class attack submarine", "SSN Victor III", "USSR", "nuclear attack submarine",
             ["mgk400"], {"test71":12,"53_65":8}, domain="subsurface", length_m=107.1, displacement_t=7000.0,
             max_speed_kn=30.0, cruise_speed_kn=7.0, health=70.0, signature_factor=.25,
             acoustic_signature=.20, max_depth_m=300.0, patrol_depth_m=130.0, depth_rate_m_s=2.0,
             has_datalink=False, fire_control_channels=0, role="Atlantic breakout / submerged attack",
             service_note="Project 671RTM period recognition fit with 533 mm torpedoes. Other carried weapons and wire/wake guidance details are omitted or abstracted.")
    platform("nanuchka", "Nanuchka III missile corvette", "FSG Nanuchka III", "USSR", "corvette",
             ["mr320","soviet_esm"], {"p120":6,"osa_m":20,"ak176":200,"ak630":50},
             length_m=59.3, displacement_t=730.0, health=55.0, signature_factor=.55,
             max_speed_kn=32.0, mast_height_m=18.0, turn_rate_deg_s=4.0, fire_control_channels=1,
             role="Littoral missile ambush",
             service_note="Project 1234.1: six P-120 missiles, Osa-M, AK-176 and AK-630. The corvette's large anti-ship salvo is offset by a small defensive magazine.")
    platform("merchant", "North Atlantic merchantman", "Merchant", "Civilian", "merchant",
             ["civil_nav"], {}, length_m=160.0, displacement_t=17000.0, max_speed_kn=17.0,
             cruise_speed_kn=14.0, health=95.0, fire_control_channels=0, decoy_count=0,
             has_datalink=False, role="Protected cargo vessel", service_note="Generic period cargo ship with a fictional name. It represents convoy traffic; no particular civilian hull is claimed.")
    platform("airfield", "Shore air station", "Air station", "", "shore base", [], {},
             domain="land", max_speed_kn=0.0, cruise_speed_kn=0.0, health=400.0,
             aircraft_capacity=16, aviation_facility="airfield", fire_control_channels=0,
             decoy_count=0, role="Land-based aviation", service_note="Fixed recovery and launch point at a real airfield. No installation layout or actual 1990 deployment is asserted.")

    def aircraft(key, name, short, nation, category, sensors, weapons, speed, **kw):
        values = dict(domain="air", max_speed_kn=float(speed), cruise_speed_kn=float(speed*.65),
                      turn_rate_deg_s=6.0, accel_kn_s=4.0, health=25.0, signature_factor=.6,
                      cruise_altitude_m=6000.0, max_altitude_m=12000.0, altitude_rate_m_s=20.0,
                      endurance_s=14400.0, launch_time_s=90.0, recovery_time_s=120.0,
                      fire_control_channels=0, decoy_count=6, acoustic_signature=0.0)
        values.update(kw)
        platform(key,name,short,nation,category,sensors,weapons,**values)
    aircraft("f14a","F-14A+ Tomcat","F-14A+","USA","fighter",["awg9","alr45"],
             {"aim54a":4,"aim9m":2},1200,launch_requirement="catobar",length_m=19.1,
             endurance_s=9000.0,can_refuel=True,role="Fleet air defence / long-range interception",
             service_note="F-14A+ was renamed F-14B after 1990. AWG-9, four AIM-54A and two AIM-9M. The normal Sparrow stations are deliberately empty because continuous semi-active AAM illumination is not modelled. No AMRAAM or active-homing Sparrow substitute.")
    aircraft("e2c","E-2C Hawkeye","E-2C","USA","airborne early warning",["aps125","alr45"],{},
             320,launch_requirement="catobar",length_m=17.6,cruise_altitude_m=7500.0,
             endurance_s=18000.0,role="Airborne radar picture / early warning",
             service_note="Group 0 era radar baseline; exact squadron radar subtype is not asserted. No APY-9, Cooperative Engagement Capability or aerial refuelling.")
    aircraft("s3a","S-3A Viking","S-3A","USA","ASW aircraft",["aps116","alr45"],{"mk46":4},
             430,launch_requirement="catobar",length_m=16.3,sonobuoy_count=30,
             sonobuoy_sensitivity_nm=17.0,sonobuoy_life_s=2700.0,cruise_altitude_m=2500.0,
             role="Carrier-based sonobuoy search / torpedo delivery",
             service_note="S-3A ASW fit, not S-3B Harpoon upgrade. Acoustic processing is represented by expendable sonobuoys.")
    aircraft("p3c","P-3C Orion","P-3C","USA","maritime patrol aircraft",["aps115","alr45"],{"mk46":6},
             405,launch_requirement="runway",length_m=35.6,sonobuoy_count=60,
             sonobuoy_sensitivity_nm=18.0,sonobuoy_life_s=3600.0,cruise_altitude_m=3000.0,
             endurance_s=28800.0,role="Long-endurance ASW search",
             service_note="Period Orion acoustic patrol fit. Sonobuoys replace the detailed onboard acoustic workstation; no APY-10, Mk 54 or LRASM.")
    for key,name,short,nation,sensors,weapons in [
        ("sh60b","SH-60B Seahawk","SH-60B","USA",["aps124","alr45"],{"mk46":2}),
        ("sh3h","SH-3H Sea King","SH-3H","USA",["aqs13"],{"mk46":2}),
        ("ka27","Ka-27PL Helix","Ka-27PL","USSR",["osminog","vgs3"],{"at1":2})]:
        aircraft(key,name,short,nation,"ASW helicopter",sensors,weapons,145,
                 can_hover=True,launch_requirement="helicopter",length_m=20.0,cruise_altitude_m=400.0,
                 max_altitude_m=3500.0,altitude_rate_m_s=8.0,endurance_s=10800.0,
                 sonobuoy_count=16 if key=="sh60b" else 8,sonobuoy_sensitivity_nm=15.0,
                 role="Shipboard ASW / localization",
                 service_note=("LAMPS III radar, sonobuoys and Mk 46; SH-60B has no dipping sonar. "
                               "Stop over the datum to drop buoys; the aircraft itself cannot listen through a dipping transducer."
                               if key=="sh60b" else "Period dipping-sonar ASW helicopter. Sensor envelopes, buoy count and deck cycle are game estimates."))
    aircraft("tu22m3","Tu-22M3 Backfire-C","Tu-22M3","USSR","maritime strike bomber",["pn_a"],{"kh22":1},
             1050,cruise_speed_kn=490.0,signature_factor=1.4,health=40.0,length_m=42.5,
             cruise_altitude_m=10000.0,launch_requirement="runway",role="Long-range anti-carrier strike",
             service_note="One conventional Kh-22 represents an anti-ship sortie. No Kh-32, Kinzhal or inflight refuelling. Raid strength and search geometry are fictional.")

class Mission:
    def __init__(self, sid, name, lat, lon, extent, order, date, difficulty, duration, role, learning, intent, first_orders, description):
        self.lat, self.lon = lat, lon
        self.d = dict(id=sid, name=name, era="Cold War", year=1990, order=order,
            difficulty=difficulty, duration_minutes=duration, role=role, learning=learning,
            commander_intent=intent, first_orders=first_orders,
            historical_note="Alternate history, 1990. Real geography and period platform families; the conflict, deployments and named civilian traffic are fictional. See the period notes in the platform library.",
            description=description, start_time_utc=date, player_faction="BLUE", neutral_factions=["NEUTRAL"],
            seed=1990+abs(order), map=dict(center_nm=[0,0],extent_nm=extent,anchor_lat=lat,anchor_lon=lon,
              projection="local_equirectangular",anchor_note="Nautical miles about the chart anchor; longitude uses the cosine of anchor latitude."),
            environment=dict(sea_state=3,wind_kn=16,visibility_nm=8,layer_depth_m=120,layer_strength=.5,cz_range_nm=0),
            units=[],victory_mode="all",
            force_note="Period identities; fictional 1990 deployment. Tactical magazines and reduced air detachments represent weapons available in this mission, not full real-world readiness.")
    def xy(self, lat, lon):
        return g.pos(lat,lon,self.lat,self.lon)
    def unit(self, platform_id, name, faction, lat, lon, heading=0, speed=0, **extra):
        self.d["units"].append(dict(platform=ident(platform_id),callsign=name,faction=faction,
            position_nm=self.xy(lat,lon),heading_deg=heading,speed_kn=speed,**extra))
        return self
    def heading_to(self, lat, lon, goal):
        p = self.xy(lat,lon)
        return round(math.degrees(math.atan2(goal[0]-p[0],goal[1]-p[1]))%360,3)
    def objectives(self, text, win, lose, mode="all"):
        self.d["victory_mode"]=mode
        self.d["objectives"]=dict(text=text,victory=win,loss=lose)
        return self
    def write(self):
        # Focus on commanded ships. A distant patrol base does not shrink the tactical opening.
        m=self.d["map"]
        land,labels=g.chart(self.lat,self.lon,m["center_nm"],m["extent_nm"])
        self.d["terrain"]=dict(land=land,source="Natural Earth 1:10m land 5.1.1; public domain",generalization_nm=.2)
        m.update(labels=labels,charted_nm=g.charted_box(m["center_nm"],m["extent_nm"]),
                 chart_note="Natural Earth coastline and bathymetry / 1990 scenario / not for navigation")
        path=ROOT/"data/scenarios"/(self.d["id"]+".json")
        path.write_text(json.dumps(self.d,indent=2,ensure_ascii=False)+"\n")
        return self.d


def condition(oid, kind, text, **kwargs):
    return dict(id=oid,type=kind,text=text,**kwargs)


def loss(names, text="Protected vessel lost"):
    return condition("protected","unit_lost",text,callsigns=names)


def destroyed(names):
    return condition("neutralize","all_units_lost","Neutralize the named opposing combatants",callsigns=names)


def deadline(seconds):
    return condition("deadline","time_elapsed","Mission deadline passed",seconds=seconds)


def hold(seconds):
    return condition("watch","time_elapsed","Complete the watch with protected units intact",seconds=seconds)


def area(oid,names,center,text,radius=3,count=1):
    return condition(oid,"reach_area",text,callsigns=names,center_nm=center,radius_nm=radius,count=count)


def scenarios():
    # A small opening command: escorts have radar contacts within minutes, and the merchant has
    # an exact initial course to its gate so the player can concentrate on protection.
    s=Mission("cold_war_01_convoy","NORTHERN CONVOY",61.15,1.6,125,-40,"1990-09-14T05:30:00",
      "Introductory",20,"Convoy escort commander","Radar picture, identification, coordinated Harpoon salvos",
      "Get MV North Star through the handover box. The cargo matters more than a pursuit.",
      ["Select Elrod and inspect the track list; keep its air-search radar radiating.",
       "Keep Nicholas between the convoy and the eastern threat axis; identify contacts before a Harpoon salvo.",
       "MV North Star already steers for the handover box at 14 kn. Keep it alive; use time compression between contacts."],
      "14 September 1990, northern North Sea. A Soviet missile corvette has slipped past the outer screen. Two long-hull Perry frigates cover one final reinforcement ship on the leg toward Norway. A neutral merchant crosses the operating area. The corvette has six heavy anti-ship missiles; your Mk 13 launchers share their magazines between Standard and Harpoon.")
    gate=s.xy(61.43,1.95)
    cargo="MV North Star"
    s.unit("perry","USS Elrod (FFG 55)","BLUE",61.13,1.50,35,16)
    s.unit("perry","USS Nicholas (FFG 47)","BLUE",61.04,1.52,35,16,radar_on=False,air_wing=[])
    s.unit("merchant",cargo,"BLUE",60.99,1.36,s.heading_to(60.99,1.36,gate),14)
    s.unit("nanuchka","Soviet missile corvette (Nanuchka III)","RED",61.49,2.10,220,16,
           patrol_nm=[s.xy(61.10,1.60),s.xy(61.5,2.20)])
    s.unit("merchant","MV Skagen Trader","NEUTRAL",61.35,.82,145,12,
           patrol_nm=[s.xy(60.9,1.3)],radar_on=True)
    s.objectives("Escort North Star to the marked handover box before the 3-hour deadline. Losing either merchant or both escorts fails the mission.",
       [area("handover",[cargo],gate,"North Star reached the handover box",radius=3)],
       [loss([cargo,"MV Skagen Trader"],"Cargo or neutral merchant lost"),
        condition("screen_lost","all_units_lost","Both escorts lost",callsigns=["USS Elrod (FFG 55)","USS Nicholas (FFG 47)"]),deadline(10800)])
    s.d["forces"]="NATO: 2 Perry frigates, 1 cargo ship, 1 SH-60B / USSR: 1 missile corvette / neutral shipping"
    yield s.write()

    s=Mission("cold_war_02_barrier","THE ICELAND-FAROE BARRIER",63.12,-11.65,720,-30,"1990-09-16T01:10:00",
      "Intermediate",25,"ASW barrier commander","Passive bearings, sonobuoys, layer depth and firing solutions",
      "Deny the Victor III its southern exit. Hold the barrier for three hours, or neutralize the boat.",
      ["Select Dallas to view its local sonar picture. Keep it slow and passive; build a solution before committing a Mk 48.",
       "Launch a Spruance SH-60B toward the suspected passage and drop sonobuoys. It has no dipping sonar.",
       "Use Keflavik's P-3C to extend the search. Protect Spruance and prevent the submarine reaching the southern gate."],
      "16 September 1990, Iceland-Faroe Ridge. An unidentified Soviet Victor III is attempting an Atlantic breakout. USS Dallas and USS Spruance hold a compact barrier, with a P-3C detachment at Keflavik. A seasonal acoustic layer complicates the search; below-layer listening and deliberate localization matter more than speed. This is a submarine search, not a radar duel.")
    s.d["environment"].update(sea_state=4,wind_kn=23,visibility_nm=6,layer_depth_m=140,layer_strength=.55,cz_range_nm=30)
    exit_gate=s.xy(62.98,-11.76)
    red="Soviet submarine (Victor III)"
    s.unit("los_angeles","USS Dallas (SSN 700)","BLUE",63.19,-11.48,25,6,depth_m=170,radar_on=False)
    s.unit("spruance","USS Spruance (DD 963)","BLUE",63.01,-11.38,305,8,radar_on=False,
           air_wing=[dict(platform=ident("sh60b"),count=2,callsign="Spruance",first_modex=60,
                          patrol_nm=[s.xy(63.24,-11.65),s.xy(63.08,-11.65)])])
    s.unit("airfield","Keflavik Air Base","BLUE",63.985,-22.605,
           air_wing=[dict(platform=ident("p3c"),count=1,callsign="Orion",squadron="Scenario patrol detachment",first_modex=21,patrol_nm=[s.xy(63.24,-11.65),s.xy(63.06,-11.80)])])
    s.unit("victor3",red,"RED",63.30,-11.40,210,7,depth_m=160,radar_on=False,ai_posture="breakout",
           patrol_nm=[exit_gate])
    s.objectives("Deny the southern gate for 3 hours or neutralize the Victor III. A breakout or the loss of either barrier ship fails the mission.",
       [hold(10800),destroyed([red])],[loss(["USS Dallas (SSN 700)","USS Spruance (DD 963)"],"Barrier ship lost"),
       area("breakout",[red],exit_gate,"Victor III crossed the southern barrier",radius=3)],mode="any")
    s.d["map"].update(focus_center_nm=[0,0],focus_extent_nm=110)
    s.d["forces"]="NATO: Dallas, Spruance, 2 SH-60B, 1 Keflavik P-3C / USSR: 1 Victor III"
    yield s.write()

    s=Mission("cold_war_03_carrier","NORWEGIAN SEA: CARRIER WATCH",68.1,4.2,600,-20,"1990-09-18T04:45:00",
      "Advanced",30,"Carrier group commander","Early warning, fighter interception and layered air defence",
      "Keep Eisenhower afloat through the two-hour air watch. Preserve the cruiser as the inner missile screen.",
      ["Launch the E-2C Hawkeye, then a pair of F-14A+ Tomcats from Eisenhower.",
       "Send the Hawkeye and fighters northeast of the group; keep Bunker Hill's radar on.",
       "Reserve SM-2 for leakers and recall aircraft before fuel exhaustion. No task requires chasing the cruiser into its missile envelope."],
      "18 September 1990, Norwegian Sea. A fictional crisis has brought Eisenhower north and a Soviet cruiser into the Norwegian Sea. Two Backfire-C aircraft are inbound from the northeast with conventional Kh-22 missiles. The carrier has a small playable detachment of Tomcats, Hawkeye, Vikings and Sea Kings. Airborne radar buys warning time; the screen must stop any missiles that get through the fighter patrol.")
    s.d["environment"].update(sea_state=4,wind_kn=20,visibility_nm=10,layer_depth_m=170,cz_range_nm=30)
    cv="USS Dwight D. Eisenhower (CVN 69)"
    cg="USS Bunker Hill (CG 52)"
    s.unit("nimitz",cv,"BLUE",67.83,3.55,250,18)
    s.unit("ticonderoga",cg,"BLUE",68.01,3.85,250,18)
    s.unit("spruance","USS Spruance (DD 963)","BLUE",67.82,4.15,250,18,radar_on=False)
    s.unit("slava","Slava","RED",69.05,8.1,225,16,patrol_nm=[s.xy(68.5,6.3),s.xy(69.2,8.4)])
    for i,lat in enumerate([71.40,71.48]):
        s.unit("tu22m3","Backfire raid %d"%(i+1),"RED",lat,9.1+i*.2,215,490,
               patrol_nm=[s.xy(68.15,4.4)],ai_posture="breakout")
    s.objectives("Survive the 2-hour carrier watch, or neutralize Slava and both raiders. Eisenhower or Bunker Hill lost means defeat.",
       [hold(7200),destroyed(["Slava","Backfire raid 1","Backfire raid 2"])],
       [loss([cv,cg],"Carrier or air-defence commander lost")],mode="any")
    s.d["map"].update(focus_center_nm=s.xy(68.0,4.0),focus_extent_nm=210)
    s.d["forces"]="NATO: Eisenhower, Bunker Hill, Spruance; F-14A+, E-2C, S-3A, SH-3H and SH-60B / USSR: Slava, 2 Backfire-C"
    yield s.write()

    s=Mission("cold_war_04_baltic","BALTIC: THE NARROW WATER",55.30,16.25,145,-10,"1990-09-20T19:20:00",
      "Advanced",20,"Surface action commander","Neutral identification, emissions and missile engagement geometry",
      "Stop the Soviet destroyer crossing the western gate. Merchant traffic remains protected even under fire.",
      ["Use Elrod's radar to establish the surface picture; inspect identity and solution before firing.",
       "Keep Spruance offset from Elrod so one incoming salvo does not exhaust a single defensive sector.",
       "Attack the destroyer before it reaches the western gate; the neutral merchant is not a valid target."],
      "20 September 1990, Bornholm Basin. A Soviet Sovremennyy-class destroyer is moving west toward the Danish straits. Two US escorts on a fictional Baltic deployment must close the passage while civilian traffic continues. The shallow basin gives no deep-water convergence-zone advantage. Eight Moskit missiles are a serious threat; identifying the right surface contact is part of the mission.")
    s.d["environment"].update(sea_state=2,wind_kn=11,visibility_nm=5,layer_depth_m=35,layer_strength=.3,cz_range_nm=0)
    gate=s.xy(55.30,15.55)
    red="Otlichnyy"
    s.unit("perry","USS Elrod (FFG 55)","BLUE",55.37,15.87,75,15)
    s.unit("spruance","USS Spruance (DD 963)","BLUE",55.20,15.98,70,15,radar_on=False)
    s.unit("sovremenny",red,"RED",55.34,16.90,270,24,ai_posture="breakout",patrol_nm=[gate])
    s.unit("merchant","MV Baltic Trader","NEUTRAL",55.56,16.30,230,12,
           patrol_nm=[s.xy(55.35,15.75)],radar_on=True)
    s.objectives("Neutralize Otlichnyy before it crosses the western gate. Losing a US escort, the neutral merchant, or the gate fails the mission.",
       [destroyed([red])],[loss(["USS Elrod (FFG 55)","USS Spruance (DD 963)","MV Baltic Trader"],"Escort or protected neutral lost"),
        area("breakout",[red],gate,"Otlichnyy reached the Danish-straits approach",radius=3),deadline(7200)])
    s.d["forces"]="NATO: 1 Perry frigate, 1 Spruance destroyer, 3 SH-60B / USSR: Otlichnyy, 1 Ka-27 / neutral merchant"
    yield s.write()


def validate(cases):
    # This inventory is an explicit era boundary. Scenario overrides and embarked aircraft are
    # checked recursively, preventing modern defaults from leaking into a period mission.
    for pid,p in PLATFORMS.items():
        assert all(s in SENSORS for s in p["sensor_ids"]),pid
        assert all(w in WEAPONS for w in p["weapon_loadout"]),pid
        assert all(a in PLATFORMS for a in p.get("default_air_wing",{})),pid
    for s in cases:
        assert s["year"]==1990 and s["start_time_utc"].startswith("1990-")
        names={u["callsign"] for u in s["units"]}
        for unit in s["units"]:
            p=PLATFORMS[unit["platform"]]
            assert all(w in WEAPONS for w in unit.get("loadout",p["weapon_loadout"]))
            for a in unit.get("air_wing",[]):
                assert a["platform"] in PLATFORMS and PLATFORMS[a["platform"]]["domain"]=="air"
        for o in s["objectives"]["victory"]+s["objectives"]["loss"]:
            assert all(n in names for n in o.get("callsigns",[]))
    manifest=dict(year=1990,scenario_ids=[s["id"] for s in cases],
        platforms=sorted(PLATFORMS),weapons=sorted(WEAPONS),sensors=sorted(SENSORS),
        note="Explicit period inventory. All performance values remain gameplay estimates.")
    (ROOT/"data/cold_war_1990_manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")


if __name__=="__main__":
    catalogue()
    cases=list(scenarios())
    validate(cases)
    print(f"1990 pack: {len(cases)} missions, {len(PLATFORMS)} platforms, {len(WEAPONS)} weapons, {len(SENSORS)} sensors")
