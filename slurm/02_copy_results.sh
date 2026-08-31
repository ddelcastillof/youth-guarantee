#!/bin/bash

# Utility script

set -euo pipefail
shopt -s nullglob

HPC_SIMPATHS_DIR=/users/dd198b/Documents/GitHub/SimPaths
HPC_YG_DIR=/users/dd198b/Documents/GitHub/youth-guarantee

SCENARIO=${SCENARIO:-baseline}

SRC_ROOT=$HPC_SIMPATHS_DIR/output
DEST_ROOT=$HPC_YG_DIR/data/simpaths_output/$SCENARIO

if [[ ! -d $SRC_ROOT ]]; then
    echo "SimPaths output directory not found: $SRC_ROOT" >&2
    exit 1
fi

mkdir -p "$DEST_ROOT"

copied_dirs=()
skipped_dirs=()

for src_dir in "$SRC_ROOT"/*/; do
    src_dir=${src_dir%/}
    run_name=$(basename "$src_dir")

    # SimPaths writes a sibling logs directory alongside the run directories
    if [[ $run_name == *logs ]]; then
        continue
    fi

    src_csv_dir=$src_dir/csv
    if [[ ! -d $src_csv_dir ]]; then
        echo "No csv/ folder in $run_name, skipping"
        skipped_dirs+=("$run_name")
        continue
    fi

    person_src=$src_csv_dir/Person.csv
    
    bu_src=""
    for candidate in "$src_csv_dir/BenefitUnit.csv"; do
        if [[ -f $candidate ]]; then
            bu_src=$candidate
            break
        fi
    done

    if [[ ! -f $person_src ]]; then
        echo "Person.csv missing in $run_name, skipping"
        skipped_dirs+=("$run_name")
        continue
    fi

    if [[ -z $bu_src ]]; then
        echo "BenefitUnits.csv missing in $run_name, skipping"
        skipped_dirs+=("$run_name")
        continue
    fi

    dest_csv_dir=$DEST_ROOT/$run_name/csv
    mkdir -p "$dest_csv_dir"

    cp "$person_src" "$dest_csv_dir/Person.csv"
    cp "$bu_src" "$dest_csv_dir/$(basename "$bu_src")"

    echo "Copied $run_name ($(basename "$person_src"), $(basename "$bu_src"))"
    copied_dirs+=("$DEST_ROOT/$run_name")
done

if [[ ${#copied_dirs[@]} -eq 0 ]]; then
    echo "No run directories with a csv/ folder found under $SRC_ROOT" >&2
    exit 1
fi

# Point the summarising step at the copies rather than at the SimPaths output
printf '%s\n' "${copied_dirs[@]}" > "$DEST_ROOT/output_dirs.txt"

echo "Copied ${#copied_dirs[@]} run directories into $DEST_ROOT"
echo "Skipped ${#skipped_dirs[@]} directories"
