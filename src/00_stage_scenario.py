"""
Stage SimPaths/input for one scenario.

Restores the pristine input files, then applies that scenario's mutation, so a
run never inherits the inputs left behind by the scenario before it. Run this
immediately before src/01_run_simpaths.py.
"""

import hashlib
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from scenarios import hi_only  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[1]
PRISTINE_PATH = REPO_ROOT / "data" / "scenario_inputs" / "pristine"

# Scenarios with no entry here run on the pristine inputs; "baseline" is the
# only such scenario allowed, so a mistyped name cannot quietly become baseline
SCENARIO_MUTATIONS = {
    "hi-only": hi_only.apply,
}

BASELINE = "baseline"


def env_str(name):
    value = os.environ.get(name)
    if not value:
        sys.exit(f"Missing required environment variable: {name}")
    return value


def sha256(path):
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def pristine_files():
    if not PRISTINE_PATH.is_dir():
        sys.exit(
            f"Pristine inputs not found at {PRISTINE_PATH}\n"
            "Run slurm/00_init_pristine_inputs.sh once before staging any scenario."
        )
    files = sorted(p for p in PRISTINE_PATH.iterdir() if p.suffix == ".xlsx")
    if not files:
        sys.exit(f"No pristine input files in {PRISTINE_PATH}")
    return files


def main():
    # Accept hi_only and hi-only, but hyphens are canonical (they name the output dirs)
    scenario = env_str("SCENARIO").replace("_", "-")

    simpaths_path = Path(env_str("SIMPATHS_PATH"))
    if not simpaths_path.is_dir():
        sys.exit(f"SIMPATHS_PATH is not a directory: {simpaths_path}")
    simpaths_input_path = simpaths_path / "input"

    # Restore first, so even an unrecognised scenario leaves the inputs in a known state
    restored = []
    for source in pristine_files():
        destination = simpaths_input_path / source.name
        shutil.copy(source, destination)
        restored.append(destination)
    print(f"Restored {len(restored)} pristine input files into {simpaths_input_path}")

    if scenario != BASELINE and scenario not in SCENARIO_MUTATIONS:
        known = ", ".join([BASELINE, *sorted(SCENARIO_MUTATIONS)])
        sys.exit(
            f"Unknown scenario: {scenario}\n"
            f"Known scenarios: {known}\n"
            "Register a mutation in SCENARIO_MUTATIONS to add a new one."
        )

    mutation = SCENARIO_MUTATIONS.get(scenario)
    if mutation is None:
        print(f"Scenario {scenario} runs on the pristine inputs, nothing to mutate")
    else:
        mutation(simpaths_input_path)

    # Record what the model will actually read
    results_path = REPO_ROOT / "data" / "simpaths_output" / scenario
    results_path.mkdir(parents=True, exist_ok=True)
    (results_path / "staged_inputs.txt").write_text(
        "".join(f"{sha256(path)}  {path.name}\n" for path in restored)
    )

    # Force -DBSetup to rebuild against the inputs we just staged
    for filename in ("input.mv.db", "input.mv.db.lock"):
        (simpaths_input_path / filename).unlink(missing_ok=True)

    print(f"Staged scenario {scenario}")


if __name__ == "__main__":
    main()
