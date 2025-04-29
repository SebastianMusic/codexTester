#!/usr/bin/env bash
#
# test.sh – run study sessions
#
#   default : static questions (./q)
#   dq      : dynamic meta-prompts (./dq)
#   -m      : manually pick one file
# ---------------------------------------------------------------------------

set -euo pipefail

##############################################################################
# 0.  FLAGS
##############################################################################
TYPE="static"        # static | dynamic
MANUAL=false

for arg in "$@"; do
  case "$arg" in
    dq|dynamic) TYPE="dynamic" ;;
    static)     TYPE="static"  ;;
    -m|--manual) MANUAL=true   ;;
    *) echo "Usage: $0 [dq|static] [-m]" ; exit 1 ;;
  esac
done

##############################################################################
# 1.  CONSTANTS
##############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR/${TYPE/dynamic/dq}"
PREFIX_FILE="$SCRIPT_DIR/prefix.md"

[[ -f "$PREFIX_FILE" ]] || { echo "Missing $PREFIX_FILE"; exit 1; }
PREFIX=$(<"$PREFIX_FILE")

MODEL="gpt-4.1"
EDITOR="nvim"

# Dynamic-flow system prompts (tweak whenever you want)
DRAFT_PROMPT=$'You are an exam-setter. Think aloud with ### lines, then output one JSON line:\n{"question":"…","points":["p1","p2","p3"]}'
CONCISE_PROMPT=$'Rewrite the JSON so question ≤140 chars, trim each point ≤15 words. Return one JSON line only.'

##############################################################################
# 2.  PICK SUBFOLDER
##############################################################################
selection=$(
  (find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sed "s|$BASE_DIR/||" || true) |
  fzf --prompt="Select directory: " --print-query --bind "enter:accept"
) || { echo "fzf cancelled"; exit 1; }

dir_choice=$(sed -n '2p' <<<"$selection")
dir_choice=${dir_choice:-$(sed -n '1p' <<<"$selection")}
[[ -n "$dir_choice" ]] || { echo "No directory chosen"; exit 1; }

QUEST_DIR="$BASE_DIR/$dir_choice"
[[ -d "$QUEST_DIR" ]] || { echo "Folder $QUEST_DIR not found"; exit 1; }

##############################################################################
# 3.  BUILD FILE LIST
##############################################################################
mapfile -t FILES < <(find "$QUEST_DIR" -type f)
(( ${#FILES[@]} > 0 )) || { echo "No files in $QUEST_DIR"; exit 1; }

##############################################################################
# 4.  MANUAL PICK?
##############################################################################
if $MANUAL; then
  pick=$(printf '%s\n' "${FILES[@]}" | sed "s|$QUEST_DIR/||" |
        fzf --prompt="Pick file: ")
  [[ -n "$pick" ]] || { echo "No file chosen"; exit 1; }
  FILES=("$QUEST_DIR/$pick")
fi

##############################################################################
# 5.  HELPER – clean last JSON line
##############################################################################
json_last_line() {
  awk 'NF{last=$0} END{
        gsub(/^[`]+|[`]+$/,"",last);       # strip ```
        gsub(/^json/,"",last);             # strip leading "json" if ```json
        print last
      }'
}

##############################################################################
# 6.  MAIN LOOP
##############################################################################
while (( ${#FILES[@]} )); do
  # pick random file
  idx=$(( RANDOM % ${#FILES[@]} ))
  filepath=${FILES[$idx]}
  unset 'FILES[idx]'; FILES=("${FILES[@]}")

  if [[ "$TYPE" == "static" ]]; then
    ##########################################################################
    # STATIC FLOW
    ##########################################################################
    question_content=$(awk '/^###### Important points to remember ######/ {exit} {print}' "$filepath")
    [[ -n "$question_content" ]] || { echo "Bad file $filepath"; continue; }

    tmp=$(mktemp)
    printf '%s\n\n###### Answer below ######\n\n' "$question_content" >"$tmp"
    $EDITOR "$tmp"
    answer=$(<"$tmp"); rm -f "$tmp"
    [[ -n "$answer" ]] || { echo "Empty answer; skipping"; continue; }

    codex -m "$MODEL" "$PREFIX

$answer" || echo "Codex failed"

  else
    ##########################################################################
    # DYNAMIC FLOW
    ##########################################################################
    meta_prompt=$(<"$filepath")

    # 1️⃣  Draft
    draft_json=$(codex -m "$MODEL" -q "$DRAFT_PROMPT

$meta_prompt" |
                 jq -r '.content[] | select(.type=="output_text") | .text' |
                 json_last_line)

    # 2️⃣  Concise
    concise_json=$(codex -m "$MODEL" -q "$CONCISE_PROMPT

$draft_json" |
                   jq -r '.content[] | select(.type=="output_text") | .text' |
                   json_last_line)

    # Validate JSON
    if ! question=$(jq -er '.question' <<<"$concise_json" 2>/dev/null); then
      echo "⚠️  Invalid JSON from model; skipping $(basename "$filepath")"
      continue
    fi
    mapfile -t points < <(jq -r '.points[]' <<<"$concise_json" 2>/dev/null)

    tmp=$(mktemp)
    { printf '###### Question ######\n%s\n\n' "$question"
      printf '###### Answer below ######\n\n'; } >"$tmp"

    $EDITOR "$tmp"
    answer=$(<"$tmp"); rm -f "$tmp"
    [[ -n "$answer" ]] || { echo "Empty answer"; continue; }

    codex -m "$MODEL" "$PREFIX

###### Question ######
$question

###### Important points to remember ######
$(printf -- '- %s\n' "${points[@]}")

###### Answer below ######
$answer" || echo "Codex failed"
  fi

  $MANUAL && break
done

echo "Done."
