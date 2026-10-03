"""Authored recognition intelligence for the fictional shipped operations.

This catalogue library never queries spawned units or hidden positions. A match still requires
sensor evidence. National origin alone is not hostile intent outside these briefed wars.
Civil shipping has no blanket affiliation assertion: reports must establish its identity.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
ALLIED = {"USA", "UK", "Norway", "France", "Germany", "Italy", "Spain", "Denmark", "Japan", "USA / Spain / Italy"}
OPPOSITION = {
    "aegis_bastion": {"Russia"}, "northern_passage": {"Russia"},
    "cold_war_01_convoy": {"USSR"}, "cold_war_02_barrier": {"USSR"},
    "cold_war_03_carrier": {"USSR"}, "gulf_01_hormuz": {"Iran"},
    "med_01_tartus": {"Russia"}, "pacific_02_taiwan_strait": {"China"},
    "training_missile_defence": {"Russia"}, "training_asw": {"Russia"},
}


def apply_recognition_brief(scenario):
    opponents = OPPOSITION.get(scenario["id"])
    if opponents is None:
        return scenario
    blue, red = {}, {}
    for path in sorted((ROOT / "data/platforms").rglob("*.tres")):
        text = path.read_text()
        ident = re.search(r'^id = "([^"]+)"', text, re.M)
        nation = re.search(r'^nation = "([^"]+)"', text, re.M)
        if not ident or not nation:
            continue
        key, country = ident[1], nation[1]
        if country in opponents:
            blue[key], red[key] = "HOSTILE", "FRIENDLY"
        elif country in ALLIED:
            blue[key], red[key] = "FRIENDLY", "HOSTILE"
    scenario["recognition_affiliations"] = {"BLUE": blue, "RED": red}
    scenario["recognition_note"] = (
        "In this fictional operation, the brief declares recognized opposing military families "
        "hostile. Sensor-library evidence is required; an unidentified radar return is not hostile. "
        "The brief contains no positions, exact callsigns, or guarantee that a listed type is present."
    )
    return scenario
