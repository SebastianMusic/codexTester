#!/bin/bash

# --- SETTINGS ---

# Define paths to your scripts
SCRIPT_DIR="$(dirname "$0")"  # directory where this script lives

TEST_SCRIPT="$SCRIPT_DIR/test.sh"
GEN_SCRIPT="$SCRIPT_DIR/gen.sh"
MANUAL_GEN_SCRIPT="$SCRIPT_DIR/mangen.sh"

# --- HANDLE ARGUMENTS ---

# Check if argument was provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 [t | g | mg]"
    echo "  t  - run test script"
    echo "  g  - run generation script"
    echo "  mg - run manual generation script"
    exit 1
fi

mode="$1"

case "$mode" in
    t)
        echo "Running test script..."
        bash "$TEST_SCRIPT"
        ;;
    g)
        echo "Running generation script..."
        bash "$GEN_SCRIPT"
        ;;
    mg)
        echo "Running manual generation script..."
        bash "$MANUAL_GEN_SCRIPT"
        ;;
    *)
        echo "Unknown mode: $mode"
        echo "Valid options are:"
        echo "  t  - test"
        echo "  g  - generate"
        echo "  mg - manual generate"
        exit 1
        ;;
esac
