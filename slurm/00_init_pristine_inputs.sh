#!/bin/bash

# Utility script, run once per machine before any scenario is staged.
#
# Snapshots the SimPaths input files that scenarios mutate, so every run can be
# restored to a known-clean starting point. Refuses to capture a snapshot that
# already carries a scenario's effect: that would enshrine an intervention as
# the baseline, silently, for every run afterwards.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SIMPATHS_PATH=${SIMPATHS_PATH:-$REPO_ROOT/../SimPaths}
SRC_INPUT=$SIMPATHS_PATH/input
PRISTINE_DIR=$REPO_ROOT/data/scenario_inputs/pristine

# Input files any scenario mutates; add to this list when a scenario touches a new one
PRISTINE_FILES=("reg_health_wellbeing.xlsx")

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

if [[ ! -d $SRC_INPUT ]]; then
    echo "SimPaths input directory not found: $SRC_INPUT" >&2
    exit 1
fi

if [[ -d $PRISTINE_DIR ]] && [[ -n $(ls -A "$PRISTINE_DIR" 2>/dev/null) ]]; then
    echo "Pristine snapshot already exists: $PRISTINE_DIR" >&2
    echo "Refusing to overwrite it. Delete it by hand if you really mean to re-capture." >&2
    exit 1
fi

for filename in "${PRISTINE_FILES[@]}"; do
    if [[ ! -f $SRC_INPUT/$filename ]]; then
        echo "Missing input file: $SRC_INPUT/$filename" >&2
        exit 1
    fi
done

# Contamination check: a scenario's regressor must not already be in the workbook
python3 - "$SRC_INPUT" <<'PY'
import sys
from pathlib import Path

from openpyxl import load_workbook

simpaths_input = Path(sys.argv[1])

# Kept in step with src/scenarios/hi_only.py
CHECKS = [("reg_health_wellbeing.xlsx", "DHE_MCS1", "AgeUnder25")]

for workbook_name, sheet_name, regressor in CHECKS:
    sheet = load_workbook(simpaths_input / workbook_name, read_only=True)[sheet_name]
    regressors = [row[0] for row in sheet.iter_rows(min_row=2, max_col=1, values_only=True)]
    if regressor in regressors:
        sys.exit(
            f"{simpaths_input / workbook_name} already contains {regressor} in {sheet_name}.\n"
            "These inputs carry a scenario effect and cannot be used as the pristine baseline.\n"
            "Restore a clean copy (git -C <SimPaths> checkout -- input/) and run this again."
        )

print("Contamination check passed: inputs are clean")
PY

mkdir -p "$PRISTINE_DIR"

: > "$PRISTINE_DIR/CHECKSUMS.txt"
for filename in "${PRISTINE_FILES[@]}"; do
    cp "$SRC_INPUT/$filename" "$PRISTINE_DIR/$filename"
    printf '%s  %s\n' "$(sha256_of "$PRISTINE_DIR/$filename")" "$filename" >> "$PRISTINE_DIR/CHECKSUMS.txt"
    echo "Captured $filename"
done

echo "Pristine snapshot written to $PRISTINE_DIR"
cat "$PRISTINE_DIR/CHECKSUMS.txt"
