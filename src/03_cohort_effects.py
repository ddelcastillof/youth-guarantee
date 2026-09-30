"""
Follow one fixed cohort through every scenario and compare each person with themselves in baseline.

The cohort is everyone SimPaths finds eligible for supported employment at any
point in the programme window of the baseline run: the people who would be
eligible with no programme. Each is followed from the year before they are
first eligible (k = -1, a check that scenarios agree before the programme) to
the end of the simulation, under the same seed and person id in every scenario.

Run after src/02_outputs_sum.py has written person_years.parquet for baseline
and every scenario to compare; it reads every scenario it finds.
"""
import sys
from pathlib import Path

import polars as pl

REPO_ROOT = Path(__file__).resolve().parent.parent
RESULTS_ROOT = REPO_ROOT / "data" / "simpaths_output"

REFERENCE = "baseline"
PERSON_KEYS = ["seed", "run", "id_Person"]
MCS_THRESHOLDS = (50, 45, 46, 40, 35, 30)

# One value per person-year; levels average them, effects average their difference from baseline
mcs = pl.col("healthMentalMcs")
OUTCOMES = {
    "emp_rate": pl.col("employed").cast(pl.Float64),
    "placed_rate": pl.col("placed").cast(pl.Float64),
    # Eligible under the scenario's own run; differs from baseline even before
    # the programme acts, as SimPaths reshuffles UC receipt between runs
    "elig_rate": pl.col("eligible").cast(pl.Float64),
    "mean_mcs": mcs,
    **{f"mean_mcscase{t}": (mcs < t).cast(pl.Float64) for t in MCS_THRESHOLDS},
    "mean_mhcase": (pl.col("healthPsyDstrss0to12") >= 4).cast(pl.Float64),
    "mean_inc": pl.col("yDispEquivYear"),
}

# Years since first eligible, from k = -1; and calendar year, from each person's
# first eligible year only, so a year never mixes in people not yet eligible
TIMESCALES = {
    "since_eligible": ("k", pl.lit(True)),
    "calendar": ("time", pl.col("k") >= 0),
}

person_year_files = sorted(RESULTS_ROOT.glob("*/person_years.parquet"))
if not person_year_files:
    sys.exit(f"No person_years.parquet under {RESULTS_ROOT}: run src/02_outputs_sum.py first")
persons = pl.concat([pl.read_parquet(path) for path in person_year_files])

scenarios = sorted(persons["scenario"].unique())
if REFERENCE not in scenarios:
    sys.exit(f"No {REFERENCE} person-years under {RESULTS_ROOT}: it defines the cohort")
print(f"Scenarios found: {', '.join(scenarios)}")

# Pairing needs the same seeds in every scenario; unmatched ones drop out of the effects
runs = persons.select("scenario", "seed", "run").unique()
reference_runs = runs.filter(pl.col("scenario") == REFERENCE).drop("scenario")
for scenario in scenarios:
    scenario_runs = runs.filter(pl.col("scenario") == scenario).drop("scenario")
    unmatched = scenario_runs.join(reference_runs, on=["seed", "run"], how="anti").height
    missing = reference_runs.join(scenario_runs, on=["seed", "run"], how="anti").height
    if unmatched or missing:
        print(f"Warning: {scenario} has {unmatched} runs with no {REFERENCE} match "
              f"and lacks {missing} {REFERENCE} runs; only matching seeds are compared")

cohort = (
    persons.filter((pl.col("scenario") == REFERENCE) & pl.col("eligible"))
    .group_by(PERSON_KEYS)
    .agg(pl.col("time").min().alias("t0"))
)
if cohort.is_empty():
    sys.exit(f"Nobody is eligible in {REFERENCE}: check the programme window in its simpaths_config.yml")
entries = cohort.group_by("t0").len().sort("t0").rows()
print(f"Cohort: {cohort.height} people over {reference_runs.height} runs; first eligible by year: {entries}")

followed = (
    persons.join(cohort, on=PERSON_KEYS)
    .filter(pl.col("time") >= pl.col("t0") - 1)
    .with_columns((pl.col("time") - pl.col("t0")).alias("k"))
    .select("scenario", *PERSON_KEYS, "time", "k", "demAge", *[expr.alias(name) for name, expr in OUTCOMES.items()])
)

# Each person-year against the same person that year in baseline
baseline = followed.filter(pl.col("scenario") == REFERENCE).drop("scenario", "k")
paired = (
    followed.filter(pl.col("scenario") != REFERENCE)
    .join(baseline, on=[*PERSON_KEYS, "time"], suffix="_bln")
    # Ids of people who exist before the programme are stable across runs, but
    # this also drops any pair where the id has gone to someone else
    .filter(pl.col("demAge") == pl.col("demAge_bln"))
    .with_columns(pl.col(name) - pl.col(f"{name}_bln") for name in OUTCOMES)
)
print(f"Paired {paired.height} person-years with {REFERENCE}")


def by_timescale(data):
    # One row per scenario, run and step on each timescale, stacked
    return pl.concat([
        data.filter(keep)
        .group_by("scenario", "seed", "run", column)
        .agg(pl.len().alias("n"), *[pl.col(name).mean() for name in OUTCOMES])
        .rename({column: "t"})
        .select("scenario", "seed", "run", pl.lit(timescale).alias("timescale"), "t", pl.exclude("scenario", "seed", "run", "t"))
        for timescale, (column, keep) in TIMESCALES.items()
    ]).sort("timescale", "scenario", "seed", "run", "t")


levels_file = RESULTS_ROOT / "cohort_levels.csv"
effects_file = RESULTS_ROOT / "cohort_effects.csv"
by_timescale(followed).write_csv(levels_file)
by_timescale(paired).write_csv(effects_file)
print(f"Saved {levels_file} and {effects_file}")
