#!/bin/bash

# The SimPaths pipeline of slurm/submit_all.sh, run on this machine instead of queued on MARS.
#
# Usage: ./slurm/submit_all_local.sh                       # every scenario in SCENARIOS
#        ./slurm/submit_all_local.sh hi-only               # just the ones named
#        ./slurm/submit_all_local.sh --stage summarise X   # one stage in place, e.g. to re-summarise
#        ./slurm/submit_all_local.sh --stage effects       # re-run the cohort comparison in place
#
# Scenarios, settings and stages all come from slurm/submit_all.sh, so a local run
# uses the seeds and settings a submitted one would; change them there. The stages
# run one at a time in the order its job dependencies allow: no two runs overlap on
# SimPaths/config and SimPaths/input, each summary follows its run, and the effects
# come last. The first stage to fail stops the rest.
#
# Results land in data/simpaths_output as on MARS, replacing any downloaded for the
# same scenario. The effects stage compares every scenario it finds there, so run
# all of them in one place rather than mixing local runs with MARS ones.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=slurm/submit_all.sh
source slurm/submit_all.sh

activate_local_env() {
    # multirun.jar is built for Java 25 (maven.compiler.release in SimPaths/pom.xml),
    # which MARS takes from conda; here Homebrew's goes ahead of the openjdk@21
    # that ~/.zshrc puts on PATH
    local jdk=${JAVA25_HOME:-/opt/homebrew/opt/openjdk@25}
    if [[ ! -x $jdk/bin/java ]]; then
        echo "No Java 25 at $jdk: brew install openjdk@25, or set JAVA25_HOME" >&2
        exit 1
    fi
    export PATH=$jdk/bin:$PATH

    # Checked now rather than by the first summary, after its run
    if ! python3 -c 'import polars' 2>/dev/null; then
        echo "python3 cannot import polars: pip install -r requirements.txt" >&2
        exit 1
    fi
}

run_stage() {
    STAGE="$1${2:+ $2}"
    echo "##------ $(date) ------## Stage $STAGE"
    export SCENARIO=${2:-}
    "stage_$1"
}

run_all() {
    (( $# )) || set -- "${SCENARIOS[@]}"

    local scenario
    for scenario in "$@"; do
        run_stage run "$scenario"
        run_stage summarise "$scenario"
    done
    # Scenarios summarised by earlier runs are compared too, as their
    # person_years.parquet is already in place
    run_stage effects

    echo "Ran $# scenarios. Render simpaths-results.qmd for the report"
}

activate_local_env
# A long run's output buries the banner of the stage that failed
trap '[[ $? == 0 || -z ${STAGE:-} ]] || echo "Stopped at stage $STAGE" >&2' EXIT
# A sleeping Mac pauses the simulation; caffeinate keeps it awake until this script exits
if command -v caffeinate >/dev/null; then
    caffeinate -i -w $$ &
fi

if [[ ${1:-} != --stage ]]; then
    run_all "$@"
elif [[ ${2:-} != effects && -z ${3:-} ]]; then
    # effects covers every scenario at once, so it is the one stage without a name
    echo "--stage ${2:-} needs a scenario name" >&2
    exit 1
else
    case $2 in
        run|summarise|effects) run_stage "$2" "${3:-}" ;;
        *) echo "Unknown stage: $2 (expected run, summarise or effects)" >&2; exit 1 ;;
    esac
fi
