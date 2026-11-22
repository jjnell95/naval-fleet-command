"""Run every data builder in the order they depend on each other.

    python3 tools/scenarios/rebuild_all.py            # regenerate data/
    python3 tools/scenarios/rebuild_all.py --check    # regenerate, then fail if git sees a change

The order matters: the training exercises copy Northern Passage's chart, the operation pass
re-encodes every mission, and the recognition brief reads the platform files the catalogue
builders have just written. `--check` is the test that data/ is still what the builders write:
a hand edit under data/ that the builders do not carry shows up as a difference.
Needs shapely and pyshp (requirements.txt).
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SEQUENCE = ["build_scenarios.py", "build_northern_passage.py", "build_cold_war.py", "build_theatres.py",
            "operation_design.py", "build_command_training.py"]


def main():
    for name in SEQUENCE:
        print("== " + name, flush=True)
        subprocess.run([sys.executable, str(HERE / name)], cwd=HERE, check=True)
    if "--check" in sys.argv[1:]:
        changed = subprocess.run(["git", "status", "--porcelain", "--", "data"], cwd=ROOT,
                                 capture_output=True, text=True, check=True).stdout
        if changed:
            print("data/ differs from what the builders write:\n" + changed)
            return 1
        print("data/ is exactly what the builders write.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
