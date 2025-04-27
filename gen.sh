#!/bin/bash

set -euo pipefail

# --- SETTINGS ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_DIR="$SCRIPT_DIR/q"
DEFAULT_EDITOR="nvim"
CODING_MODEL="gpt-4.1"

mkdir -p "$BASE_DIR"

# --- CLEANUP HANDLER ---

TMP_TOPIC=""
TMP_FILENAME=""
TMP_PROMPT=""
TMP_CODEX=""

cleanup() {
    [[ -n "$TMP_TOPIC" && -f "$TMP_TOPIC" ]] && rm -f "$TMP_TOPIC"
    [[ -n "$TMP_FILENAME" && -f "$TMP_FILENAME" ]] && rm -f "$TMP_FILENAME"
    [[ -n "$TMP_PROMPT" && -f "$TMP_PROMPT" ]] && rm -f "$TMP_PROMPT"
    [[ -n "$TMP_CODEX" && -f "$TMP_CODEX" ]] && rm -f "$TMP_CODEX"
}
trap cleanup EXIT

# --- CHOOSE DIRECTORY ---

selection=$(
    (find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sed "s|$BASE_DIR/||" || true) \
    | fzf --prompt="Select or type new directory: " --print-query --bind "enter:accept"
)

if [[ $? -ne 0 ]]; then
    echo "fzf was cancelled. Exiting script."
    exit 1
fi

query=$(sed -n '1p' <<< "$selection")
picked=$(sed -n '2p' <<< "$selection")
dir_choice="${picked:-$query}"

if [[ -z "$dir_choice" ]]; then
    echo "Error: No directory selected or typed. Exiting."
    exit 1
fi

chosen_dir="$BASE_DIR/$dir_choice"
mkdir -p "$chosen_dir"

# --- GET TOPIC ---

TMP_TOPIC=$(mktemp)
$DEFAULT_EDITOR "$TMP_TOPIC"
topic=$(xargs < "$TMP_TOPIC")

if [[ -z "$topic" ]]; then
    echo "Error: topic was empty after trimming. Exiting."
    exit 1
fi

# --- GET FILENAME ---

TMP_FILENAME=$(mktemp)
$DEFAULT_EDITOR "$TMP_FILENAME"
filename=$(xargs < "$TMP_FILENAME")

if [[ -z "$filename" ]]; then
    echo "Error: filename was empty after trimming. Exiting."
    exit 1
fi

# --- GENERATE PROMPT ---

(
    TMP_PROMPT=$(mktemp)

    cat <<EOF > "$TMP_PROMPT"
You are tasked with creating study questions for active recall learning.

Every output must strictly follow this format:

###### Question ######
(Write a direct recall question related to the topic.)

###### Important points to remember ######
- (List at least 3–5 key facts, definitions, concepts, or steps that the user must recall.)

###### Answer below ######
(Leave this section empty. Do not fill in anything here.)

---

Instructions:
- Only output exactly this markdown structure, no explanations.
- Keep the question short, precise, and unambiguous.
- Important points must be factual, not vague.
- Do not include an explicit "answer" in the Important Points — they are guidance for recall.
- Do not include any extra commentary, intro text, or summary.

---

Now create a question about the following topic:
$topic
EOF

    full_prompt=$(<"$TMP_PROMPT")

    TMP_CODEX=$(mktemp)

    codex -q "$full_prompt" > "$TMP_CODEX" || {
        echo "Error: Codex failed to respond. Exiting."
        rm -f "$TMP_CODEX"
        exit 1
    }

    response=$(<"$TMP_CODEX")

    # Cut out anything after "###### Answer below ######"
    generated_content=$(echo "$response" | jq -r '.content[] | select(.type=="output_text") | .text' 2>/dev/null | awk '
        /^###### Answer below ######/ { exit }
        { print }
    ')

    if [[ -n "$generated_content" ]]; then
        echo "$generated_content" > "${chosen_dir}/${filename}.md"
        echo "Saved to '${chosen_dir}/${filename}.md'"
    else
        echo "Error: Generated content was empty."
    fi
) > /dev/null 2>&1 &

disown

echo "Started background generation for '${chosen_dir}/${filename}.md'. You can exit now."
