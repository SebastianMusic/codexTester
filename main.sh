#!/usr/bin/env bash
#
# main.sh – one-stop launcher
#
#   t   → test script           (./test.sh ...)
#   g   → generator             (./gen.sh  ...)
#   mg  → manual generator      (alias for “g -m”)
#
# Any extra flags after the mode are forwarded unchanged to the target script.
# ------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEST_SCRIPT="$SCRIPT_DIR/test.sh"
GEN_SCRIPT="$SCRIPT_DIR/gen.sh"       # unified non-blocking generator

usage() {
  cat <<EOF
Usage: $0 MODE [ARGS...]

MODE
  t     run test script             (static by default)
  g     run generator               (static by default)
  mg    run generator with -m flag  (manual topic/filename)

EXAMPLES
  $0 t dq -m        # dynamic test, pick single file
  $0 g dynamic      # create a dynamic meta-prompt
EOF
  exit 1
}

[[ $# -ge 1 ]] || usage

mode="$1"
shift              # leave the remaining args for the target script

case "$mode" in
  t)
      bash "$TEST_SCRIPT" "$@"
      ;;
  g)
      bash "$GEN_SCRIPT" "$@"
      ;;
  mg)
      # ensure -m is included exactly once
      bash "$GEN_SCRIPT" -m "$@"
      ;;
  *)
      echo "Unknown mode: $mode"
      usage
      ;;
esac
