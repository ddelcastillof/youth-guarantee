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
    person_path = Path(dir, "csv", "Person.csv")
    bu_path = Path(dir, "csv", "BenefitUnit.csv")
    if not person_path.is_file():
        sys.exit(f"Person.csv not found at {person_path}")
    if not bu_path.is_file():
        sys.exit(f"BenefitUnit.csv not found at {bu_path}")
    seed = Path(dir).name.split("_")[1]
    print(f"Reading output directory {dir} assuming seed is {seed}")

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
     





