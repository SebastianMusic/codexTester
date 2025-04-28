#!/usr/bin/env bash
#
# gen_question.sh   –  create study material without blocking the shell
#
#   • static  (default) → full recall-question markdown   →  ./q/<folder>/<name>.md
#   • dynamic (dq)      → one-line meta-prompt text       →  ./dq/<folder>/<name>.txt
#
# Usage:
#   ./gen_question.sh            # = static
#   ./gen_question.sh static
#   ./gen_question.sh dynamic    # or ./gen_question.sh dq
# ------------------------------------------------------------------------------

set -euo pipefail

###############################################################################
# 0.  MODE PARSE
###############################################################################
MODE="static"
if [[ $# -gt 0 ]]; then
  case "$1" in
    static) MODE="static"   ;;
    dynamic|dq) MODE="dynamic" ;;
    *)  echo "Usage: $0 [static|dynamic]" ; exit 1 ;;
  esac
fi

###############################################################################
# 1.  PATHS & CONSTANTS
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$MODE" == "static" ]]; then
  BASE_DIR="$SCRIPT_DIR/q"
else
  BASE_DIR="$SCRIPT_DIR/dq"
fi
MODEL="gpt-4.1"
EDITOR="nvim"

mkdir -p "$BASE_DIR"

###############################################################################
# 2.  PICK / CREATE SUB-FOLDER
###############################################################################
selection=$(
  (find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sed "s|$BASE_DIR/||" || true) \
  | fzf --prompt="Select or type new directory: " --print-query --bind "enter:accept"
) || { echo "fzf cancelled. Exiting." ; exit 1; }

dir_choice=$(sed -n '2p' <<< "$selection")
dir_choice=${dir_choice:-$(sed -n '1p' <<< "$selection")}
[[ -n "$dir_choice" ]] || { echo "No directory selected. Exiting."; exit 1; }

TARGET_DIR="$BASE_DIR/$dir_choice"
mkdir -p "$TARGET_DIR"

###############################################################################
# 3.  READ TOPIC  + FILENAME (synchronously, in the foreground)
###############################################################################
tmp_topic=$(mktemp)
$EDITOR "$tmp_topic"
topic=$(xargs <"$tmp_topic") ; rm -f "$tmp_topic"
[[ -n "$topic" ]] || { echo "Topic was empty. Exiting."; exit 1; }

tmp_file=$(mktemp)
$EDITOR "$tmp_file"
filename=$(xargs <"$tmp_file") ; rm -f "$tmp_file"
[[ -n "$filename" ]] || { echo "Filename was empty. Exiting."; exit 1; }

###############################################################################
# 4.  BACKGROUND  CODEx  GENERATION
###############################################################################
(
  set -euo pipefail

  # ---- local cleanup (only inside this subshell) ---------------------------
  TMP_PROMPT=$(mktemp)
  TMP_CODEX=$(mktemp)
  trap 'rm -f "$TMP_PROMPT" "$TMP_CODEX"' EXIT

  # ---- compose system prompt ----------------------------------------------
  if [[ "$MODE" == "static" ]]; then
    cat >"$TMP_PROMPT" <<EOF
You are tasked with creating study questions for active-recall learning.

OUTPUT FORMAT (exact):
###### Question ######
(one clear recall question)

###### Important points to remember ######
- (3–6 key facts)

###### Answer below ######
(leave blank)

Instructions:
- Strictly follow the structure.
- No extra commentary.
- Question must be unambiguous.

Topic:
$topic
EOF
    outfile="$TARGET_DIR/${filename}.md"
else   # ── dynamic mode ────────────────────────────────────────────────────
  cat >"$TMP_PROMPT" <<'EOF'
SYSTEM: You are crafting a **meta-prompt** that another language-model will use
to create a *mathematics* exercise.

REQUIREMENTS FOR THE META-PROMPT
• Start with a strong imperative verb (Generate / Create / Draft / Pose).  
• Identify the precise topic area (e.g. “discrete mathematics – permutations
  with repetition”).  
• Include at least one concrete parameter to randomise (e.g. “choose n between
  4 and 8” or “use a 5-letter alphabet”).  
• State any constraints clearly (order matters, repetition allowed, etc.).  
• Tell the model to output *only the exercise text*, nothing else.

OUTPUT RULES
• One single sentence, ≤ 160 characters.  
• No quotation marks, no Markdown, no examples, no commentary.  
• Exactly one line—no leading or trailing blank lines.

USER TOPIC SEED:
EOF
  printf '%s\n' "$topic" >>"$TMP_PROMPT"
  outfile="$TARGET_DIR/${filename}.txt"
fi


  # ---- call Codex ----------------------------------------------------------
  codex -m "$MODEL" -q "$(cat "$TMP_PROMPT")" >"$TMP_CODEX" || {
      echo "Codex failed for $outfile" >&2
      exit 0
  }

  # ---- extract model text --------------------------------------------------
  generated=$(jq -r '.content[] | select(.type=="output_text") | .text' <"$TMP_CODEX")

  if [[ "$MODE" == "static" ]]; then
    # cut off everything after "###### Answer below ######"
    generated=$(awk '/^###### Answer below ######/ {exit} {print}' <<<"$generated")
  else
    # dynamic: keep first non-blank line, trim
    generated=$(awk 'NF{print;exit}' <<<"$generated" | xargs)
  fi

  [[ -n "$generated" ]] && { echo "$generated" >"$outfile"; echo "Saved → $outfile"; } \
                        || echo "Empty output – nothing saved for $outfile"

) > /dev/null 2>&1 &        #  ← BUFFER EVERYTHING & RUN IN BG

disown                       # detach from this shell

echo "Started background generation → $TARGET_DIR/${filename}.{md,txt}"
echo "You can safely close the terminal."
