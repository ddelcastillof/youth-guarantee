#!/bin/bash

# Utility script

set -euo pipefail

HPC_SIMPATHS_DIR=${HPC_SIMPATHS_DIR:-/users/dd198b/Documents/GitHub/SimPaths}
HPC_YG_DIR=${HPC_YG_DIR:-/users/dd198b/Documents/GitHub/youth-guarantee}

SLURM_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SLURM_DIR/scenario_list.sh"

SCENARIOS=()
if [[ $# -gt 0 ]]; then
    SCENARIOS=("$@")
else
    while IFS= read -r scenario; do
        SCENARIOS+=("$scenario")
    done < <(scenario_names)
fi

if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
    echo "No scenarios to copy" >&2
    exit 1
fi

SRC_ROOT=$HPC_SIMPATHS_DIR/output
DEST_ROOT=$HPC_YG_DIR/data/simpaths_output

if [[ ! -d $SRC_ROOT ]]; then
    echo "SimPaths output directory not found: $SRC_ROOT" >&2
    exit 1
fi

copy_scenario() {
    local scenario=$1
    local dest_root=$DEST_ROOT/$scenario
    local manifest=$dest_root/output_dirs.txt

    if [[ ! -f $manifest ]]; then
        echo "[$scenario] No manifest at $manifest" >&2
        echo "[$scenario] Run src/01_run_simpaths.py with SCENARIO=$scenario first" >&2
        return 1
    fi

    local copied_dirs=()
    local skipped_dirs=()
    local listed_dir run_name src_csv_dir person_src bu_src dest_csv_dir

    while IFS= read -r listed_dir || [[ -n $listed_dir ]]; do
        [[ -n $listed_dir ]] || continue

        run_name=$(basename "$listed_dir")

        if [[ $run_name == *logs ]]; then
            continue
        fi

        src_csv_dir=$SRC_ROOT/$run_name/csv
        person_src=$src_csv_dir/Person.csv
        bu_src=$src_csv_dir/BenefitUnit.csv
        dest_csv_dir=$dest_root/$run_name/csv

        if [[ ! -f $person_src || ! -f $bu_src ]]; then
            if [[ -f $dest_csv_dir/Person.csv && -f $dest_csv_dir/BenefitUnit.csv ]]; then
                echo "[$scenario] $run_name already copied"
                copied_dirs+=("$dest_root/$run_name")
            else
                echo "[$scenario] Person.csv or BenefitUnit.csv missing in $run_name, skipping" >&2
                skipped_dirs+=("$run_name")
            fi
            continue
        fi

        mkdir -p "$dest_csv_dir"
        cp "$person_src" "$dest_csv_dir/Person.csv"
        cp "$bu_src" "$dest_csv_dir/BenefitUnit.csv"

        echo "[$scenario] Copied $run_name"
        copied_dirs+=("$dest_root/$run_name")
    done < "$manifest"

    if [[ ${#copied_dirs[@]} -eq 0 ]]; then
        echo "[$scenario] No run directories from the manifest found under $SRC_ROOT" >&2
        return 1
    fi

    printf '%s\n' "${copied_dirs[@]}" > "$manifest"

    echo "[$scenario] Copied ${#copied_dirs[@]} run directories into $dest_root"
    echo "[$scenario] Skipped ${#skipped_dirs[@]} directories"
}

status=0
for scenario in "${SCENARIOS[@]}"; do
    copy_scenario "$scenario" || status=1
done

exit $status
