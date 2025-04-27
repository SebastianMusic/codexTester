#!/bin/bash

set -euo pipefail

# --- SETTINGS ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_DIR="$SCRIPT_DIR/q"
DEFAULT_EDITOR="nvim"

mkdir -p "$BASE_DIR"

# --- CLEANUP HANDLER ---

TMP_QUESTION=""
TMP_FILENAME=""

cleanup() {
    [[ -n "$TMP_QUESTION" && -f "$TMP_QUESTION" ]] && rm -f "$TMP_QUESTION"
    [[ -n "$TMP_FILENAME" && -f "$TMP_FILENAME" ]] && rm -f "$TMP_FILENAME"
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

# --- MANUAL QUESTION CREATION ---

TMP_QUESTION=$(mktemp)

cat <<EOF > "$TMP_QUESTION"
###### Question ######

###### Important points to remember ######

EOF

echo "Write your question manually. Save and quit when done."
$DEFAULT_EDITOR "$TMP_QUESTION" || {
    echo "Error: Editor exited abnormally. Exiting."
    exit 1
}

question_content=$(<"$TMP_QUESTION")

if [[ -z "$question_content" ]]; then
    echo "Error: Question content was empty after editing. Exiting."
    exit 1
fi

# --- GET FILENAME ---

TMP_FILENAME=$(mktemp)
echo "Write the filename (without extension). Save and quit when done." > "$TMP_FILENAME"
$DEFAULT_EDITOR "$TMP_FILENAME" || {
    echo "Error: Editor exited abnormally. Exiting."
    exit 1
}

filename=$(xargs < "$TMP_FILENAME")

if [[ -z "$filename" ]]; then
    echo "Error: Filename was empty after trimming. Exiting."
    exit 1
fi

# --- SAVE QUESTION ---

output_file="${chosen_dir}/${filename}.md"

# Check if file already exists
if [[ -f "$output_file" ]]; then
    echo "Warning: File '$output_file' already exists. Overwrite? (y/N)"
    read -r answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        echo "Cancelled saving. Exiting."
        exit 1
    fi
fi

echo "$question_content" > "$output_file"
echo "Saved manual question to '${output_file}'"
