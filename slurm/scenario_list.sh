#!/bin/bash

# Sourced helper. Prints the scenario names from slurm/scenarios.txt, one per line.
# Override the list location with SCENARIO_LIST.

# Resolved when this file is sourced: BASH_SOURCE is not reliable inside the function
_SCENARIO_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

scenario_names() {
    local list=${SCENARIO_LIST:-$_SCENARIO_LIB_DIR/scenarios.txt}

    if [[ ! -f $list ]]; then
        echo "Scenario list not found: $list" >&2
        return 1
    fi

    # Strip comments and whitespace, drop blank lines
    sed -e 's/#.*//' -e 's/[[:space:]]//g' "$list" | grep -v '^$'
}
