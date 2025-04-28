#!/usr/bin/env bash
#
# dq_run.sh  –  Dynamic-question drill workflow
# -----------------------------------------------------------------------------
#   1. Pick a sub-folder under  q/dq/        (each file = one meta-prompt)
#   2. For each meta-prompt file
#        • Codex call 1 : SYSTEM_DRAFT   → JSON {question, points[ ]}
#        • Codex call 2 : SYSTEM_CONCISE → polished JSON
#        • Open Neovim  : question + important points + “Answer below”
#        • On save      :  prefix.md + question + points + answer  → Codex critique
#   3. Repeat until folder exhausted
# -----------------------------------------------------------------------------

set -euo pipefail

# ── PATHS & CONSTANTS ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR/dq"                 # root for dynamic prompt folders
MODEL="gpt-4.1"                             # codex model id
EDITOR="nvim"                               # change if you prefer another editor

# prefix.md (examiner prompt)
PREFIX_FILE="$SCRIPT_DIR/prefix.md"
[[ -f "$PREFIX_FILE" ]] || { printf "Error: %s not found\n" "$PREFIX_FILE"; exit 1; }
PREFIX=$(<"$PREFIX_FILE")

# ── SYSTEM PROMPTS (generation phase) ─────────────────────────────────────────
SYSTEM_DRAFT=$'You are a university-level exam-setter.\n\
TASK: create **one** exercise that satisfies the user meta-prompt.\n\
OUTPUT SPECIFICATION\n\
  • First reason step-by-step OUT LOUD; prefix each internal line with \"### \".\n\
  • Finally, emit exactly ONE line of pure JSON and **nothing else**:\n\
      {\"question\":\"<single clear sentence>\",\
\"points\":[\"<pt1>\",\"<pt2>\",\"<pt3>\"]}\n\
    – 3 ≤ points ≤ 6 capturing the key facts a student should recall.'

SYSTEM_CONCISE=$'You are an editor.\n\
INPUT = one JSON line with keys question, points.\n\
Rewrite:\n\
  • Ensure \"question\" ≤ 140 chars, absolutely unambiguous.\n\
  • Trim each \"points\" item to ≤ 15 words.\n\
Return a single JSON line in the identical shape — nothing else.'

# ── HELPER: extract last JSON line from codex CLI envelope ────────────────────
codex_json_text() {
  jq -r '.content[] | select(.type=="output_text") | .text' \
  | awk 'NF{last=$0} END{print last}'
}

die() { printf "Error: %s\n" "$*" >&2; exit 1; }

# ── CHOOSE PROMPT FOLDER ──────────────────────────────────────────────────────
[[ -d "$BASE_DIR" ]] || die "Base directory '$BASE_DIR' not found."

selection=$(
  (find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sed "s|$BASE_DIR/||" || true) \
  | fzf --prompt="Select dynamic-prompt folder: " --print-query --bind "enter:accept"
) || die "fzf cancelled."

dir_choice=$(sed -n '2p' <<< "$selection")
dir_choice=${dir_choice:-$(sed -n '1p' <<< "$selection")}
[[ -n "$dir_choice" ]] || die "No folder chosen."

PROMPT_DIR="$BASE_DIR/$dir_choice"
[[ -d "$PROMPT_DIR" ]] || die "Folder '$dir_choice' does not exist."
echo ">>> Using meta-prompts from:  $PROMPT_DIR"

# ── MAIN LOOP ─────────────────────────────────────────────────────────────────
mapfile -t META_PROMPTS < <(find "$PROMPT_DIR" -type f)
(( ${#META_PROMPTS[@]} > 0 )) || die "No prompt files found."

while (( ${#META_PROMPTS[@]} )); do
  # Pick random meta-prompt
  idx=$(( RANDOM % ${#META_PROMPTS[@]} ))
  filepath=${META_PROMPTS[$idx]}
  unset 'META_PROMPTS[idx]'
  META_PROMPTS=("${META_PROMPTS[@]}")     # compact array

  meta_prompt=$(<"$filepath")
  [[ -n "$meta_prompt" ]] || { echo "Skipping empty file $(basename "$filepath")"; continue; }

  # ── 1️⃣  GENERATE (draft) ────────────────────────────────────────────────
  draft_json=$(codex -m "$MODEL" -q "$SYSTEM_DRAFT

$meta_prompt" | codex_json_text)

  # ── 2️⃣  POLISH (concise) ────────────────────────────────────────────────
  concise_json=$(codex -m "$MODEL" -q "$SYSTEM_CONCISE

$draft_json" | codex_json_text)

  # Parse final JSON
  clean_question=$(jq -r '.question' <<< "$concise_json") \
      || { echo "JSON parse error – skipping $(basename "$filepath")"; continue; }

  mapfile -t important_points < <(jq -r '.points[]' <<< "$concise_json")

  # ── 3️⃣  NEOVIM BUFFER ──────────────────────────────────────────────────
  tmpfile=$(mktemp)
  {
      printf '###### Question ######\n%s\n\n' "$clean_question"
      printf '\n###### Answer below ######\n\n'
  } >"$tmpfile"

  echo
  echo "─────────────────────────────────────────────────────────────"
  echo "Answer the generated question in Neovim.  (temp file: $tmpfile)"
  echo "─────────────────────────────────────────────────────────────"
  $EDITOR "$tmpfile" || { echo "Neovim aborted; skipping."; rm -f "$tmpfile"; continue; }

  # Extract answer (everything after the marker)
  user_answer=$(awk '
      BEGIN {seen=0}
      /^###### Answer below ######/ {seen=1; next}
      {if(seen) print}
  ' "$tmpfile" | sed '/^[[:space:]]*$/d')
  rm -f "$tmpfile"

  if [[ -z "$user_answer" ]]; then
      echo "Blank answer – skipping critique."
      continue
  fi

  # ── 4️⃣  CRITIQUE  (prefix.md) ───────────────────────────────────────────
  critique_input="$PREFIX

###### Question ######
$clean_question

###### Important points to remember ######
$(printf -- '- %s\n' "${important_points[@]}")

###### Answer below ######
$user_answer
"
  echo
  echo "══════════  Feedback  ══════════"
  codex -m "$MODEL" "$critique_input" || echo "Codex critique failed."
  echo "════════════════════════════════"
  echo
done

echo "🎉  All meta-prompts processed.  Session complete."
