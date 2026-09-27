"""The 2027 Pacific, Gulf and Mediterranean catalogue: PLAN, JMSDF/JASDF, Iranian and further
Russian and civilian platforms, with their weapons and sensors.

Run through build_theatres.py, which also writes the missions. The modern North Atlantic catalogue
and the 1990 pack are never rewritten; everything here carries a nation prefix (pla_, jmsdf_,
jasdf_, jgsdf_, irn_, rfn_, civ_) and is listed in data/theatres_2027_manifest.json so tests can
check that every reference resolves. Public identity sources and model limits: docs/THEATRES_2027.md.

Every number is a GAMEPLAY_ESTIMATE on the same scale as the existing catalogue (Harpoon 70 nm at
480 kn, SM-2 45 nm, SPY-1D(V) 200 nm against air, a Virginia at acoustic 0.08, a Kilo at 0.05).
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ("PUBLIC: class identity, dimensions and broad fit; see docs/THEATRES_2027.md. "
          "GAMEPLAY_ESTIMATE: ranges, signatures, hit probability, damage, timings, magazines and "
          "detachments. A 2027 recognition model, not a capability claim.")
PLATFORMS, WEAPONS, SENSORS = {}, {}, {}
## Modern-catalogue resources these platforms carry as fitted. Listed so the manifest is complete.
SHARED_WEAPONS = ["sm2_family", "sm3_family", "sm6_family", "essm_family", "ram_block2", "phalanx_ciws",
                  "mk45_mod4_gun", "rgm_84_harpoon", "agm_84_harpoon", "oto_76mm_gun", "mk8_114mm_gun",
                  "aim120_family", "aim9x_air", "jsm_missile", "p800_oniks", "oneway_attack_drone", "mk54_lwt"]
SHARED_SENSORS = ["an_spy_1d_v", "an_apg_81", "an_asq_239", "civil_nav_radar", "mp_405", "nato_esm_suite"]


def packed(items):
    return "PackedStringArray(" + ", ".join(json.dumps(v) for v in items) + ")"


def resource(kind, key, data, packed_fields=()):
    cls = {"platforms": "PlatformSpec", "weapons": "WeaponSpec", "sensors": "SensorSpec"}[kind]
    script = {"platforms": "platform_spec", "weapons": "weapon_spec", "sensors": "sensor_spec"}[kind]
    output = ROOT / "data" / kind / ("theatres" if kind == "platforms" else "")
    output.mkdir(parents=True, exist_ok=True)
    fields = {"id": key, **data, "source_status": SOURCE}
    lines = [f'[gd_resource type="Resource" script_class="{cls}" load_steps=2 format=3]', "",
             f'[ext_resource type="Script" path="res://scripts/data/{script}.gd" id="1"]', "",
             '[resource]', 'script = ExtResource("1")']
    for k, v in fields.items():
        text = packed(v) if k in packed_fields else json.dumps(v, ensure_ascii=False)
        lines.append(f"{k} = {text}")
    (output / (key + ".tres")).write_text("\n".join(lines) + "\n")
    {"platforms": PLATFORMS, "weapons": WEAPONS, "sensors": SENSORS}[kind][key] = fields


# --- Factories --------------------------------------------------------------------------------

def radar(key, name, surface, air, rate=1.0, height=24.0):
    resource("sensors", key, dict(display_name=name, kind="radar", emits=True,
             range_surface_nm=float(surface), range_air_nm=float(air), antenna_height_m=float(height),
             classify_rate=rate))


def sonar(key, name, passive, active, depth=0, hover=False, cz=False, rate=1.0):
    resource("sensors", key, dict(display_name=name, kind="sonar", emits=False,
             range_surface_nm=0.0, range_air_nm=0.0, antenna_height_m=0.0, classify_rate=rate,
             passive_sensitivity_nm=float(passive), active_range_nm=float(active),
             bearing_accuracy_deg=1.6, self_noise_tolerance=0.5, array_depth_m=float(depth),
             requires_hover=hover, cz_capable=cz))


def esm(key, name, gain=1.8, height=24.0, rate=1.1):
    resource("sensors", key, dict(display_name=name, kind="esm", emits=False, range_surface_nm=0.0,
             range_air_nm=0.0, antenna_height_m=float(height), esm_gain=gain, classify_rate=rate))


def weapon(key, name, kind, targets, reach, speed, damage, **kw):
    d = dict(display_name=name, family=name.split(" /")[0], type=kind, target_types=targets,
             guidance="fire_control_directed" if kind in ["sam", "ciws"] else "active_radar_homing",
             profile="high" if kind in ["sam", "aam"] else "sea_skimming",
             max_range_nm=float(reach), min_range_nm=2.0, speed_kn=float(speed),
             damage=float(damage), base_pk=0.6, salvo_default=2, launch_interval_s=3.0,
             seeker_range_nm=6.0, turn_rate_deg_s=60.0 if kind in ["sam", "aam", "ciws"] else 15.0,
             signature_factor=0.12, altitude_m=10.0, soft_kill_resistance=1.0)
    if kind == "torpedo":
        d.update(guidance="acoustic_homing", profile="subsurface", min_range_nm=0.4,
                 seeker_range_nm=2.2, turn_rate_deg_s=12.0, launch_interval_s=20.0,
                 run_to_enable_nm=0.8, acoustic_signature=0.65, soft_kill_resistance=0.7, altitude_m=0.0)
    if kind in ["gun", "ciws"]:
        d.update(profile="direct" if kind == "gun" else "high", min_range_nm=0.4 if kind == "gun" else 0.05,
                 seeker_range_nm=0.0 if kind == "gun" else 1.0,
                 guidance="ballistic" if kind == "gun" else "radar_directed", salvo_default=6 if kind == "gun" else 1,
                 launch_interval_s=1.0)
    if kind == "aam":
        d.update(min_range_nm=1.0, altitude_m=8000.0, signature_factor=0.05)
    d.update(kw)
    resource("weapons", key, d, ["target_types"])


def platform(key, name, short, nation, category, sensors, weapons, **kw):
    d = dict(display_name=name, short_name=short, nation=nation, category=category,
             domain="surface", max_speed_kn=30.0, cruise_speed_kn=16.0, turn_rate_deg_s=2.8,
             accel_kn_s=0.22, health=100.0, signature_factor=1.0, mast_height_m=27.0,
             sensor_ids=list(sensors), weapon_loadout=dict(weapons),
             decoy_count=12, decoy_effectiveness=0.35, fire_control_channels=2, role=category.capitalize(),
             service_note="Representative 2027 fit; only systems the game represents are listed.")
    d.update(kw)
    resource("platforms", key, d, ["sensor_ids"])


def aircraft(key, name, short, nation, category, sensors, weapons, speed, **kw):
    values = dict(domain="air", max_speed_kn=float(speed), cruise_speed_kn=float(speed * 0.62),
                  turn_rate_deg_s=6.0, accel_kn_s=4.0, health=25.0, signature_factor=0.7,
                  cruise_altitude_m=8000.0, max_altitude_m=13000.0, altitude_rate_m_s=25.0,
                  endurance_s=10800.0, launch_time_s=60.0, recovery_time_s=90.0,
                  fire_control_channels=0, decoy_count=8, acoustic_signature=0.0, mast_height_m=5.0)
    values.update(kw)
    platform(key, name, short, nation, category, sensors, weapons, **values)


def helicopter(key, name, short, nation, sensors, weapons, speed=150, **kw):
    values = dict(can_hover=True, launch_requirement="helicopter", cruise_altitude_m=400.0,
                  max_altitude_m=3500.0, altitude_rate_m_s=8.0, endurance_s=10800.0, health=18.0,
                  signature_factor=0.25, decoy_count=6, turn_rate_deg_s=10.0, accel_kn_s=6.0)
    values.update(kw)
    aircraft(key, name, short, nation, "ASW helicopter", sensors, weapons, speed, **values)


def submarine(key, name, short, nation, sensors, weapons, length, tonnes, speed, acoustic, depth, **kw):
    values = dict(domain="subsurface", category="attack submarine", length_m=float(length),
                  displacement_t=float(tonnes), max_speed_kn=float(speed), cruise_speed_kn=7.0,
                  turn_rate_deg_s=2.2, accel_kn_s=0.2, health=55.0, signature_factor=0.25,
                  mast_height_m=8.0, acoustic_signature=acoustic, max_depth_m=float(depth),
                  patrol_depth_m=min(150.0, depth * 0.5), depth_rate_m_s=2.0, has_datalink=True,
                  fire_control_channels=0, decoy_count=6, decoy_effectiveness=0.3)
    values.update(kw)
    category = values.pop("category")
    platform(key, name, short, nation, category, sensors, weapons, **values)


def site(key, name, short, nation, category, sensors, weapons, **kw):
    """A fixed installation ashore: a coastal missile battery, a SAM site, a drone launch site."""
    values = dict(domain="land", max_speed_kn=0.0, cruise_speed_kn=0.0, turn_rate_deg_s=0.0,
                  accel_kn_s=0.0, health=60.0, signature_factor=1.2, mast_height_m=30.0,
                  fire_control_channels=0, decoy_count=0, decoy_effectiveness=0.0, has_datalink=True,
                  aircraft_capacity=0, aviation_facility="none")
    values.update(kw)
    platform(key, name, short, nation, category, sensors, weapons, **values)


# --- The catalogue ----------------------------------------------------------------------------

def catalogue():
    # ---------- People's Liberation Army Navy ----------
    radar("pla_type346b", "Type 346B active phased-array radar", 45, 250, 1.2, 30)
    radar("pla_type346a", "Type 346A active phased-array radar", 40, 220, 1.15, 28)
    radar("pla_type518", "Type 518 L-band air-search radar", 20, 250, 0.9, 32)
    radar("pla_type382", "Type 382 air-search radar", 30, 140, 1.0, 30)
    radar("pla_type366", "Type 366 over-the-horizon targeting radar", 60, 0, 0.8, 24)
    radar("pla_type364", "Type 364 search radar", 25, 70, 0.9, 20)
    radar("pla_type362", "Type 362 search radar", 18, 40, 0.8, 12)
    radar("pla_nav_radar", "Navigation and surface-search radar", 16, 10, 0.5, 28)
    radar("pla_h6j_radar", "H-6J maritime search radar", 150, 60, 1.0, 5)
    radar("pla_type1493", "Type 1493 fighter radar", 50, 85, 1.0, 3)
    radar("pla_j16_aesa", "J-16 active phased-array radar", 70, 110, 1.15, 3)
    radar("pla_kj500_radar", "KJ-500 airborne early-warning radar", 170, 300, 1.25, 4)
    radar("pla_y8q_radar", "Y-8Q maritime patrol radar", 120, 80, 1.15, 3)
    radar("pla_klc1_radar", "KLC-1 helicopter search radar", 40, 20, 0.9, 3)
    radar("pla_z20f_radar", "Z-20F surface-search radar", 50, 25, 0.95, 3)
    radar("pla_z18j_radar", "Z-18J early-warning radar", 90, 140, 0.95, 4)
    radar("pla_coastal_radar", "Coastal surveillance and targeting radar", 60, 40, 0.9, 60)
    radar("pla_ht233_radar", "HT-233 engagement radar", 20, 130, 1.1, 25)
    sonar("pla_hsjd9", "H/SJD-9 bow sonar", 12, 10, cz=True, rate=0.9)
    sonar("pla_hsjg311", "H/SJG-311 towed array", 22, 0, 120, cz=True)
    sonar("pla_hsjg206", "H/SJG-206 towed array", 18, 0, 100, cz=True)
    sonar("pla_hull_sonar_small", "Corvette bow sonar", 9, 7, rate=0.85)
    sonar("pla_towed_small", "Corvette towed array", 14, 0, 80)
    sonar("pla_type093_suite", "Type 093B sonar suite", 24, 12, cz=True, rate=1.1)
    sonar("pla_yuan_sonar", "Type 039A sonar suite", 22, 10, cz=True)
    sonar("pla_dipping_sonar", "Helicopter dipping sonar", 28, 10, 150, hover=True)
    esm("pla_esm", "Shipboard electronic support suite", 1.85, 26)
    esm("pla_air_esm", "Airborne electronic support suite", 1.7, 3)

    weapon("pla_yj18", "YJ-18 anti-ship cruise missile", "asm", ["surface"], 290, 560, 60,
           vls_pack=1, min_range_nm=4.0, base_pk=0.78, salvo_default=4, defensive_difficulty=1.45, soft_kill_resistance=1.5, altitude_m=12.0)
    weapon("pla_yj83", "YJ-83 anti-ship missile", "asm", ["surface"], 100, 480, 42,
           min_range_nm=3.0, base_pk=0.76, salvo_default=4)
    weapon("pla_yj83k", "YJ-83K air-launched anti-ship missile", "asm", ["surface"], 135, 480, 42,
           min_range_nm=3.0, base_pk=0.76, salvo_default=2)
    weapon("pla_yj12", "YJ-12 supersonic anti-ship missile", "asm", ["surface"], 216, 1700, 70,
           min_range_nm=8.0, base_pk=0.70, salvo_default=4, profile="high", altitude_m=8000.0,
           defensive_difficulty=1.8, signature_factor=0.25, soft_kill_resistance=1.3, turn_rate_deg_s=10.0)
    weapon("pla_yj12b", "YJ-12B coastal anti-ship missile", "asm", ["surface"], 216, 1700, 70,
           min_range_nm=8.0, base_pk=0.70, salvo_default=4, profile="high", altitude_m=8000.0,
           defensive_difficulty=1.8, signature_factor=0.25, soft_kill_resistance=1.3, turn_rate_deg_s=10.0)
    weapon("pla_yj21", "YJ-21 anti-ship ballistic missile", "asm", ["surface"], 600, 5000, 100,
           vls_pack=1, min_range_nm=40.0, base_pk=0.5, salvo_default=2, profile="ballistic", guidance="inertial_terminal_seeker",
           altitude_m=40000.0, defensive_difficulty=2.4, signature_factor=0.45, soft_kill_resistance=5.0,
           turn_rate_deg_s=8.0, launch_interval_s=20.0)
    weapon("pla_cj10", "CJ-10 land-attack cruise missile", "asm", ["land"], 900, 480, 55,
           vls_pack=1, min_range_nm=15.0, base_pk=0.8, salvo_default=2, profile="high", altitude_m=60.0,
           guidance="inertial_terrain_matching", defensive_difficulty=1.1, soft_kill_resistance=2.0)
    weapon("pla_hhq9b", "HHQ-9B / HQ-9B long-range surface-to-air missile", "sam", ["missile", "air"], 108, 2200, 45,
           vls_pack=1, min_range_nm=2.0, base_pk=0.52, signature_factor=0.18, altitude_m=8000.0)
    weapon("pla_hhq16", "HHQ-16 medium-range surface-to-air missile", "sam", ["missile", "air"], 30, 1900, 38,
           vls_pack=1, min_range_nm=1.5, base_pk=0.50)
    weapon("pla_hhq10", "HHQ-10 point-defence missile", "sam", ["missile", "air"], 5, 1700, 20,
           min_range_nm=0.3, base_pk=0.55)
    weapon("pla_hpj11_ciws", "H/PJ-11 eleven-barrel 30 mm CIWS", "ciws", ["missile", "air"], 1.4, 3200, 15, base_pk=0.42)
    weapon("pla_hpj12_ciws", "H/PJ-12 (Type 730) 30 mm CIWS", "ciws", ["missile", "air"], 1.2, 3000, 15, base_pk=0.38)
    weapon("pla_hpj13_30mm", "H/PJ-13 30 mm gun mount", "ciws", ["missile", "air"], 1.0, 2600, 12, base_pk=0.30)
    weapon("pla_hpj45_130mm", "H/PJ-45A 130 mm gun", "gun", ["surface"], 12, 1600, 11, base_pk=0.52)
    weapon("pla_hpj26_76mm", "H/PJ-26 76 mm gun", "gun", ["surface"], 8, 1600, 6, base_pk=0.50, salvo_default=8)
    weapon("pla_yu6", "Yu-6 heavyweight torpedo", "torpedo", ["surface", "subsurface"], 24, 50, 90,
           base_pk=0.70, run_to_enable_nm=1.0, acoustic_signature=0.7)
    weapon("pla_yu7", "Yu-7 lightweight torpedo", "torpedo", ["subsurface"], 6, 43, 55, base_pk=0.68, run_to_enable_nm=0.4)
    weapon("pla_yu8", "Yu-8 rocket-delivered ASW torpedo", "torpedo", ["subsurface"], 16, 240, 55,
           vls_pack=1, base_pk=0.66, run_to_enable_nm=0.3, guidance="rocket_delivery_abstracted")
    weapon("pla_yj82", "YJ-82 submarine-launched anti-ship missile", "asm", ["surface"], 22, 480, 35,
           min_range_nm=2.0, base_pk=0.70)
    weapon("pla_pl15", "PL-15 active-radar air-to-air missile", "aam", ["air"], 80, 2600, 45, base_pk=0.55, min_range_nm=1.5)
    weapon("pla_pl10", "PL-10 infrared air-to-air missile", "aam", ["air"], 12, 1900, 28, base_pk=0.62,
           guidance="infrared_homing", profile="direct", min_range_nm=0.3, salvo_default=1)
    weapon("pla_df21d", "DF-21D anti-ship ballistic missile", "asm", ["surface"], 800, 6000, 110,
           min_range_nm=80.0, base_pk=0.5, salvo_default=2, profile="ballistic", guidance="inertial_terminal_seeker",
           # A medium-range ballistic round spends its flight above the atmosphere: SM-3's problem,
           # and nobody else's. The single-altitude profile places it there rather than in the
           # gap between the terminal interceptors' ceiling and SM-3's floor.
           altitude_m=150000.0, defensive_difficulty=2.2, signature_factor=0.5, soft_kill_resistance=6.0,
           turn_rate_deg_s=6.0, launch_interval_s=30.0)

    platform("pla_ddg_type055", "Type 055 large destroyer (Renhai)", "DDG Type 055", "China", "destroyer",
             ["pla_type346b", "pla_type518", "pla_hsjd9", "pla_hsjg311", "pla_esm"],
             {"pla_hhq9b": 48, "pla_yj18": 16, "pla_yj21": 6, "pla_cj10": 8, "pla_yu8": 8, "pla_hhq10": 24, "pla_hpj11_ciws": 100, "pla_hpj45_130mm": 300, "pla_yu7": 6},
             length_m=180.0, displacement_t=13000.0, health=150.0, signature_factor=1.2, mast_height_m=34.0,
             fire_control_channels=8, decoy_count=16, aircraft_capacity=2, vls_cells=112,
             default_air_wing={"pla_helo_z20f": 2},
             role="Area air defence / long-range strike / group flagship",
             service_note="112 universal cells shared between HHQ-9B, YJ-18, YJ-21, CJ-10 and Yu-8; the allocation here is a scenario load of 86 cells. Two helicopters aboard. Cruiser-sized by Western reckoning; the PLAN rates it a destroyer.")
    platform("pla_ddg_type052d", "Type 052D destroyer (Luyang III)", "DDG Type 052D", "China", "destroyer",
             ["pla_type346a", "pla_type518", "pla_hsjd9", "pla_hsjg311", "pla_esm"],
             {"pla_hhq9b": 32, "pla_yj18": 8, "pla_yu8": 8, "pla_hhq10": 24, "pla_hpj12_ciws": 100, "pla_hpj45_130mm": 300, "pla_yu7": 6},
             length_m=157.0, displacement_t=7500.0, health=115.0, signature_factor=1.0, mast_height_m=30.0,
             fire_control_channels=6, decoy_count=12, aircraft_capacity=1, vls_cells=64,
             default_air_wing={"pla_helo_z9c": 1},
             role="Area air defence / surface strike",
             service_note="64 universal cells; HHQ-9B, YJ-18 and Yu-8 share them. One Z-9C aboard. The lengthened 052DL hull is not distinguished.")
    platform("pla_ffg_type054a", "Type 054A frigate (Jiangkai II)", "FFG Type 054A", "China", "frigate",
             ["pla_type382", "pla_type366", "pla_hsjd9", "pla_hsjg206", "pla_esm"],
             {"pla_hhq16": 24, "pla_yu8": 8, "pla_yj83": 8, "pla_hpj12_ciws": 80, "pla_hpj26_76mm": 300, "pla_yu7": 6},
             length_m=134.0, displacement_t=4053.0, max_speed_kn=27.0, health=90.0, signature_factor=0.85, mast_height_m=27.0,
             fire_control_channels=4, decoy_count=12, aircraft_capacity=1, vls_cells=32,
             default_air_wing={"pla_helo_z9c": 1},
             role="Escort / medium-range air defence / ASW",
             service_note="32 cells shared between HHQ-16 and Yu-8, eight YJ-83 in canisters, four MR-90 illuminators, one Z-9C. Type 366 gives over-the-horizon targeting only when it radiates.")
    platform("pla_fsg_type056a", "Type 056A corvette (Jiangdao)", "FSG Type 056A", "China", "corvette",
             ["pla_type364", "pla_hull_sonar_small", "pla_towed_small", "pla_esm"],
             {"pla_yj83": 4, "pla_hhq10": 8, "pla_hpj26_76mm": 200, "pla_yu7": 6},
             length_m=90.0, displacement_t=1500.0, max_speed_kn=25.0, health=55.0, signature_factor=0.6, mast_height_m=20.0,
             fire_control_channels=1, decoy_count=8, aircraft_capacity=0, turn_rate_deg_s=3.5,
             role="Littoral patrol / ASW screen",
             service_note="Four YJ-83, an eight-round HHQ-10 launcher, a 76 mm gun and a towed array. A landing pad but no hangar.")
    platform("pla_pgg_type022", "Type 022 missile boat (Houbei)", "PGG Type 022", "China", "fast attack craft",
             ["pla_type362", "pla_esm"],
             {"pla_yj83": 8, "pla_hpj13_30mm": 40},
             length_m=42.6, displacement_t=220.0, max_speed_kn=36.0, cruise_speed_kn=20.0, health=30.0, signature_factor=0.35,
             mast_height_m=12.0, fire_control_channels=0, decoy_count=4, turn_rate_deg_s=6.0, accel_kn_s=0.5,
             role="Littoral missile ambush",
             service_note="Wave-piercing catamaran with eight YJ-83 and a 30 mm mount. Fast, small and expendable; it relies on a picture handed to it.")
    platform("pla_cv_shandong", "Type 002 aircraft carrier (Shandong)", "CV Shandong", "China", "aircraft carrier",
             ["pla_type346a", "pla_type382", "pla_esm"],
             {"pla_hhq10": 54, "pla_hpj11_ciws": 120},
             length_m=305.0, displacement_t=66000.0, max_speed_kn=31.0, cruise_speed_kn=18.0, turn_rate_deg_s=1.0, accel_kn_s=0.1,
             health=350.0, signature_factor=2.8, mast_height_m=48.0, fire_control_channels=2, decoy_count=24,
             aircraft_capacity=36, aviation_facility="stobar", launch_spots=2, recovery_spots=1, turnaround_s=2700.0,
             default_air_wing={"pla_fighter_j15": 8, "pla_aew_z18j": 1, "pla_helo_z18f": 2, "pla_helo_z9c": 1},
             role="Ski-jump carrier / fleet air defence",
             service_note="STOBAR deck: a ski jump forward and arrester wires aft, so J-15s launch with reduced fuel and stores and recover one at a time. The represented detachment is a scenario allocation, not the full air group.")
    submarine("pla_ssn_type093b", "Type 093B attack submarine (Shang II)", "SSN Type 093B", "China",
              ["pla_type093_suite"], {"pla_yj18": 6, "pla_yu6": 14}, 110.0, 7000.0, 30.0, 0.18, 350.0,
              category="nuclear attack submarine", health=65.0, decoy_count=8,
              role="Sea denial / anti-surface torpedo and missile attack",
              service_note="Publicly assessed as quieter than the first Type 093 boats but noisier than current Western designs; the acoustic value reflects that ordering only. YJ-18 is fired from the torpedo tubes.")
    submarine("pla_ssk_type039a", "Type 039A/B submarine (Yuan)", "SSK Type 039A", "China",
              ["pla_yuan_sonar"], {"pla_yu6": 14, "pla_yj82": 4}, 77.6, 3600.0, 20.0, 0.05, 300.0,
              category="diesel-electric attack submarine", health=45.0, patrol_depth_m=120.0,
              role="Air-independent ambush / barrier",
              service_note="Stirling air-independent propulsion makes it very quiet at patrol speed; a sprint gives it away like any other boat.")
    aircraft("pla_bomber_h6j", "H-6J maritime strike bomber", "H-6J", "China", "maritime strike bomber",
             ["pla_h6j_radar", "pla_air_esm"], {"pla_yj12": 4}, 570,
             cruise_speed_kn=430.0, cruise_altitude_m=10000.0, endurance_s=21600.0, health=40.0, signature_factor=1.4,
             length_m=34.8, launch_requirement="runway", turn_rate_deg_s=3.0,
             role="Long-range anti-ship strike",
             service_note="Six YJ-12 stations; four are loaded here so a regiment's raid stays inside the game's defensive scale. It searches with its own radar and shoots on the group's picture.")
    aircraft("pla_fighter_j15", "J-15 carrier fighter (Flying Shark)", "J-15", "China", "fighter",
             ["pla_type1493", "pla_air_esm"], {"pla_pl15": 4, "pla_pl10": 2, "pla_yj83k": 2}, 1300,
             cruise_speed_kn=480.0, cruise_altitude_m=10000.0, max_altitude_m=16000.0, endurance_s=7200.0, health=25.0,
             signature_factor=0.8, length_m=21.9, launch_requirement="stobar", can_refuel=True,
             role="Carrier air defence / anti-ship strike",
             service_note="Ski-jump launch caps its fuel and stores; the short endurance is that penalty. Buddy refuelling is represented by can_refuel.")
    aircraft("pla_fighter_j16", "J-16 multirole fighter", "J-16", "China", "strike fighter",
             ["pla_j16_aesa", "pla_air_esm"], {"pla_pl15": 4, "pla_pl10": 2, "pla_yj83k": 2}, 1300,
             cruise_speed_kn=490.0, cruise_altitude_m=10000.0, max_altitude_m=16000.0, endurance_s=9000.0, health=25.0,
             signature_factor=0.8, length_m=21.9, launch_requirement="runway", can_refuel=True,
             role="Land-based counter-air and anti-ship strike")
    aircraft("pla_aew_kj500", "KJ-500 airborne early warning aircraft", "KJ-500", "China", "airborne early warning",
             ["pla_kj500_radar", "pla_air_esm"], {}, 300,
             cruise_speed_kn=260.0, cruise_altitude_m=8000.0, max_altitude_m=10000.0, endurance_s=28800.0, health=35.0,
             signature_factor=1.2, length_m=34.0, launch_requirement="runway", turn_rate_deg_s=3.0,
             role="Airborne radar picture / raid direction")
    aircraft("pla_mpa_y8q", "Y-8Q maritime patrol aircraft (KQ-200)", "Y-8Q", "China", "maritime patrol aircraft",
             ["pla_y8q_radar", "pla_air_esm"], {"pla_yu7": 4}, 330,
             cruise_speed_kn=280.0, cruise_altitude_m=3000.0, max_altitude_m=9000.0, endurance_s=28800.0, health=35.0,
             signature_factor=1.1, length_m=34.0, launch_requirement="runway", turn_rate_deg_s=3.0,
             sonobuoy_count=50, sonobuoy_sensitivity_nm=17.0, sonobuoy_life_s=3600.0,
             role="Long-endurance ASW search / surface surveillance",
             service_note="Sonobuoys stand in for its acoustic processing and magnetic anomaly detector.")
    helicopter("pla_helo_z9c", "Z-9C shipboard helicopter", "Z-9C", "China",
               ["pla_klc1_radar", "pla_dipping_sonar"], {"pla_yu7": 1}, 150,
               length_m=13.7, endurance_s=9000.0, health=16.0, sonobuoy_count=4, sonobuoy_sensitivity_nm=14.0,
               role="Shipboard ASW / over-the-horizon targeting",
               service_note="A light helicopter: one torpedo, a small dipping set and very few buoys.")
    helicopter("pla_helo_z20f", "Z-20F naval helicopter", "Z-20F", "China",
               ["pla_z20f_radar", "pla_dipping_sonar"], {"pla_yu7": 2}, 160,
               length_m=20.0, endurance_s=12600.0, health=20.0, sonobuoy_count=16, sonobuoy_sensitivity_nm=15.0,
               role="Shipboard ASW / localization")
    helicopter("pla_aew_z18j", "Z-18J early-warning helicopter", "Z-18J", "China",
               ["pla_z18j_radar", "pla_air_esm"], {}, 145,
               length_m=23.0, endurance_s=14400.0, health=22.0, signature_factor=0.3, cruise_altitude_m=3000.0,
               role="Carrier early-warning picture", service_note="A retractable radar under a big helicopter: hours of radar picture, at helicopter altitude.")
    helicopter("pla_helo_z18f", "Z-18F ASW helicopter", "Z-18F", "China",
               ["pla_z20f_radar", "pla_dipping_sonar"], {"pla_yu7": 4}, 145,
               length_m=23.0, endurance_s=14400.0, health=22.0, signature_factor=0.3, sonobuoy_count=32, sonobuoy_sensitivity_nm=15.0,
               role="Carrier ASW / buoy fields")
    platform("pla_aor_type903a", "Type 903A replenishment ship (Fuchi II)", "AOR Type 903A", "China", "replenishment ship",
             ["pla_nav_radar", "pla_esm"], {},
             length_m=178.5, displacement_t=23000.0, max_speed_kn=19.0, cruise_speed_kn=14.0, turn_rate_deg_s=1.5, accel_kn_s=0.1,
             health=130.0, signature_factor=1.8, mast_height_m=30.0, fire_control_channels=0, decoy_count=4, aircraft_capacity=2,
             default_air_wing={}, role="Underway replenishment / protected asset",
             service_note="Unarmed in this representation; its value is what the group cannot do without it.")
    site("pla_battery_yj12b", "YJ-12B coastal anti-ship battery", "Battery YJ-12B", "China", "coastal missile battery",
         ["pla_coastal_radar", "pla_esm"], {"pla_yj12b": 8}, health=60.0,
         role="Coastal anti-ship missile battery",
         service_note="A transporter-erector-launcher battery with its surveillance radar on high ground. Its reach is set by the missile; its targeting by whatever picture it holds.")
    site("pla_sam_hq9b_site", "HQ-9B surface-to-air missile site", "SAM site HQ-9B", "China", "surface-to-air missile site",
         ["pla_ht233_radar", "pla_esm"], {"pla_hhq9b": 16}, health=70.0, fire_control_channels=6, mast_height_m=25.0,
         role="Long-range air defence of an island or a coast",
         service_note="An engagement radar and four launchers; it defends everything within reach exactly as a ship's air defence does.")
    site("pla_asbm_df21d", "DF-21D anti-ship ballistic missile battery", "Battery DF-21D", "China", "ballistic missile battery",
         [], {"pla_df21d": 4}, health=50.0, signature_factor=0.8, mast_height_m=10.0,
         role="Long-range anti-carrier fires from inland",
         service_note="No sensors of its own: it fires on a classified track handed to it over the network, which is the whole operational problem it poses and the one it has.")

    # ---------- Japan Maritime, Air and Ground Self-Defense Forces ----------
    radar("jmsdf_fcs3a", "FCS-3A multifunction radar", 30, 120, 1.25, 24)
    radar("jmsdf_opy2", "OPY-2 multifunction radar", 30, 95, 1.2, 22)
    radar("jmsdf_ops50", "OPS-50 active phased-array radar", 40, 200, 1.2, 40)
    radar("jmsdf_hps106", "HPS-106 active phased-array patrol radar", 140, 200, 1.25, 3)
    radar("jmsdf_hps104", "HPS-104 helicopter search radar", 40, 45, 0.95, 3)
    radar("jasdf_japg2", "J/APG-2 active phased-array fighter radar", 60, 80, 1.1, 3)
    radar("jgsdf_coastal_radar", "Coastal surveillance radar", 50, 30, 0.9, 50)
    sonar("jmsdf_oqq24", "OQQ-24 bow sonar", 14, 12, cz=True)
    sonar("jmsdf_oqq22", "OQQ-22 bow sonar", 13, 11, cz=True)
    sonar("jmsdf_oqq25", "OQQ-25 variable-depth and towed array", 22, 9, 200, cz=True)
    sonar("jmsdf_oqq23", "OQQ-23 bow sonar", 10, 8)
    sonar("jmsdf_oqr4", "OQR-4 towed array", 24, 0, 150, cz=True)
    sonar("jmsdf_oqr3", "OQR-3 towed array", 22, 0, 150, cz=True)
    sonar("jmsdf_zqq8", "ZQQ-8 submarine sonar suite", 30, 13, cz=True, rate=1.25)
    sonar("jmsdf_hqs104", "HQS-104 dipping sonar", 34, 11, 300, hover=True, rate=1.1)
    esm("jmsdf_nolq3", "NOLQ-3 electronic warfare suite", 2.0, 28)
    esm("jasdf_esm", "Airborne warning receiver", 1.7, 3)

    weapon("jmsdf_type17_ssm", "Type 17 ship-to-ship missile", "asm", ["surface"], 110, 490, 48,
           base_pk=0.82, salvo_default=4, defensive_difficulty=1.15, altitude_m=8.0, soft_kill_resistance=1.3, signature_factor=0.1)
    weapon("jmsdf_type90_ssm", "Type 90 ship-to-ship missile", "asm", ["surface"], 81, 480, 45, base_pk=0.78, salvo_default=4)
    weapon("jmsdf_type07_vla", "Type 07 vertical-launch ASW rocket", "torpedo", ["subsurface"], 12, 240, 55,
           vls_pack=1, base_pk=0.68, run_to_enable_nm=0.4, guidance="rocket_delivery_abstracted")
    weapon("jmsdf_type12_torpedo", "Type 12 lightweight torpedo", "torpedo", ["subsurface"], 6, 45, 55, base_pk=0.70, run_to_enable_nm=0.4)
    weapon("jmsdf_type97_torpedo", "Type 97 air-launched torpedo", "torpedo", ["subsurface"], 6, 45, 55, base_pk=0.70, run_to_enable_nm=0.3)
    weapon("jmsdf_type18_torpedo", "Type 18 heavyweight torpedo", "torpedo", ["surface", "subsurface"], 27, 55, 95,
           base_pk=0.76, run_to_enable_nm=1.0, acoustic_signature=0.7)
    weapon("jasdf_asm3", "ASM-3 supersonic anti-ship missile", "asm", ["surface"], 108, 1750, 60,
           min_range_nm=8.0, base_pk=0.72, salvo_default=2, profile="high", altitude_m=8000.0,
           defensive_difficulty=1.75, signature_factor=0.2, soft_kill_resistance=1.3, turn_rate_deg_s=10.0)
    weapon("jasdf_aam4b", "AAM-4B active-radar air-to-air missile", "aam", ["air"], 54, 2400, 45, base_pk=0.55, min_range_nm=1.5)
    weapon("jasdf_aam5", "AAM-5 infrared air-to-air missile", "aam", ["air"], 10, 1900, 28, base_pk=0.63,
           guidance="infrared_homing", profile="direct", min_range_nm=0.3, salvo_default=1)
    weapon("jgsdf_type12_ssm", "Type 12 surface-to-ship missile (coastal)", "asm", ["surface"], 108, 480, 48,
           base_pk=0.80, salvo_default=4, defensive_difficulty=1.1, altitude_m=8.0, soft_kill_resistance=1.3, signature_factor=0.1)

    platform("jmsdf_ddg_maya", "Maya-class destroyer (27DDG)", "DDG Maya", "Japan", "destroyer",
             ["an_spy_1d_v", "jmsdf_oqq24", "jmsdf_oqr4", "jmsdf_nolq3"],
             {"sm2_family": 24, "sm3_family": 8, "sm6_family": 16, "essm_family": 16, "jmsdf_type17_ssm": 8, "jmsdf_type07_vla": 8,
              "mk45_mod4_gun": 300, "phalanx_ciws": 60, "jmsdf_type12_torpedo": 6},
             length_m=170.0, displacement_t=10250.0, health=125.0, signature_factor=1.05, mast_height_m=32.0,
             fire_control_channels=6, decoy_count=14, aircraft_capacity=1, vls_cells=96,
             default_air_wing={"jmsdf_helo_sh60k": 1},
             role="Aegis area air and ballistic missile defence",
             service_note="Aegis Baseline J7 with cooperative engagement; 96 cells shared between Standard, SM-3, SM-6, ESSM and the Type 07 rocket. Eight Type 17 in canisters.")
    platform("jmsdf_dd_akizuki", "Akizuki-class destroyer (19DD)", "DD Akizuki", "Japan", "destroyer",
             ["jmsdf_fcs3a", "jmsdf_oqq22", "jmsdf_oqr3", "jmsdf_nolq3"],
             {"essm_family": 32, "jmsdf_type07_vla": 16, "jmsdf_type90_ssm": 8, "mk45_mod4_gun": 300, "phalanx_ciws": 60, "jmsdf_type12_torpedo": 6},
             length_m=151.0, displacement_t=6800.0, health=100.0, signature_factor=0.9, mast_height_m=28.0,
             fire_control_channels=4, decoy_count=12, aircraft_capacity=2, vls_cells=32,
             default_air_wing={"jmsdf_helo_sh60k": 1},
             role="Escort air defence for the Aegis ships / ASW",
             service_note="Built to cover the Aegis destroyers while they look up at ballistic missiles: FCS-3A with quad-packed ESSM, and a full ASW fit.")
    platform("jmsdf_ffm_mogami", "Mogami-class frigate (FFM)", "FFM Mogami", "Japan", "frigate",
             ["jmsdf_opy2", "jmsdf_oqq25", "jmsdf_nolq3"],
             {"jmsdf_type17_ssm": 8, "ram_block2": 11, "mk45_mod4_gun": 250, "jmsdf_type12_torpedo": 6},
             length_m=133.0, displacement_t=5500.0, health=85.0, signature_factor=0.55, mast_height_m=26.0,
             fire_control_channels=2, decoy_count=12, aircraft_capacity=1,
             default_air_wing={"jmsdf_helo_sh60k": 1},
             role="Multi-role frigate / mine and littoral warfare",
             service_note="A stealthy hull with a unified mast. SeaRAM is its only missile air defence; the vertical launcher fitted to later hulls is left empty here.")
    platform("jmsdf_ddh_izumo", "Izumo-class multi-purpose destroyer (F-35B conversion)", "DDH Izumo", "Japan", "aircraft carrier",
             ["jmsdf_ops50", "jmsdf_oqq23", "jmsdf_nolq3"],
             {"ram_block2": 22, "phalanx_ciws": 60},
             length_m=248.0, displacement_t=27000.0, max_speed_kn=30.0, cruise_speed_kn=18.0, turn_rate_deg_s=1.2, accel_kn_s=0.12,
             health=300.0, signature_factor=2.5, mast_height_m=40.0, fire_control_channels=2, decoy_count=20,
             aircraft_capacity=28, aviation_facility="stovl", launch_spots=2, recovery_spots=2, turnaround_s=2700.0,
             default_air_wing={"jasdf_fighter_f35b": 6, "jmsdf_helo_sh60k": 3},
             role="STOVL carrier / ASW helicopter group / flagship",
             service_note="After the deck modification for F-35B. The fighters belong to the Air Self-Defense Force and embark as a detachment.")
    submarine("jmsdf_ssk_taigei", "Taigei-class submarine", "SSK Taigei", "Japan",
              ["jmsdf_zqq8"], {"jmsdf_type18_torpedo": 12, "rgm_84_harpoon": 6}, 84.0, 4300.0, 20.0, 0.05, 400.0,
              category="diesel-electric attack submarine", health=50.0, decoy_count=8, patrol_depth_m=150.0,
              role="Quiet barrier / anti-surface ambush",
              service_note="Lithium-ion batteries in place of air-independent propulsion: a long quiet loiter and a fast sprint, then a long charge. The sub-launched Harpoon uses the surface round's numbers.")
    aircraft("jmsdf_mpa_p1", "Kawasaki P-1 maritime patrol aircraft", "P-1", "Japan", "maritime patrol aircraft",
             ["jmsdf_hps106", "jasdf_esm"], {"jmsdf_type97_torpedo": 4, "agm_84_harpoon": 2}, 450,
             cruise_speed_kn=400.0, cruise_altitude_m=3000.0, max_altitude_m=13000.0, endurance_s=28800.0, health=35.0,
             signature_factor=1.0, length_m=38.0, launch_requirement="runway", turn_rate_deg_s=3.0,
             sonobuoy_count=70, sonobuoy_sensitivity_nm=18.0, sonobuoy_life_s=3600.0,
             role="Long-endurance ASW search / surface surveillance")
    helicopter("jmsdf_helo_sh60k", "SH-60K patrol helicopter", "SH-60K", "Japan",
               ["jmsdf_hps104", "jmsdf_hqs104"], {"jmsdf_type97_torpedo": 2}, 145,
               length_m=19.8, endurance_s=10800.0, health=20.0, sonobuoy_count=16, sonobuoy_sensitivity_nm=15.0,
               role="Shipboard ASW / localization")
    aircraft("jasdf_fighter_f35b", "F-35B Lightning II (Air Self-Defense Force)", "F-35B", "Japan", "fighter",
             ["an_apg_81", "an_asq_239"], {"aim120_family": 4, "aim9x_air": 2, "jsm_missile": 2}, 1000,
             cruise_speed_kn=500.0, cruise_altitude_m=10000.0, max_altitude_m=15000.0, endurance_s=7800.0, health=30.0,
             signature_factor=0.22, length_m=15.7, launch_requirement="stovl", can_refuel=True,
             role="Fifth-generation air defence / anti-ship strike from the Izumo deck",
             service_note="The same airframe as the Royal Navy's; the Joint Strike Missile is on order for Japan's F-35s.")
    aircraft("jasdf_fighter_f2", "Mitsubishi F-2 fighter", "F-2", "Japan", "strike fighter",
             ["jasdf_japg2", "jasdf_esm"], {"jasdf_asm3": 2, "jasdf_aam4b": 2, "jasdf_aam5": 2}, 1100,
             cruise_speed_kn=480.0, cruise_altitude_m=9000.0, max_altitude_m=15000.0, endurance_s=7800.0, health=28.0,
             signature_factor=0.7, length_m=15.5, launch_requirement="runway", can_refuel=True,
             role="Anti-ship strike / air defence",
             service_note="Built around the anti-ship mission: two ASM-3 supersonic missiles and a self-defence air-to-air load.")
    site("jgsdf_type12_battery", "Type 12 surface-to-ship missile battery", "Battery Type 12", "Japan", "coastal missile battery",
         ["jgsdf_coastal_radar", "jasdf_esm"], {"jgsdf_type12_ssm": 12}, health=60.0,
         role="Ground Self-Defense Force coastal anti-ship fires",
         service_note="The baseline Type 12; the extended-range version being fielded is not represented.")

    # ---------- Islamic Republic of Iran Navy and IRGC Navy ----------
    radar("irn_asr_radar", "Asr naval search radar", 30, 60, 0.85, 24)
    radar("irn_aws1_radar", "AWS-1 air and surface search radar", 28, 70, 0.8, 22)
    radar("irn_type352_radar", "Type 352 (Square Tie) targeting radar", 20, 30, 0.8, 12)
    radar("irn_fac_radar", "Fast-attack-craft navigation radar", 12, 6, 0.5, 6)
    radar("irn_coastal_radar", "Coastal surveillance radar", 40, 30, 0.85, 80)
    radar("irn_meraj4_radar", "Meraj-4 long-range search radar", 30, 180, 1.0, 20)
    radar("irn_mohajer_eo", "Mohajer-6 electro-optical turret", 22, 8, 1.1, 2)
    sonar("irn_hull_sonar", "Frigate bow sonar", 10, 8, rate=0.85)
    sonar("irn_mgk400", "MGK-400 Rubikon sonar suite (Project 877EKM)", 20, 10, cz=True)
    sonar("irn_ghadir_sonar", "Midget-submarine passive sonar", 6, 3, rate=0.7)
    esm("irn_esm", "Shipboard warning receiver", 1.6, 22, rate=1.0)

    weapon("irn_qader", "Qader anti-ship cruise missile", "asm", ["surface"], 108, 480, 48, base_pk=0.70, salvo_default=4, signature_factor=0.14)
    weapon("irn_noor", "Noor (C-802) anti-ship missile", "asm", ["surface"], 65, 480, 42, base_pk=0.68, salvo_default=4, signature_factor=0.14)
    weapon("irn_nasr1", "Nasr-1 light anti-ship missile", "asm", ["surface"], 19, 480, 25,
           min_range_nm=1.0, base_pk=0.60, defensive_difficulty=0.9, signature_factor=0.08, seeker_range_nm=4.0)
    weapon("irn_khalij_fars", "Khalij Fars anti-ship ballistic missile", "asm", ["surface"], 190, 4000, 90,
           min_range_nm=30.0, base_pk=0.40, salvo_default=2, profile="ballistic", guidance="inertial_electro_optical",
           altitude_m=40000.0, defensive_difficulty=1.9, signature_factor=0.5, soft_kill_resistance=5.0,
           turn_rate_deg_s=6.0, launch_interval_s=25.0)
    weapon("irn_sayyad4_sam", "Sayyad-4 long-range surface-to-air missile", "sam", ["missile", "air"], 110, 2300, 42,
           min_range_nm=3.0, base_pk=0.45, signature_factor=0.2, altitude_m=9000.0)
    weapon("irn_mehrab_sam", "Mehrab surface-to-air missile", "sam", ["missile", "air"], 20, 1800, 38, min_range_nm=1.5, base_pk=0.42)
    weapon("irn_kamand_ciws", "Kamand 30 mm CIWS", "ciws", ["missile", "air"], 1.1, 3000, 15, base_pk=0.38)
    weapon("irn_oerlikon_35mm", "Twin 35 mm gun mount", "ciws", ["missile", "air"], 1.0, 2400, 12, base_pk=0.28)
    weapon("irn_test71me", "TEST-71ME torpedo", "torpedo", ["surface", "subsurface"], 10, 40, 72, base_pk=0.66, run_to_enable_nm=0.7)
    weapon("irn_53_65ke", "53-65KE wake-homing torpedo", "torpedo", ["surface"], 10, 45, 90,
           base_pk=0.62, guidance="wake_homing_abstracted", run_to_enable_nm=0.8)

    platform("irn_ffg_moudge", "Moudge-class frigate (Sahand)", "FFG Moudge", "Iran", "frigate",
             ["irn_asr_radar", "irn_hull_sonar", "irn_esm"],
             {"irn_qader": 4, "irn_mehrab_sam": 6, "oto_76mm_gun": 200, "irn_kamand_ciws": 40},
             length_m=95.0, displacement_t=1500.0, max_speed_kn=30.0, cruise_speed_kn=15.0, health=60.0, signature_factor=0.65,
             mast_height_m=22.0, fire_control_channels=1, decoy_count=6, aircraft_capacity=1, default_air_wing={}, turn_rate_deg_s=3.2,
             role="Surface strike / flotilla flagship",
             service_note="Sahand-standard fit: four Qader, a single-rail Mehrab launcher, a 76 mm gun and a Kamand close-in mount. The landing deck is unoccupied in these missions.")
    platform("irn_ffg_alvand", "Alvand-class frigate (Vosper Mk 5)", "FFG Alvand", "Iran", "frigate",
             ["irn_aws1_radar", "irn_esm"],
             {"irn_noor": 4, "mk8_114mm_gun": 200, "irn_oerlikon_35mm": 40},
             length_m=94.5, displacement_t=1540.0, max_speed_kn=34.0, cruise_speed_kn=15.0, health=55.0, signature_factor=0.7,
             mast_height_m=22.0, fire_control_channels=0, decoy_count=4, turn_rate_deg_s=3.2,
             role="Surface patrol",
             service_note="A 1970s hull rearmed with Noor; no missile air defence since the Seacat was landed.")
    submarine("irn_ssk_kilo_877ekm", "Kilo-class submarine (Project 877EKM)", "SSK Kilo 877EKM", "Iran",
              ["irn_mgk400"], {"irn_test71me": 12, "irn_53_65ke": 6}, 72.6, 3076.0, 17.0, 0.06, 240.0,
              category="diesel-electric attack submarine", health=45.0, patrol_depth_m=100.0, has_datalink=False,
              role="Gulf of Oman ambush",
              service_note="The export Kilo of the 1990s deliveries; no cruise missiles.")
    submarine("irn_ssm_ghadir", "Ghadir-class midget submarine", "SSM Ghadir", "Iran",
              ["irn_ghadir_sonar"], {"irn_test71me": 2}, 29.0, 120.0, 11.0, 0.12, 100.0,
              category="midget submarine", health=20.0, signature_factor=0.12, mast_height_m=4.0, patrol_depth_m=40.0,
              cruise_speed_kn=5.0, has_datalink=False, decoy_count=0,
              role="Shallow-water ambush in the strait",
              service_note="Two heavyweight torpedoes, a small crew and very shallow water. Its sonar is short; its advantage is that the strait is narrow.")
    platform("irn_fac_peykaap3", "Peykaap III fast attack craft", "FAC Peykaap III", "Iran", "fast attack craft",
             ["irn_fac_radar"], {"irn_nasr1": 2},
             length_m=17.0, displacement_t=15.0, max_speed_kn=52.0, cruise_speed_kn=25.0, health=8.0, signature_factor=0.12,
             mast_height_m=6.0, fire_control_channels=0, decoy_count=0, turn_rate_deg_s=9.0, accel_kn_s=1.2,
             role="Swarm missile attack",
             service_note="Two Nasr-1 and a great deal of speed. One is a nuisance; a dozen are a defensive problem.")
    platform("irn_pgg_houdong", "Houdong-class missile boat (Thondor)", "PGG Houdong", "Iran", "fast attack craft",
             ["irn_type352_radar", "irn_esm"], {"irn_noor": 4, "irn_oerlikon_35mm": 30},
             length_m=38.6, displacement_t=205.0, max_speed_kn=35.0, cruise_speed_kn=18.0, health=25.0, signature_factor=0.35,
             mast_height_m=12.0, fire_control_channels=0, decoy_count=2, turn_rate_deg_s=6.0, accel_kn_s=0.5,
             role="Missile boat",
             service_note="Four Noor and a Square Tie targeting radar that announces itself when it is switched on.")
    aircraft("irn_uav_mohajer6", "Mohajer-6 unmanned aircraft", "Mohajer-6", "Iran", "unmanned aircraft",
             ["irn_mohajer_eo"], {}, 110,
             cruise_speed_kn=90.0, cruise_altitude_m=4500.0, max_altitude_m=5500.0, endurance_s=43200.0, health=6.0,
             signature_factor=0.08, length_m=5.7, launch_requirement="runway", decoy_count=0, fire_control_channels=1,
             role="Over-the-horizon spotting for the batteries and the boats")
    site("irn_battery_qader", "Qader / Noor coastal anti-ship battery", "Battery Qader", "Iran", "coastal missile battery",
         ["irn_coastal_radar", "irn_esm"], {"irn_qader": 8, "irn_noor": 8}, health=50.0, mast_height_m=80.0,
         role="Coastal anti-ship fires over the strait",
         service_note="Launchers in the hills behind the coast with a surveillance radar above them.")
    site("irn_asbm_khalij_fars", "Khalij Fars anti-ship ballistic missile battery", "Battery Khalij Fars", "Iran", "ballistic missile battery",
         [], {"irn_khalij_fars": 4}, health=40.0, signature_factor=0.8, mast_height_m=10.0,
         role="Ballistic anti-ship fires on a handed-off track",
         service_note="Fires on the picture its drones and coastal radars supply; it has no sensor of its own.")
    site("irn_drone_site_shahed", "One-way attack drone launch site", "Drone site", "Iran", "drone launch site",
         [], {"oneway_attack_drone": 24}, health=40.0, signature_factor=0.9, mast_height_m=8.0,
         role="Massed slow drones against shipping",
         service_note="Launch rails in the open. Each salvo is six drones; it fires on the shared picture.")
    site("irn_sam_bavar373", "Bavar-373 long-range surface-to-air missile site", "SAM site Bavar-373", "Iran", "surface-to-air missile site",
         ["irn_meraj4_radar", "irn_esm"], {"irn_sayyad4_sam": 12}, health=60.0, fire_control_channels=4, mast_height_m=20.0,
         role="Long-range air defence of the coast")

    # ---------- Russian coastal additions for the Mediterranean and the Pacific ----------
    radar("rfn_monolit_b_radar", "Monolit-B coastal targeting radar", 45, 20, 0.9, 60)
    radar("rfn_91n6_radar", "91N6 (Big Bird) acquisition radar", 30, 260, 1.1, 25)
    weapon("rfn_48n6_sam", "48N6 / S-400 long-range surface-to-air missile", "sam", ["missile", "air", "ballistic"], 130, 2600, 45,
           min_range_nm=3.0, base_pk=0.55, signature_factor=0.2, altitude_m=12000.0, intercept_max_altitude_m=30000.0)
    site("rfn_battery_bastion", "K-300P Bastion-P coastal missile battery", "Battery Bastion-P", "Russia", "coastal missile battery",
         ["rfn_monolit_b_radar", "mp_405"], {"p800_oniks": 8}, health=60.0, mast_height_m=60.0,
         role="Coastal anti-ship fires with Oniks",
         service_note="The same P-800 Oniks the Gorshkov carries, from launchers ashore, targeted by the Monolit-B radar or by the group's picture.")
    site("rfn_sam_s400_site", "S-400 surface-to-air missile site", "SAM site S-400", "Russia", "surface-to-air missile site",
         ["rfn_91n6_radar", "mp_405"], {"rfn_48n6_sam": 16}, health=70.0, fire_control_channels=6, mast_height_m=25.0,
         role="Long-range air defence of a base",
         service_note="One battalion's worth of ready missiles. The 40N6 extended-range round is not represented.")

    # ---------- Civilian ----------
    platform("civ_tanker_vlcc", "Very large crude carrier", "VLCC", "Civil", "tanker",
             ["civil_nav_radar"], {},
             length_m=333.0, displacement_t=330000.0, max_speed_kn=15.0, cruise_speed_kn=13.0, turn_rate_deg_s=0.5, accel_kn_s=0.04,
             health=220.0, signature_factor=3.5, mast_height_m=40.0, fire_control_channels=0, decoy_count=0, has_datalink=False,
             role="Protected merchant traffic",
             service_note="A generic laden tanker with an invented name. Hard to sink, easy to set alight, impossible to hide.")


def validate_and_write_manifest(scenario_ids):
    for pid, p in PLATFORMS.items():
        for s in p["sensor_ids"]:
            assert s in SENSORS or s in SHARED_SENSORS, (pid, s)
        for w in p["weapon_loadout"]:
            assert w in WEAPONS or w in SHARED_WEAPONS, (pid, w)
        for a in p.get("default_air_wing", {}):
            assert a in PLATFORMS and PLATFORMS[a]["domain"] == "air", (pid, a)
    manifest = dict(year=2027, scenario_ids=list(scenario_ids),
                    platforms=sorted(PLATFORMS), weapons=sorted(WEAPONS), sensors=sorted(SENSORS),
                    shared_weapons=sorted(SHARED_WEAPONS), shared_sensors=sorted(SHARED_SENSORS),
                    note="Explicit 2027 theatre inventory. All performance values remain gameplay estimates.")
    (ROOT / "data/theatres_2027_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    catalogue()
    m = validate_and_write_manifest([])
    print(f"2027 theatres: {len(PLATFORMS)} platforms, {len(WEAPONS)} weapons, {len(SENSORS)} sensors")
