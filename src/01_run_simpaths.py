"""
Run the SimPaths microsimulation in batches for one scenario.

A scenario is the SimPaths settings in config/<scenario>.yml, copied into
SimPaths/config for multirun.jar to read. Seed, population, years and number
of runs are left out of those files: they come from the command-line flags here.
"""

import os
import re
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


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


def model_arg_keys(config):
    # The keys indented under model_args:, up to the next top-level key
    keys, in_model_args = [], False
    for line in config.splitlines():
        if line[:1].strip() and not line.startswith("#"):
            in_model_args = line.startswith("model_args:")
        elif in_model_args and (match := re.match(r"\s+(\w+):", line)):
            keys.append(match.group(1))
    return keys


def check_jar_has_model_args(jar, config_path):
    # SimPaths sets each model_args key on the SimPathsModel field of the same name,
    # by reflection. A key that names no field only prints a stack trace and the run
    # goes ahead without it, so every key must be a name in the class: its constant
    # pool holds each one as a 0x01 tag, a two-byte length, then the name.
    with zipfile.ZipFile(jar) as archive:
        model_class = archive.read("simpaths/model/SimPathsModel.class")
    for key in model_arg_keys(config_path.read_text()):
        name = key.encode()
        if b"\x01" + len(name).to_bytes(2, "big") + name not in model_class:
            sys.exit(
                f"{jar} has no SimPathsModel field named {key}.\n"
                f"Rename the key in {config_path} to match the field, or rebuild the jar "
                "from the SimPaths tree that carries it."
            )


def main():
    scenario = env_str("SCENARIO")
    first_year = env_int("FIRST_YEAR")
    last_year = env_int("LAST_YEAR")
    population = env_int("POPULATION")
    starting_seed = env_int("STARTING_SEED")
    runs_per_batch = env_int("RUNS_PER_BATCH")
    batches = env_int("BATCHES")

    config_path = REPO_ROOT / "config" / f"{scenario}.yml"
    if not config_path.is_file():
        known = sorted(path.stem for path in config_path.parent.glob("*.yml"))
        sys.exit(
            f"Unknown scenario: {scenario}\n"
            f"Known scenarios: {', '.join(known)}\n"
            f"Write {config_path} to run it."
        )

    # Guards agains missplaced SimPaths model
    simpaths_path = Path(env_str("SIMPATHS_PATH"))
    if not simpaths_path.is_dir():
        sys.exit(f"SIMPATHS_PATH is not a directory: {simpaths_path}")
    if not (simpaths_path / "multirun.jar").is_file():
        sys.exit(f"multirun.jar not found in {simpaths_path}")
    check_jar_has_model_args(simpaths_path / "multirun.jar", config_path)

    simpaths_input_path = simpaths_path / "input"
    simpaths_output_path = simpaths_path / "output"

    results_path = REPO_ROOT / "data" / "simpaths_output" / scenario
    results_path.mkdir(parents=True, exist_ok=True)

    # multirun.jar only reads configs from its own config folder, by name
    (simpaths_path / "config").mkdir(exist_ok=True)
    shutil.copy(config_path, simpaths_path / "config" / config_path.name)
    # Keep a copy with the results
    shutil.copy(config_path, results_path / "simpaths_config.yml")

    timestamp(f" - Started scenario {scenario}")

    try:
        # Force -DBSetup to rebuild from the current inputs, even after a killed
        # job skipped the cleanup below
        for filename in ("input.mv.db", "input.mv.db.lock"):
            (simpaths_input_path / filename).unlink(missing_ok=True)

        output_dirs_before = set(list_output_dirs(simpaths_output_path))

        print("Running SimPaths setup", flush=True)

        run_java([
            "-config", config_path.name,
            "-s", str(first_year),
            "-g", "false",
            "-DBSetup",
        ], cwd=simpaths_path)

        for batch in range(1, batches + 1):
            print(f"Running SimPaths simulation, batch {batch} of {batches}", flush=True)
            batch_seed = starting_seed + (batch - 1) * runs_per_batch
            run_java([
                "-config", config_path.name,
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
