"""
Run the SimPaths microsimulation in batches for two or more scenarios.
"""

import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def timestamp(suffix):
    now = datetime.now().strftime("%a %b %d %H:%M:%S %Y")
    print(f"##------ {now} ------##{suffix}", flush=True)


def env_str(name):
    value = os.environ.get(name)
    if not value:
        sys.exit(f"Missing required environment variable: {name}")
    return value


def env_int(name):
    return int(float(env_str(name)))


def list_output_dirs(path):
    if not path.is_dir():
        return []
    return sorted(path.iterdir())


def run_java(args, cwd):
    subprocess.run(["java", "-jar", "multirun.jar", *args], cwd=cwd, check=True)


def main():
    scenario = env_str("SCENARIO")
    first_year = env_int("FIRST_YEAR")
    last_year = env_int("LAST_YEAR")
    population = env_int("POPULATION")
    starting_seed = env_int("STARTING_SEED")
    runs_per_batch = env_int("RUNS_PER_BATCH")
    batches = env_int("BATCHES")
    config_name = env_str("SIMPATHS_CONFIG")

    # Guards agains missplaced SimPaths model
    simpaths_path = Path(env_str("SIMPATHS_PATH"))
    if not simpaths_path.is_dir():
        sys.exit(f"SIMPATHS_PATH is not a directory: {simpaths_path}")
    if not (simpaths_path / "multirun.jar").is_file():
        sys.exit(f"multirun.jar not found in {simpaths_path}")
    # multirun.jar reports a missing config and then exits 0, as if it had run
    if not (simpaths_path / "config" / config_name).is_file():
        sys.exit(f"{config_name} not found in {simpaths_path / 'config'}: run src/00_stage_config.py first")

    simpaths_input_path = simpaths_path / "input"
    simpaths_output_path = simpaths_path / "output"

    results_root_path = Path(__file__).resolve().parents[1] / "data" / "simpaths_output"

    timestamp(f" - Started scenario {scenario}")

    try:
        (simpaths_input_path / "input.mv.db").unlink(missing_ok=True)

        output_dirs_before = set(list_output_dirs(simpaths_output_path))

        print("Running SimPaths setup", flush=True)

        run_java([
            "-config", config_name,
            "-s", str(first_year),
            "-g", "false",
            "-DBSetup",
        ], cwd=simpaths_path)

        for batch in range(1, batches + 1):
            print(f"Running SimPaths simulation, batch {batch} of {batches}", flush=True)
            batch_seed = starting_seed + (batch - 1) * runs_per_batch
            run_java([
                "-config", config_name,
                "-r", str(batch_seed),
                "-p", str(population),
                "-n", str(runs_per_batch),
                "-s", str(first_year),
                "-e", str(last_year),
                "-g", "false",
                # Build each run's population from the input database rather than
                # saving it and reloading it for later runs: SimPaths notes that
                # the reloaded population gives slightly different results
                # (TODO in SimPathsModel), and singlerun.jar never reloads either
                "-P", "none",
            ], cwd=simpaths_path)

        output_dirs_after = list_output_dirs(simpaths_output_path)
        new_output_dirs = [
            path for path in output_dirs_after
            if path not in output_dirs_before and not path.name.endswith("logs")
        ]
        # multirun.jar also exits 0 without running when it rejects its arguments
        if not new_output_dirs:
            sys.exit(f"SimPaths wrote no new output under {simpaths_output_path}")

        results_path = results_root_path / scenario
        results_path.mkdir(parents=True, exist_ok=True)
        (results_path / "output_dirs.txt").write_text(
            "".join(f"{path}\n" for path in new_output_dirs)
        )

        timestamp(f" - Finished scenario {scenario}")
    finally:
        # Delete heavy files
        for filename in ("input.mv.db", "input.mv.db.lock"):
            (simpaths_input_path / filename).unlink(missing_ok=True)


if __name__ == "__main__":
    main()
