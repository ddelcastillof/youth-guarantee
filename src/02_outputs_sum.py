"""
Summarising output from SimPaths
"""
import os
import sys
from pathlib import Path

import polars as pl

REPO_ROOT = Path(__file__).resolve().parent.parent

scenario = os.environ.get("SCENARIO")
if not scenario:
    sys.exit("SCENARIO env var not set")

results_path = REPO_ROOT / "data" / "simpaths_output" / scenario
output_file = results_path / "summarised_output.csv"
output_dirs = (results_path / "output_dirs.txt").read_text().splitlines()

person_cols = [
    "run", "time", "id_Person", "idBu", "demAge", "demMaleFlag",
    "eduHighestC4", "labC4", "healthMentalMcs", "healthPhysicalPcs",
    "healthPsyDstrss0to12", "healthSelfRated",
]

bu_cols = ["run", "time", "id_BenefitUnit", "yPvrtyFlag", "yDispEquivYear"]

all_data = []

for output_dir in (output_dirs):
    person_path = Path(output_dir, "csv", "Person.csv")
    bu_path = Path(output_dir, "csv", "BenefitUnit.csv")
    if not person_path.is_file():
        sys.exit(f"Person.csv not found at {person_path}")
    if not bu_path.is_file():
        sys.exit(f"BenefitUnit.csv not found at {bu_path}")
    seed = Path(output_dir).name.split("_")[1]
    print(f"Reading output directory {output_dir} assuming seed is {seed}")

    person_data = pl.read_csv(source = person_path, columns = person_cols)
    bu_data = pl.read_csv(source = bu_path, columns = bu_cols)

    merged_data = person_data.join(
        bu_data,
        left_on = ["run", "time", "idBu"],
        right_on = ["run", "time", "id_BenefitUnit"],
        how = "inner",
    ).with_columns(pl.lit(seed).alias("seed"))

    all_data.append(merged_data)
 
all_data = pl.concat(all_data)
     
# Create employment variables
all_data = all_data.with_columns(
    pl.when(pl.col("labC4") == "EmployedOrSelfEmployed")
    .then(True)
    .when(pl.col("demAge").is_between(16, 64))
    .then(False)
    .otherwise(None)
    .alias("employed")
    )

# Young labour population
final_data = all_data.filter((pl.col("demAge") >= 18) & (pl.col("demAge") <= 25))

# Grouping all variables individual statistics
MCS_THRESHOLDS = (50, 45, 46, 40, 35, 30)

mcs = pl.col("healthMentalMcs")

output = (
    final_data.group_by(["seed", "time"])
    .agg(
        pl.lit(scenario).alias("scenario"),
        pl.lit("population").alias("strata"),
        pl.col("yDispEquivYear").mean().alias("mean_inc"),
        pl.col("employed").mean().alias("emp_rate"),
        (pl.col("healthPsyDstrss0to12") >= 4).mean().alias("mean_mhcase"),
        mcs.mean().alias("mean_mcs"),
        *[(mcs < t).mean().alias(f"mean_mcscase{t}") for t in MCS_THRESHOLDS],
#        pl.col("yPvrtyFlag").mean().alias("poverty_rate"),
#        gini.alias("gini"),
#        (
#            nonneg_inc.filter(inc_decile.is_in(list(range(1, 6)))).sum()
#            / nonneg_inc.sum()
#        ).alias("median_share"),
#        (
#            nonneg_inc.filter(inc_decile >= 9).sum()
#            / nonneg_inc.filter(inc_decile <= 2).sum()
#        ).alias("s80s20"),
    )
    .sort(["seed", "time"])
)

# Saving file
print(f"Saving summarised scenario per output {scenario}")
output.write_csv(output_file)

