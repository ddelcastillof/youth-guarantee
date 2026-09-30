"""
Write the SimPaths multirun config for one scenario.

multirun.jar reads its YAML from SimPaths/config, which every scenario shares,
so this rewrites the whole file each run: supported employment is switched on
for the youth guarantee scenarios and explicitly off for the others, so a run
never inherits the setting left behind by the scenario before it. Run this
after src/00_stage_scenario.py (which rejects unknown scenario names) and
immediately before src/01_run_simpaths.py.
"""

import os
import shutil
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

# Scenarios that switch the supported employment programme on
SUPPORTED_EMPLOYMENT_SCENARIOS = {"yg-scenario-only", "both-scenarios"}
SUPPORTED_EMPLOYMENT_START_YEAR = 2021
SUPPORTED_EMPLOYMENT_END_YEAR = 2026

# Seed, population, years and number of runs are left out: src/01_run_simpaths.py
# passes them as command-line flags, which override anything set here
CONFIG_TEMPLATE = """\
# Written by youth-guarantee/src/00_stage_config.py for scenario {scenario}; rewritten every run.
# Seed, population, years and runs come from src/01_run_simpaths.py's command-line flags.

model_args:
  supportedEmployment: {supported_employment}
  supportedEmploymentStartYear: {start_year}
  supportedEmploymentEndYear: {end_year}

collector_args:
  persistPersons: true
  persistBenefitUnits: true
  persistHouseholds: true
"""


def env_str(name):
    value = os.environ.get(name)
    if not value:
        sys.exit(f"Missing required environment variable: {name}")
    return value


def check_jar_supports_supported_employment(jar):
    # SimPaths sets model_args by reflection and only prints a stack trace for a
    # field it does not have, so an older jar would quietly run every scenario
    # without the programme. Checked for all scenarios, as the same change also
    # fixes the yBenUCReceivedFlag that the summary uses to find eligible people
    if not jar.is_file():
        sys.exit(f"multirun.jar not found at {jar}")
    with zipfile.ZipFile(jar) as archive:
        model_class = archive.read("simpaths/model/SimPathsModel.class")
    if b"supportedEmploymentStartYear" not in model_class:
        sys.exit(
            f"{jar} has no supported employment fields.\n"
            "Rebuild it from the SimPaths tree that carries the supported employment changes."
        )


def main():
    # Accept yg_scenario_only and yg-scenario-only, as src/00_stage_scenario.py does
    scenario = env_str("SCENARIO").replace("_", "-")
    config_name = env_str("SIMPATHS_CONFIG")

    simpaths_path = Path(env_str("SIMPATHS_PATH"))
    if not simpaths_path.is_dir():
        sys.exit(f"SIMPATHS_PATH is not a directory: {simpaths_path}")

    check_jar_supports_supported_employment(simpaths_path / "multirun.jar")

    supported_employment = scenario in SUPPORTED_EMPLOYMENT_SCENARIOS
    config = CONFIG_TEMPLATE.format(
        scenario=scenario,
        supported_employment=str(supported_employment).lower(),
        start_year=SUPPORTED_EMPLOYMENT_START_YEAR,
        end_year=SUPPORTED_EMPLOYMENT_END_YEAR,
    )

    config_path = simpaths_path / "config" / config_name
    config_path.parent.mkdir(exist_ok=True)
    config_path.write_text(config)

    # Keep a copy with the results: nothing else records whether the programme ran
    results_path = REPO_ROOT / "data" / "simpaths_output" / scenario
    results_path.mkdir(parents=True, exist_ok=True)
    shutil.copy(config_path, results_path / "simpaths_config.yml")

    state = "on" if supported_employment else "off"
    print(f"Wrote {config_path} for scenario {scenario}: supported employment {state}")


if __name__ == "__main__":
    main()
