"""
Write the SimPaths multirun config for one scenario.

multirun.jar reads its YAML from SimPaths/config, which every scenario shares,
so this rewrites the whole file each run: supported employment is switched on
for the youth guarantee scenarios and the MCS shock for the health intervention
scenarios, each explicitly off for the others, so a run never inherits the
settings left behind by the scenario before it. Unknown scenario names are
refused. Run this immediately before src/01_run_simpaths.py.
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

# Scenarios that give the policy cohort its MCS shock.
MCS_SHOCK_SCENARIOS = {"hi-only", "both-scenarios"}
MCS_SHOCK = 1.2  # SF-12 MCS points added each year

# Every other scenario switches on at least one intervention, so any name missing
# here is refused and a mistyped one cannot quietly become baseline
BASELINE = "baseline"
SCENARIOS = {BASELINE} | SUPPORTED_EMPLOYMENT_SCENARIOS | MCS_SHOCK_SCENARIOS

# Seed, population, years and number of runs are left out: src/01_run_simpaths.py
# passes them as command-line flags, which override anything set here
CONFIG_TEMPLATE = """\
# Written by youth-guarantee/src/00_stage_config.py for scenario {scenario}; rewritten every run.
# Seed, population, years and runs come from src/01_run_simpaths.py's command-line flags.

model_args:
  supportedEmployment: {supported_employment}
  supportedEmploymentStartYear: {start_year}
  supportedEmploymentEndYear: {end_year}
  policyCohort: true
  policyCohortStartYear: {start_year}
  policyCohortMcsShock: {mcs_shock}

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


def check_jar_supports_interventions(jar):
    # SimPaths sets model_args by reflection.
    if not jar.is_file():
        sys.exit(f"multirun.jar not found at {jar}")
    with zipfile.ZipFile(jar) as archive:
        model_class = archive.read("simpaths/model/SimPathsModel.class")
    for field, change in (
        (b"supportedEmploymentStartYear", "supported employment"),
        (b"policyCohortMcsShock", "policy cohort MCS shock"),
    ):
        if field not in model_class:
            sys.exit(
                f"{jar} has no {change} fields.\n"
                f"Rebuild it from the SimPaths tree that carries the {change} changes."
            )


def main():
    # Accept yg_scenario_only and yg-scenario-only, but hyphens are canonical (they name the output dirs)
    scenario = env_str("SCENARIO").replace("_", "-")
    if scenario not in SCENARIOS:
        sys.exit(
            f"Unknown scenario: {scenario}\n"
            f"Known scenarios: {', '.join(sorted(SCENARIOS))}\n"
            "Add it to SUPPORTED_EMPLOYMENT_SCENARIOS or MCS_SHOCK_SCENARIOS to run it."
        )
    config_name = env_str("SIMPATHS_CONFIG")

    simpaths_path = Path(env_str("SIMPATHS_PATH"))
    if not simpaths_path.is_dir():
        sys.exit(f"SIMPATHS_PATH is not a directory: {simpaths_path}")

    check_jar_supports_interventions(simpaths_path / "multirun.jar")

    supported_employment = scenario in SUPPORTED_EMPLOYMENT_SCENARIOS
    mcs_shock = MCS_SHOCK if scenario in MCS_SHOCK_SCENARIOS else 0.0
    config = CONFIG_TEMPLATE.format(
        scenario=scenario,
        supported_employment=str(supported_employment).lower(),
        start_year=SUPPORTED_EMPLOYMENT_START_YEAR,
        end_year=SUPPORTED_EMPLOYMENT_END_YEAR,
        mcs_shock=mcs_shock,
    )

    config_path = simpaths_path / "config" / config_name
    config_path.parent.mkdir(exist_ok=True)
    config_path.write_text(config)

    # Keep a copy with the results: nothing else records whether the interventions ran
    results_path = REPO_ROOT / "data" / "simpaths_output" / scenario
    results_path.mkdir(parents=True, exist_ok=True)
    shutil.copy(config_path, results_path / "simpaths_config.yml")

    state = "on" if supported_employment else "off"
    print(
        f"Wrote {config_path} for scenario {scenario}: "
        f"supported employment {state}, MCS shock {mcs_shock}"
    )


if __name__ == "__main__":
    main()
