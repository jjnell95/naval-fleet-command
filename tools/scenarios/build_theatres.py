"""Six 2027 operations in the Western Pacific, the Gulf and the Mediterranean.

    python3 tools/scenarios/build_theatres.py     # rebuilds the 2027 theatre catalogue, then the missions

Real geography from the regional Natural Earth extractions, real class names and squadron
identities, fictional situations. Nothing here is a plan or a prediction; each mission is a
tactical problem built from public platform families. Sources and model limits: docs/THEATRES_2027.md.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geography as g
import theatres_2027 as cat
from build_scenarios import Scenario, hold, targets, protected, arrival, lost

DISCLAIMER = ("Real geography and real platform families; the conflict, the deployment and the "
              "tactical situation are fiction.")


def cvw5(fighters=6, lightnings=4, growlers=2, hawkeyes=2, asw=3, suw=1):
    """Carrier Air Wing Five, the forward-deployed wing, sized for one scenario."""
    return [
        {"platform": "usn_fighter_fa18e", "count": fighters, "squadron": "VFA-27", "callsign": "Mace", "first_modex": 201},
        {"platform": "usn_fighter_fa18f", "count": 2, "squadron": "VFA-102", "callsign": "Diamondback", "first_modex": 101},
        {"platform": "usn_fighter_f35c", "count": lightnings, "squadron": "VFA-147", "callsign": "Argonaut", "first_modex": 301},
        {"platform": "usn_ea_ea18g", "count": growlers, "squadron": "VAQ-141", "callsign": "Shadowhawk", "first_modex": 501},
        {"platform": "usn_aew_e2d", "count": hawkeyes, "squadron": "VAW-125", "callsign": "Torch", "first_modex": 601},
        {"platform": "usn_helo_mh60r", "count": asw, "squadron": "HSM-77", "callsign": "Saberhawk", "first_modex": 701},
        {"platform": "usn_helo_mh60s", "count": suw, "squadron": "HSC-12", "callsign": "Golden Falcon", "first_modex": 611},
    ]


def pla_field(j16=0, kj500=0, y8q=0, h6j=0, isr_patrol=None, strike_patrol=None):
    out = []
    if h6j:
        out.append({"platform": "pla_bomber_h6j", "count": h6j, "squadron": "Naval aviation bomber regiment", "callsign": "Badger", "first_modex": 11})
    if j16:
        out.append({"platform": "pla_fighter_j16", "count": j16, "squadron": "Naval aviation fighter regiment", "callsign": "Flanker", "first_modex": 21})
    if kj500:
        out.append({"platform": "pla_aew_kj500", "count": kj500, "squadron": "Early warning regiment", "callsign": "Eye", "first_modex": 31})
    if y8q:
        out.append({"platform": "pla_mpa_y8q", "count": y8q, "squadron": "Patrol regiment", "callsign": "Skate", "first_modex": 41})
    for entry in out:
        if isr_patrol and entry["platform"] in ("pla_aew_kj500", "pla_mpa_y8q"):
            entry["patrol_nm"] = isr_patrol
        if strike_patrol and entry["platform"] in ("pla_bomber_h6j", "pla_fighter_j16"):
            entry["patrol_nm"] = strike_patrol
    return out


# ==============================================================================================

def bashi_channel():
    s = Scenario("pacific_01_bashi_channel", "BASHI CHANNEL: SILENT PASSAGE", 21.0, 121.0, 300, 21,
                 layer=(180, 0.55), cz_range_nm=30, sea_state=3, wind_kn=14, visibility_nm=10, start="2027-04-03T19:20:00",
                 seed=41,
                 description=("A Type 093B attack submarine is trying to reach the Philippine Sea through the Bashi Channel "
                              "between Taiwan and the Batanes, screened by a Type 039A picket ahead of it. USS Vermont, a Flight IIA "
                              "destroyer with two Seahawks and a P-8A detachment at Clark hold the barrier. A maritime patrol aircraft "
                              "and a pair of J-16s from Fujian are working the channel against you. Deep water east of the sill "
                              "carries convergence zones; the ridge itself is shelf."))
    s.meta("Western Pacific", "Intermediate", 25, "ASW barrier commander",
           "Passive bearings across a strait, convergence zones at a shelf edge, buoy barriers laid by a patrol aircraft under a fighter threat",
           "Deny the Bashi Channel for six hours, or neutralize the Type 093B. A breakout into the Philippine Sea loses the watch.",
           ["Select Vermont and read its passive picture; keep it slow and under the layer until it has a bearing worth working.",
            "Put Peralta's helicopters across the channel narrows with buoys; the P-8A from Clark extends the line but has fighters to worry about.",
            "The Type 039A picket is bait as much as a screen. Do not spend torpedoes on it while the Shang is still moving east."],
           setting_note="A fictional April 2027 crisis. Real geography, real class names; the deployment and the encounter are invented.")
    s.afloat("usn_ssn_virginia", "USS Vermont (SSN 792)", "BLUE", 21.45, 122.05, 300, 6, depth_m=150, radar_on=False)
    s.afloat("usn_ddg_arleigh_burke_iia", "USS Rafael Peralta (DDG 115)", "BLUE", 21.5, 121.85, 10, 12,
             patrol=[s.xy(21.25, 121.85), s.xy(21.75, 121.85)])
    s.site("shore_air_station", "Clark Air Base", "BLUE", 15.186, 120.560,
           air_wing=[{"platform": "usn_mpa_p8a", "count": 2, "squadron": "VP-47", "callsign": "Golden Sword", "first_modex": 41,
                      "patrol_nm": [s.xy(21.3, 120.9), s.xy(21.5, 122.3)]}])
    s.afloat("pla_ssn_type093b", "Type 093B (Shang II)", "RED", 21.35, 121.55, 80, 7, depth_m=180, radar_on=False,
             ai_posture="breakout", patrol=[s.xy(21.5, 122.2)], loadout={"pla_yj18": 4, "pla_yu6": 14})
    s.afloat("pla_ssk_type039a", "Type 039A (Yuan)", "RED", 21.6, 121.4, 120, 4, depth_m=90, radar_on=False,
             patrol=[s.xy(21.45, 121.6), s.xy(21.75, 121.3)])
    s.site("shore_air_station", "Huian Air Base", "RED", 25.033, 118.821,
           air_wing=pla_field(j16=2, y8q=1,
                              isr_patrol=[s.xy(21.8, 120.8), s.xy(21.4, 122.0), s.xy(21.0, 121.2)],
                              strike_patrol=[s.xy(21.9, 121.0), s.xy(21.5, 121.9)]))
    s.d["victory_mode"] = "any"
    s.objectives("Hold the channel for six hours, or neutralize the Type 093B. The Shang crossing into the Philippine Sea, or the loss of Peralta, fails the mission.",
        [hold(6), targets(["Type 093B (Shang II)"], "Neutralize the Type 093B")],
        [protected(["USS Rafael Peralta (DDG 115)"]),
         arrival("breakout", ["Type 093B (Shang II)"], s.xy(21.5, 122.2), 6, "The Type 093B reached the Philippine Sea")])
    s.forces("US: 1 attack submarine, 1 destroyer (2 embarked helicopters), Clark patrol det  ·  PLAN: 1 nuclear attack submarine, 1 AIP submarine, Fujian patrol and fighter det")
    return s


def taiwan_strait():
    s = Scenario("pacific_02_taiwan_strait", "TAIWAN STRAIT: THE PICKET LINE", 24.0, 123.0, 560, 22,
                 layer=(150, 0.5), cz_range_nm=30, sea_state=4, wind_kn=22, visibility_nm=8, start="2027-04-07T21:30:00",
                 neutral_factions=["NEUTRAL"], seed=42,
                 description=("Ronald Reagan, Robert Smalls, the Flight III destroyer Jack H. Lucas and Rafael Peralta hold a picket east of Taiwan while a PLAN surface group led by the Type 055 "
                              "Nanchang works south along the Ryukyu chain. Two Japanese destroyers extend the line to the north-east. "
                              "A bomber raid is already airborne from the mainland, a KJ-500 is directing it, a coastal battery on the "
                              "Fujian shore covers the strait itself, and a ballistic-missile battery inland will fire at anything the "
                              "network classifies. Five hours of watch; the carrier and the cruiser must survive them."))
    s.meta("Western Pacific", "Advanced", 35, "Carrier strike group commander",
           "Layered air defence against a coordinated raid, ballistic missile defence, emissions discipline against an early-warning aircraft, and the cost of moving west into a coastal battery's reach",
           "Keep Reagan and Robert Smalls afloat for five hours. Break the raid before it launches; hold the picket east of the island.",
           ["Launch a Hawkeye and a Lightning section early; the picture is worth more than the missiles.",
            "Keep the Aegis ships between the group and the north-east, where the H-6Js and the Type 055 both are. Robert Smalls and Maya carry the SM-3s; Jack H. Lucas the SM-6s. That is the ballistic-missile defence.",
            "Everything west of Taiwan is inside the Pingtan battery's reach. The carrier does not go there."],
           setting_note="A fictional April 2027 crisis in the Western Pacific. Real geography, real class names; the deployment and the engagement are invented.")
    s.afloat("usn_cvn_nimitz", "USS Ronald Reagan (CVN 76)", "BLUE", 23.4, 124.6, 30, 20,
             air_wing=cvw5(fighters=6, lightnings=4, growlers=2, hawkeyes=2, asw=3, suw=1))
    s.afloat("usn_cg_ticonderoga", "USS Robert Smalls (CG 62)", "BLUE", 23.55, 124.85, 30, 20)
    s.afloat("usn_ddg_arleigh_burke_iia", "USS Rafael Peralta (DDG 115)", "BLUE", 23.3, 124.3, 30, 20)
    s.afloat("usn_ddg_burke_iii", "USS Jack H. Lucas (DDG 125)", "BLUE", 23.7, 124.4, 30, 20)
    s.afloat("jmsdf_ddg_maya", "JS Maya (DDG 179)", "BLUE", 24.5, 125.1, 40, 18,
             patrol=[s.xy(24.3, 124.9), s.xy(25.0, 126.2)])
    s.afloat("jmsdf_dd_akizuki", "JS Akizuki (DD 115)", "BLUE", 24.85, 125.6, 40, 18,
             patrol=[s.xy(24.6, 125.3), s.xy(25.4, 126.2)])
    s.afloat("usn_ssn_virginia", "USS Vermont (SSN 792)", "BLUE", 24.9, 124.0, 350, 8, depth_m=160, radar_on=False)
    s.site("shore_air_station", "Kadena Air Base", "BLUE", 26.356, 127.768,
           air_wing=[{"platform": "usaf_fighter_f16c", "count": 4, "squadron": "14th FS det", "callsign": "Samurai", "first_modex": 11},
                     {"platform": "usn_mpa_p8a", "count": 1, "squadron": "VP-47", "callsign": "Golden Sword", "first_modex": 41},
                     {"platform": "usn_uav_mq4c", "count": 1, "squadron": "VUP-19 det", "callsign": "Triton", "first_modex": 51}])
    # PLAN surface group coming down the Ryukyu chain toward the picket.
    s.afloat("pla_ddg_type055", "Nanchang (101)", "RED", 26.1, 124.2, 200, 18, patrol=[s.xy(24.9, 124.9), s.xy(26.3, 123.9)])
    s.afloat("pla_ddg_type052d", "Xi'an (153)", "RED", 26.25, 124.45, 200, 18, patrol=[s.xy(25.1, 125.1), s.xy(26.4, 124.2)])
    s.afloat("pla_ffg_type054a", "Xuzhou (530)", "RED", 25.95, 123.95, 200, 18, patrol=[s.xy(24.8, 124.6), s.xy(26.2, 123.6)])
    s.afloat("pla_aor_type903a", "Qiandaohu (886)", "RED", 26.5, 124.3, 200, 14, patrol=[s.xy(26.0, 124.5), s.xy(26.9, 124.1)])
    s.afloat("pla_ssn_type093b", "Type 093B (Shang II)", "RED", 23.85, 123.5, 120, 8, depth_m=170, radar_on=False,
             patrol=[s.xy(23.6, 124.6), s.xy(23.9, 123.4)])
    # The raid: already up and heading for the group, searching with its own radars.
    for i in range(4):
        s.afloat("pla_bomber_h6j", "Badger %d" % (i + 1), "RED", 27.6 + i * 0.08, 121.4 + i * 0.15, 135, 430,
                 ai_posture="breakout", patrol=[s.xy(24.4, 125.2), s.xy(23.6, 125.0)])
    s.site("shore_air_station", "Huian Air Base", "RED", 25.033, 118.821,
           air_wing=pla_field(j16=6, kj500=1,
                              isr_patrol=[s.xy(25.6, 122.4), s.xy(24.4, 123.6), s.xy(25.8, 123.4)],
                              strike_patrol=[s.xy(25.2, 123.2), s.xy(24.0, 124.4)]))
    s.site("pla_battery_yj12b", "Pingtan coastal battery", "RED", 25.52, 119.80)
    s.site("pla_asbm_df21d", "PLARF battery, Fujian interior", "RED", 24.80, 116.50)
    s.afloat("civ_merchant_bulk", "MV Keelung Express", "NEUTRAL", 24.9, 123.0, 60, 13, patrol=[s.xy(25.6, 124.8), s.xy(24.4, 121.9)])
    s.afloat("civ_merchant_bulk", "MV Pacific Meridian", "NEUTRAL", 23.0, 125.5, 20, 14, patrol=[s.xy(26.0, 126.6), s.xy(22.0, 124.8)])
    s.d["victory_mode"] = "any"
    s.objectives("Sustain a five-hour watch east of Taiwan, or neutralize Nanchang and Xi'an. Losing the carrier or the cruiser fails the mission.",
        [hold(5), targets(["Nanchang (101)", "Xi'an (153)"], "Neutralize the surface group's air-defence ships")],
        [protected(["USS Ronald Reagan (CVN 76)", "USS Robert Smalls (CG 62)", "MV Keelung Express", "MV Pacific Meridian"])])
    s.forces("US/Japan: 1 carrier (CVW-5 det), 1 cruiser, 1 Flight III and 1 Flight IIA destroyer, 2 JMSDF destroyers, 1 submarine, Kadena det  ·  PLAN: 1 Type 055, 1 Type 052D, 1 Type 054A, 1 replenishment ship, 1 submarine, 4 H-6J airborne, Huian fighter and early-warning det, 2 coastal batteries  ·  Neutral shipping")
    return s


def spratly_watch():
    s = Scenario("pacific_03_spratly", "SPRATLY WATCH: FIERY CROSS", 10.0, 114.5, 260, 23,
                 layer=(80, 0.5), cz_range_nm=0, sea_state=2, wind_kn=10, visibility_nm=12, start="2027-06-11T22:10:00",
                 neutral_factions=["NEUTRAL"], seed=43,
                 description=("A chartered merchant must reach a resupply box in the eastern Spratlys. USS Dewey and the Japanese frigate "
                              "Kumano escort her past Fiery Cross Reef, a reclaimed island with a runway, a coastal battery and a "
                              "long-range SAM site, while a Type 054A, two corvettes and three Type 022 missile boats contest the "
                              "passage. A P-8A detachment flies from Palawan. Dewey carries eight Tomahawks; whether the battery is "
                              "struck before it fires is your decision and your rules of engagement."))
    s.meta("Western Pacific", "Intermediate", 25, "Escort commander",
           "Escorting a slow merchant through littoral waters, small fast missile boats, an island base with its own air defence, and a land-attack strike as a choice rather than a reflex",
           "Get the merchant to the resupply box. Fiery Cross is a threat to be managed, not an objective; Tomahawks are for when it has become one.",
           ["Put Dewey between the merchant and Fiery Cross; keep Kumano on the merchant's disengaged side.",
            "The Type 022s are fast and small. Radar on, and hold ESSM for them rather than the corvettes.",
            "A Tomahawk salvo can silence the battery. So can staying outside its horizon."],
           setting_note="A fictional June 2027 incident. Real geography including the reclaimed outposts, real class names; the deployment and the encounter are invented.")
    s.extra_land = [
        g.reclaimed_island(9.552, 112.888, 1.7, 0.5, 67, s.lat0, s.lon0, "Fiery Cross Reef", 8.0),
        g.reclaimed_island(10.925, 114.078, 2.1, 0.9, 45, s.lat0, s.lon0, "Subi Reef", 6.0),
        g.reclaimed_island(9.905, 115.532, 3.2, 1.0, 20, s.lat0, s.lon0, "Mischief Reef", 6.0),
    ]
    s.height_m = 40  # low reef islets and Palawan's coastal plain; the chart's plateau rule would overstate them
    s.afloat("civ_merchant_bulk", "MV Lapu-Lapu Trader", "BLUE", 10.35, 116.9, 250, 12, radar_on=True,
             patrol=[s.xy(9.85, 115.9)])
    s.afloat("usn_ddg_arleigh_burke_iia", "USS Dewey (DDG 105)", "BLUE", 10.25, 116.6, 250, 12,
             loadout={"rgm_139_vla": 8, "mk45_mod4_gun": 250, "sm2_family": 24, "essm_family": 32, "phalanx_ciws": 60, "tomahawk_block_v": 8})
    s.afloat("jmsdf_ffm_mogami", "JS Kumano (FFM 2)", "BLUE", 10.45, 116.75, 250, 12)
    s.site("shore_air_station", "Antonio Bautista Air Base, Puerto Princesa", "BLUE", 9.742, 118.759,
           air_wing=[{"platform": "usn_mpa_p8a", "count": 1, "squadron": "VP-8 det", "callsign": "Fighting Tiger", "first_modex": 21}])
    s.afloat("pla_ffg_type054a", "Hengshui (572)", "RED", 9.6, 113.6, 90, 16, patrol=[s.xy(9.9, 115.2), s.xy(9.5, 113.2)])
    s.afloat("pla_fsg_type056a", "Type 056A (Jiangdao)", "RED", 9.3, 114.2, 60, 14, patrol=[s.xy(9.8, 115.4), s.xy(9.2, 113.8)])
    s.afloat("pla_fsg_type056a", "Type 056A (Jiangdao) 2", "RED", 10.7, 114.4, 120, 14, patrol=[s.xy(10.2, 115.6), s.xy(10.8, 114.1)])
    for i in range(3):
        s.afloat("pla_pgg_type022", "Type 022 boat %d" % (i + 1), "RED", 9.5 + i * 0.08, 113.0 + i * 0.1, 80, 24,
                 ai_posture="breakout", patrol=[s.xy(9.9, 115.0), s.xy(10.2, 116.2)])
    s.unit("shore_air_station", "Fiery Cross Reef airfield", "RED", s.xy(9.552, 112.888), 0, 0,
           air_wing=pla_field(j16=2, kj500=1, y8q=1,
                              isr_patrol=[s.xy(9.9, 114.6), s.xy(10.4, 116.4)],
                              strike_patrol=[s.xy(10.0, 115.4), s.xy(10.4, 116.6)]))
    s.unit("pla_battery_yj12b", "Fiery Cross coastal battery", "RED", s.xy(9.548, 112.880), 0, 0)
    s.unit("pla_sam_hq9b_site", "Fiery Cross SAM site", "RED", s.xy(9.556, 112.895), 0, 0)
    s.afloat("civ_fishing_trawler", "FV Bagong Pag-asa", "NEUTRAL", 10.1, 115.7, 300, 6, patrol=[s.xy(10.4, 115.2), s.xy(9.9, 116.0)])
    s.afloat("civ_merchant_bulk", "MV Sabah Star", "NEUTRAL", 8.9, 116.4, 330, 13, patrol=[s.xy(11.0, 115.6), s.xy(8.2, 116.8)])
    s.objectives("Escort MV Lapu-Lapu Trader into the resupply box. Losing her or Dewey fails the mission; neutral traffic is protected.",
        [arrival("resupply", ["MV Lapu-Lapu Trader"], s.xy(9.85, 115.9), 6, "Lapu-Lapu Trader reached the resupply box")],
        [protected(["MV Lapu-Lapu Trader", "USS Dewey (DDG 105)", "FV Bagong Pag-asa", "MV Sabah Star"])])
    s.forces("US/Japan: 1 destroyer, 1 frigate, 1 chartered merchant, Palawan patrol det  ·  PLAN: 1 frigate, 2 corvettes, 3 missile boats, Fiery Cross airfield, coastal battery and SAM site  ·  Neutral traffic")
    return s


def sea_of_japan():
    s = Scenario("pacific_04_sea_of_japan", "SEA OF JAPAN: NORTHERN GUARD", 41.0, 135.5, 520, 24,
                 layer=(120, 0.6), cz_range_nm=30, sea_state=5, wind_kn=28, visibility_nm=6, start="2027-03-02T20:30:00",
                 seed=44,
                 description=("A Russian Pacific Fleet surface group led by the cruiser Varyag has sortied from Vladivostok toward the "
                              "Tsugaru Strait overnight and is already well out into the Japan Basin, with a Kilo ahead of it and Backfires on call at Kamenny Ruchey. You command the Izumo group: "
                              "the carrier with an Air Self-Defense Force F-35B detachment, the Aegis destroyer Maya, Akizuki, the frigate "
                              "Kumano and the submarine Taigei, with P-1s at Hachinohe, F-2s at Misawa and a Type 12 battery on the Oga "
                              "coast. Hold the group away from the strait for five hours or neutralize it."))
    s.meta("Western Pacific", "Advanced", 30, "Escort flotilla commander",
           "Fighting a Japanese task group: STOVL fighters, Aegis ballistic and air defence, quiet lithium-ion submarine tactics, land-based anti-ship strike and a coastal battery as part of the same picture",
           "Deny the Tsugaru approaches to Varyag's group for six hours, or neutralize Varyag and Marshal Shaposhnikov. Izumo and Maya must survive.",
           ["Launch a P-1 from Hachinohe toward the group's last position; keep the F-35Bs for the Backfires, not for the ships.",
            "Get the Misawa Hawkeye and a pair of F-35Bs north-east early. The Backfires release from three hundred miles; they have to be met before that, not after.",
            "Taigei is quiet and slow. Put her across the group's track early and leave her alone."],
           setting_note="A fictional March 2027 crisis in the Sea of Japan. Real geography, real class and squadron names; the deployment and the encounter are invented.")
    s.afloat("jmsdf_ddh_izumo", "JS Izumo (DDH 183)", "BLUE", 40.3, 136.2, 20, 18,
             air_wing=[{"platform": "jasdf_fighter_f35b", "count": 6, "squadron": "301 Sqn det", "callsign": "Lightning", "first_modex": 11},
                       {"platform": "jmsdf_helo_sh60k", "count": 3, "squadron": "Fleet Air Wing 21", "callsign": "Seahawk", "first_modex": 21}])
    s.afloat("jmsdf_ddg_maya", "JS Maya (DDG 179)", "BLUE", 40.5, 136.5, 20, 18)
    s.afloat("jmsdf_dd_akizuki", "JS Akizuki (DD 115)", "BLUE", 40.15, 135.9, 20, 18)
    s.afloat("jmsdf_ffm_mogami", "JS Kumano (FFM 2)", "BLUE", 40.6, 135.8, 20, 18, radar_on=False)
    s.afloat("jmsdf_ssk_taigei", "JS Taigei (SS 513)", "BLUE", 42.0, 134.2, 330, 5, depth_m=140, radar_on=False)
    s.site("shore_air_station", "Hachinohe Air Base", "BLUE", 40.556, 141.466,
           air_wing=[{"platform": "jmsdf_mpa_p1", "count": 2, "squadron": "Fleet Air Wing 2", "callsign": "Kawasaki", "first_modex": 51}])
    s.site("shore_air_station", "Misawa Air Base", "BLUE", 40.703, 141.368,
           air_wing=[{"platform": "jasdf_fighter_f2", "count": 4, "squadron": "3rd Sqn", "callsign": "Viper Zero", "first_modex": 61},
                     {"platform": "usn_aew_e2d", "count": 1, "squadron": "JASDF 601 Sqn", "callsign": "Hawkeye", "first_modex": 71,
                      "patrol_nm": [s.xy(41.6, 136.8), s.xy(42.4, 136.0)]}])
    s.site("jgsdf_type12_battery", "Oga coastal battery", "BLUE", 39.9, 139.8)
    s.afloat("rfn_cg_slava", "Varyag (011)", "RED", 42.0, 135.6, 110, 24, ai_posture="breakout",
             patrol=[s.xy(41.4, 139.6)])
    s.afloat("rfn_ddg_udaloy", "Marshal Shaposhnikov (543)", "RED", 42.1, 135.85, 110, 24, ai_posture="breakout",
             patrol=[s.xy(41.5, 139.7)])
    s.afloat("rfn_fsg_steregushchiy", "Gremyashchiy (337)", "RED", 41.9, 135.35, 110, 24, ai_posture="breakout",
             patrol=[s.xy(41.3, 139.5)])
    s.afloat("rfn_ssk_kilo", "Petropavlovsk-Kamchatsky (B-274)", "RED", 41.8, 135.2, 150, 5, depth_m=120, radar_on=False,
             patrol=[s.xy(41.2, 136.6), s.xy(41.9, 134.6)])
    s.site("shore_air_station", "Kamenny Ruchey", "RED", 49.235, 140.194,
           air_wing=[{"platform": "rfn_bomber_tu22m3", "count": 3, "squadron": "Naval missile aviation regiment", "callsign": "Backfire", "first_modex": 21,
                      "patrol_nm": [s.xy(42.4, 137.8), s.xy(40.6, 136.4)]},
                     {"platform": "rfn_mpa_tu142", "count": 1, "squadron": "Long-range ASW regiment", "callsign": "Bear", "first_modex": 71,
                      "patrol_nm": [s.xy(42.6, 136.0), s.xy(40.4, 137.4), s.xy(41.6, 134.8)]},
                     {"platform": "rfn_mpa_il38n", "count": 1, "squadron": "Naval aviation ASW squadron", "callsign": "May", "first_modex": 51,
                      "patrol_nm": [s.xy(41.4, 135.6), s.xy(42.2, 134.4)]}])
    s.d["victory_mode"] = "any"
    s.objectives("Keep Varyag's group out of the Tsugaru approaches for six hours, or neutralize Varyag and Marshal Shaposhnikov. Izumo or Maya lost, or Varyag reaching the strait, fails the mission.",
        [hold(6), targets(["Varyag (011)", "Marshal Shaposhnikov (543)"], "Neutralize the cruiser and the destroyer")],
        [protected(["JS Izumo (DDH 183)", "JS Maya (DDG 179)"]),
         arrival("tsugaru", ["Varyag (011)"], s.xy(41.4, 139.6), 8, "Varyag reached the Tsugaru approaches")])
    s.forces("Japan: 1 STOVL carrier (F-35B det), 1 Aegis destroyer, 1 destroyer, 1 frigate, 1 submarine, Hachinohe and Misawa dets with an E-2D, 1 coastal battery  ·  Russia: 1 cruiser, 1 destroyer, 1 corvette, 1 submarine, Kamenny Ruchey bomber and patrol det")
    return s


def hormuz():
    s = Scenario("gulf_01_hormuz", "STRAIT OF HORMUZ: TANKER TRANSIT", 26.3, 56.6, 240, 25,
                 layer=(30, 0.3), cz_range_nm=0, sea_state=2, wind_kn=12, visibility_nm=9, start="2027-05-19T02:00:00",
                 neutral_factions=["NEUTRAL"], seed=45,
                 description=("Three laden tankers must clear the Strait of Hormuz into the Gulf of Oman. A US destroyer, a British "
                              "Type 45 and a French frigate escort them past Qeshm and Larak against an IRGC swarm, a midget submarine "
                              "in the lane, a Kilo waiting outside, drones from the coast and a coastal battery above Bandar Abbas, with "
                              "a ballistic-missile battery behind it that fires on whatever the drones report. A P-8A detachment at "
                              "Al Dhafra can help. The destroyer's Tomahawks can reach the battery; your rules of engagement decide "
                              "whether they do before it fires."))
    s.meta("Persian Gulf", "Advanced", 30, "Escort group commander",
           "Convoy defence in confined water: fast-attack-craft swarms, one-way attack drones, a midget submarine, shore-based cruise and ballistic missiles, and neutral traffic everywhere",
           "Bring at least two of the three tankers out into the Gulf of Oman. The escorts survive by shooting early; the tankers survive by your station-keeping.",
           ["Put Paul Ignatius ahead of the convoy in the outbound lane and Duncan on the Iranian side; Languedoc's sonar belongs astern where the Ghadir waits.",
            "The swarm comes from Qeshm at fifty knots. Radar on, weapons free, and guns for anything inside five miles.",
            "The Khalij Fars battery fires on drone reports. Killing the drones early is cheaper than stopping the missiles late."],
           setting_note="A fictional May 2027 crisis. Real geography and traffic lanes, real class names; the deployment and the engagement are invented.")
    convoy = [("MT Gulf Horizon", 26.45, 55.92), ("MT Ras Laffan Pride", 26.42, 55.80), ("MT Aegean Dawn", 26.48, 55.72)]
    exit_box = s.xy(25.55, 57.5)
    route = [s.xy(26.5, 56.35), s.xy(26.25, 56.85), exit_box]
    for name, lat, lon in convoy:
        s.afloat("civ_tanker_vlcc", name, "BLUE", lat, lon, 100, 13, radar_on=True, patrol=route)
    s.afloat("usn_ddg_arleigh_burke_iia", "USS Paul Ignatius (DDG 117)", "BLUE", 26.47, 56.08, 100, 13,
             loadout={"rgm_139_vla": 8, "mk45_mod4_gun": 250, "sm2_family": 24, "essm_family": 32, "phalanx_ciws": 60, "tomahawk_block_v": 8})
    s.afloat("rn_ddg_type45", "HMS Duncan (D 37)", "BLUE", 26.52, 55.98, 100, 13)
    s.afloat("fra_ffg_fremm", "FS Languedoc (D 653)", "BLUE", 26.38, 55.62, 100, 13)
    s.site("shore_air_station", "Al Dhafra Air Base", "BLUE", 24.248, 54.548,
           air_wing=[{"platform": "usn_mpa_p8a", "count": 1, "squadron": "VP-45 det", "callsign": "Pelican", "first_modex": 31}])
    for i in range(6):
        s.afloat("irn_fac_peykaap3", "Peykaap %d" % (i + 1), "RED", 26.98 + (i % 2) * 0.02, 56.28 + i * 0.025, 200, 30,
                 ai_posture="breakout", patrol=[s.xy(26.95, 56.6), s.xy(26.65, 56.62), s.xy(26.3, 56.8)])
    s.afloat("irn_pgg_houdong", "Thondor 1", "RED", 27.05, 56.2, 120, 18, patrol=[s.xy(26.96, 56.62), s.xy(26.62, 56.7)])
    s.afloat("irn_pgg_houdong", "Thondor 2", "RED", 27.03, 56.12, 120, 18, patrol=[s.xy(26.97, 56.58), s.xy(26.66, 56.6)])
    s.afloat("irn_ssm_ghadir", "Ghadir", "RED", 26.46, 56.55, 270, 3, depth_m=28, radar_on=False, patrol=[s.xy(26.5, 56.3), s.xy(26.4, 56.7)])
    s.afloat("irn_ssk_kilo_877ekm", "Tareq (901)", "RED", 25.7, 57.25, 300, 4, depth_m=100, radar_on=False,
             patrol=[s.xy(25.9, 57.0), s.xy(25.5, 57.6)])
    s.afloat("irn_ffg_moudge", "Dena (75)", "RED", 26.2, 56.9, 250, 14, patrol=[s.xy(26.0, 57.1), s.xy(26.35, 56.6)])
    s.afloat("irn_ffg_alvand", "Alborz (72)", "RED", 25.5, 57.7, 300, 14, patrol=[s.xy(25.35, 57.95), s.xy(25.45, 57.4)])
    s.site("irn_battery_qader", "Qeshm coastal battery", "RED", 26.76, 55.88)
    s.site("irn_asbm_khalij_fars", "Bandar Abbas ballistic battery", "RED", 27.30, 56.42)
    s.site("irn_drone_site_shahed", "Minab drone site", "RED", 27.10, 56.95)
    s.site("irn_sam_bavar373", "Bandar Abbas SAM site", "RED", 27.25, 56.20)
    s.site("shore_air_station", "Bandar Abbas Air Base", "RED", 27.22, 56.37,
           air_wing=[{"platform": "irn_uav_mohajer6", "count": 2, "squadron": "UAV group", "callsign": "Mohajer", "first_modex": 81,
                      "patrol_nm": [s.xy(26.5, 56.4), s.xy(26.2, 57.0), s.xy(26.6, 56.0)]}])
    s.afloat("civ_merchant_bulk", "MV Khor Fakkan Trader", "NEUTRAL", 26.15, 56.75, 300, 12, patrol=[s.xy(26.45, 56.45), s.xy(26.4, 55.9), s.xy(26.35, 55.0)])
    s.afloat("civ_fishing_trawler", "Dhow Al Noor", "NEUTRAL", 26.4, 56.45, 60, 6, patrol=[s.xy(26.6, 56.6), s.xy(26.3, 56.2)])
    s.objectives("Bring at least two tankers into the Gulf of Oman box within ten hours. Losing all three, or Paul Ignatius, fails the mission; neutral traffic is protected.",
        [arrival("transit", [c[0] for c in convoy], exit_box, 8, "Two tankers cleared the strait")],
        [{"id": "convoy_lost", "type": "all_units_lost", "callsigns": [c[0] for c in convoy], "text": "Every tanker was lost"},
         protected(["USS Paul Ignatius (DDG 117)", "MV Khor Fakkan Trader", "Dhow Al Noor"]),
         {"id": "deadline", "type": "time_elapsed", "seconds": 36000, "text": "The transit window closed"}])
    s.d["objectives"]["victory"][0]["count"] = 2
    s.forces("US/UK/France: 1 destroyer, 1 air-defence destroyer, 1 frigate, 3 tankers, Al Dhafra patrol det  ·  Iran: 6 fast attack craft, 2 missile boats, 1 midget submarine, 1 Kilo, 2 frigates, 2 UAVs, coastal, ballistic, drone and SAM sites  ·  Neutral traffic")
    return s


def tartus_line():
    s = Scenario("med_01_tartus", "EASTERN MEDITERRANEAN: THE TARTUS LINE", 34.4, 33.8, 300, 26,
                 layer=(90, 0.5), cz_range_nm=25, sea_state=3, wind_kn=14, visibility_nm=10, start="2027-10-06T04:10:00",
                 neutral_factions=["NEUTRAL"], seed=46,
                 description=("Mistral must reach a holding box south of Cyprus with the Charles de Gaulle group screening her, on a sea "
                              "lane full of neutral traffic. The Russian Mediterranean squadron is at sea between you and the Syrian coast: "
                              "the frigate Admiral Grigorovich with Kalibr, a Buyan-M, the Kilo Krasnodar, Su-34s and Su-35s at Khmeimim "
                              "under an S-400 umbrella, and a Bastion battery above Tartus. Typhoons and a Poseidon fly from Akrotiri."))
    s.meta("Mediterranean", "Advanced", 30, "Task force commander",
           "Screening a high-value unit through neutral traffic, fighting a land-based air threat under a long-range SAM umbrella, and a coastal battery that only shows itself when it radiates",
           "Deliver Mistral to the box south of Cyprus. Identify before engaging; the lane is full of ships that are nobody's enemy.",
           ["Launch an E-2C and a Rafale section; keep them west of the Syrian coast and its S-400.",
            "Suffren goes east first, to find Krasnodar before Krasnodar finds Mistral.",
            "The Bastion battery reaches 130 miles when it has a track. Stay outside its radar, or make sure nothing else is giving it one."],
           setting_note="A fictional October 2027 crisis. Real geography, real class and unit names; the deployment and the engagement are invented.")
    s.afloat("fra_lhd_mistral", "FS Mistral (L 9013)", "BLUE", 34.15, 31.4, 80, 16, patrol=[s.xy(33.85, 33.6)])
    s.afloat("fra_cvn_charles_de_gaulle", "FS Charles de Gaulle (R 91)", "BLUE", 34.35, 31.8, 80, 18,
             air_wing=[{"platform": "fra_fighter_rafale_m", "count": 6, "squadron": "Flottille 11F", "callsign": "Rafale", "first_modex": 11},
                       {"platform": "fra_aew_e2c", "count": 1, "squadron": "Flottille 4F", "callsign": "Hawkeye", "first_modex": 1},
                       {"platform": "nato_helo_nh90_nfh", "count": 2, "squadron": "Flottille 33F", "callsign": "Caiman", "first_modex": 31},
                       {"platform": "fra_helo_panther", "count": 1, "squadron": "Flottille 36F", "callsign": "Panther", "first_modex": 41}])
    s.afloat("ita_ddg_horizon", "ITS Andrea Doria (D 553)", "BLUE", 34.45, 32.15, 80, 18)
    s.afloat("fra_ffg_fremm", "FS Provence (D 652)", "BLUE", 34.05, 31.95, 80, 18, radar_on=False)
    s.afloat("fra_ssn_suffren", "FS Suffren (S 635)", "BLUE", 34.5, 32.6, 90, 10, depth_m=160, radar_on=False)
    s.site("shore_air_station", "RAF Akrotiri", "BLUE", 34.590, 32.988,
           air_wing=[{"platform": "raf_fighter_typhoon", "count": 4, "squadron": "903 EAW", "callsign": "Typhoon", "first_modex": 21},
                     {"platform": "usn_mpa_p8a", "count": 1, "squadron": "120 Sqn det", "callsign": "Poseidon", "first_modex": 1}])
    s.afloat("rfn_ffg_admiral_grigorovich", "Admiral Grigorovich (494)", "RED", 34.7, 34.9, 240, 16,
             patrol=[s.xy(34.2, 34.2), s.xy(34.9, 35.2)])
    s.afloat("rfn_fsg_buyan_m", "Vyshny Volochyok (609)", "RED", 34.85, 35.15, 240, 14, patrol=[s.xy(34.4, 34.5), s.xy(35.0, 35.4)])
    s.afloat("rfn_ssk_kilo", "Krasnodar (B-265)", "RED", 34.3, 34.1, 250, 5, depth_m=110, radar_on=False,
             patrol=[s.xy(33.9, 33.7), s.xy(34.5, 34.4)])
    s.site("shore_air_station", "Khmeimim Air Base", "RED", 35.401, 35.949,
           air_wing=[{"platform": "rfn_strike_su34", "count": 4, "squadron": "Aviation group", "callsign": "Fullback", "first_modex": 21,
                      "patrol_nm": [s.xy(34.6, 34.6), s.xy(34.0, 33.4)]},
                     {"platform": "rfn_fighter_su35s", "count": 2, "squadron": "Aviation group", "callsign": "Flanker", "first_modex": 41,
                      "patrol_nm": [s.xy(34.7, 34.4), s.xy(34.3, 33.6)]},
                     {"platform": "rfn_mpa_il38n", "count": 1, "squadron": "Aviation group", "callsign": "May", "first_modex": 51,
                      "patrol_nm": [s.xy(34.4, 34.0), s.xy(33.9, 32.8), s.xy(34.8, 33.4)]}])
    s.site("rfn_battery_bastion", "Tartus coastal battery", "RED", 34.87, 35.93)
    s.site("rfn_sam_s400_site", "Khmeimim SAM site", "RED", 35.38, 35.98)
    s.afloat("civ_merchant_bulk", "MV Piraeus Voyager", "NEUTRAL", 34.0, 32.6, 100, 13, patrol=[s.xy(34.4, 35.4), s.xy(33.6, 30.6)])
    s.afloat("civ_merchant_bulk", "MV Port Said Trader", "NEUTRAL", 33.6, 33.4, 320, 12, patrol=[s.xy(34.7, 34.7), s.xy(32.2, 31.8)])
    s.afloat("civ_tanker_vlcc", "MT Levant Crown", "NEUTRAL", 34.5, 33.0, 265, 12, patrol=[s.xy(34.9, 34.9), s.xy(34.1, 31.3)])
    s.objectives("Bring Mistral into the holding box south of Cyprus. Losing Mistral or Charles de Gaulle fails the mission; neutral traffic is protected.",
        [arrival("holding_box", ["FS Mistral (L 9013)"], s.xy(33.85, 33.6), 8, "Mistral reached the holding box")],
        [protected(["FS Mistral (L 9013)", "FS Charles de Gaulle (R 91)", "MV Piraeus Voyager", "MV Port Said Trader", "MT Levant Crown"])])
    s.forces("France/Italy/UK: 1 carrier (air group det), 1 amphibious ship, 1 destroyer, 1 frigate, 1 submarine, Akrotiri det  ·  Russia: 1 frigate, 1 missile corvette, 1 submarine, Khmeimim strike and patrol det, coastal battery and SAM site  ·  Neutral traffic")
    return s


BUILDERS = [bashi_channel, taiwan_strait, spratly_watch, sea_of_japan, hormuz, tartus_line]


if __name__ == "__main__":
    cat.catalogue()
    ids = []
    for build in BUILDERS:
        s = build()
        s.write()
        ids.append(s.d["id"])
    cat.validate_and_write_manifest(ids)
    print(f"2027 theatres: {len(ids)} missions, {len(cat.PLATFORMS)} platforms, {len(cat.WEAPONS)} weapons, {len(cat.SENSORS)} sensors")
