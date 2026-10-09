"""
Extract the person-years the cohort analysis needs from one scenario's SimPaths runs.

Flags who SimPaths itself treats as eligible for supported employment each year,
using the same rule as Person.isSupportedEmploymentEligible(). The cohort is not
picked here: src/03_cohort_effects.py picks it once, in baseline, and follows the
same people in every scenario. Picking it inside each scenario would compare
different people, because SimPaths draws UC receipt from its global random
number generator and so reshuffles it between runs with the same seed.
"""
import os
import re
import sys
from pathlib import Path

import polars as pl

REPO_ROOT = Path(__file__).resolve().parent.parent

# Keeps every cohort member from the year before they are first eligible (age 17)
# to the end of the programme (at most 24 + 5 = 29), in every scenario
MIN_AGE, MAX_AGE = 16, 30

scenario = os.environ.get("SCENARIO")
if not scenario:
    sys.exit("SCENARIO env var not set")

results_path = REPO_ROOT / "data" / "simpaths_output" / scenario
output_file = results_path / "person_years.parquet"
output_dirs = (results_path / "output_dirs.txt").read_text().splitlines()

# Programme window as this scenario ran it, from the config src/00_stage_config.py
# saved; that template is flat key: value lines, so no YAML parser is needed
config = (results_path / "simpaths_config.yml").read_text()


def config_year(key):
    match = re.search(rf"^\s*{key}:\s*(\d+)\s*$", config, re.MULTILINE)
    if not match:
        sys.exit(f"{key} not found in {results_path / 'simpaths_config.yml'}")
    return int(match.group(1))


start_year = config_year("supportedEmploymentStartYear")
end_year = config_year("supportedEmploymentEndYear")

# Column types match the Java fields SimPaths exports
person_schema = {
    "run": pl.Int64, "time": pl.Float64, "id_Person": pl.Int64, "idBu": pl.Int64,
    "demAge": pl.Int64, "labC4": pl.String, "healthMentalMcs": pl.Float64,
    "healthPsyDstrss0to12": pl.Float64, "yBenUCReceivedFlag": pl.String,
    "supportedEmploymentFlag": pl.String,
}

bu_schema = {
    "run": pl.Int64, "time": pl.Float64, "id_BenefitUnit": pl.Int64, "yDispEquivYear": pl.Float64,
}

all_data = []

for output_dir in output_dirs:
    # The summarise stage copies each run next to the manifest, so resolving by
    # name works on the cluster and on a machine the results were copied to
    run_dir = results_path / Path(output_dir).name
    person_path = run_dir / "csv" / "Person.csv"
    bu_path = run_dir / "csv" / "BenefitUnit.csv"
    if not person_path.is_file():
        sys.exit(f"Person.csv not found at {person_path}")
    if not bu_path.is_file():
        sys.exit(f"BenefitUnit.csv not found at {bu_path}")
    # Multirun folders are <timestamp>_<seed>_<run>; single runs are <timestamp>
    # only and always use singlerun.jar's fixed seed, so every scenario pairs up
    name_parts = run_dir.name.split("_")
    seed = name_parts[1] if len(name_parts) > 1 else "606"
    print(f"Reading output directory {run_dir} assuming seed is {seed}")

    # JAS-mine writes missing values as the literal "null"
    person_data = pl.read_csv(
        source = person_path, columns = list(person_schema),
        schema_overrides = person_schema, null_values = "null",
    )
    bu_data = pl.read_csv(
        source = bu_path, columns = list(bu_schema),
        schema_overrides = bu_schema, null_values = "null",
    )

    # Left join: a person keeps their row even if their benefit unit has none that year
    merged_data = person_data.join(
        bu_data,
        left_on = ["run", "time", "idBu"],
        right_on = ["run", "time", "id_BenefitUnit"],
        how = "left",
    ).with_columns(pl.lit(seed).alias("seed"))

    all_data.append(merged_data)

all_data = pl.concat(all_data).with_columns(
    pl.col("time").cast(pl.Int64),
    # Person.csv writes booleans as true/false; the benefit-unit flag in
    # BenefitUnit.csv is a different variable and not the one SimPaths checks
    (pl.col("yBenUCReceivedFlag") == "true").alias("uc"),
    # Only written in years the programme placed someone; null otherwise
    (pl.col("supportedEmploymentFlag") == "true").fill_null(False).alias("placed"),
)

# Create employment variables
all_data = all_data.with_columns(
    pl.when(pl.col("labC4") == "EmployedOrSelfEmployed")
    .then(True)
    .when(pl.col("demAge").is_between(16, 64))
    .then(False)
    .otherwise(None)
    .alias("employed")
    )

# Create lagged UC receipt and activity status
person_keys = ["seed", "run", "id_Person"]
has_prev_year = pl.col("time").shift(1).over(person_keys) == pl.col("time") - 1
all_data = all_data.sort([*person_keys, "time"]).with_columns(
    pl.when(has_prev_year)
    .then(pl.col(col).shift(1).over(person_keys))
    .alias(f"{col}L1")
    for col in ["uc", "labC4"]
    )

# SimPaths' rule, Person.isSupportedEmploymentEligible(): within the programme
# window, aged 18-24 this year, on UC last year, not employed last year, and at
# risk of work (not a student or retired) this year
eligible = (
    pl.col("time").is_between(start_year, end_year)
    & pl.col("demAge").is_between(18, 24)
    & pl.col("ucL1").fill_null(False)
    & (pl.col("labC4L1") == "NotEmployed")
    & ~pl.col("labC4").is_in(["Student", "Retired"])
    )

output = (
    all_data.filter(pl.col("demAge").is_between(MIN_AGE, MAX_AGE))
    .select(
        pl.lit(scenario).alias("scenario"),
        *person_keys, "time", "demAge", "labC4", "employed", "placed", "uc",
        eligible.alias("eligible"),
        "healthMentalMcs", "healthPsyDstrss0to12", "yDispEquivYear",
    )
)

# Saving file
print(f"Saving {output.height} person-years for scenario {scenario}: "
      f"{output['eligible'].sum()} eligible, {output['placed'].sum()} placed")
output.write_parquet(output_file)
