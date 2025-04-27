#!/bin/bash

set -euo pipefail

# --- SETTINGS ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_DIR="$SCRIPT_DIR/q"
PREFIX_FILE="$SCRIPT_DIR/prefix.md"
FILELIST="$SCRIPT_DIR/filelist.txt"

mkdir -p "$BASE_DIR"

# --- CLEANUP HANDLER ---

cleanup() {
    [[ -f "$FILELIST" ]] && rm -f "$FILELIST"
}
trap cleanup EXIT

# --- LOAD PREFIX ---

if [[ ! -f "$PREFIX_FILE" ]]; then
    echo "Error: System prompt '$PREFIX_FILE' not found. Exiting."
    exit 1
fi

prefix=$(<"$PREFIX_FILE")

# --- CHOOSE DIRECTORY ---

selection=$(
    (find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sed "s|$BASE_DIR/||" || true) \
    | fzf --prompt="Select a directory to test from: " --print-query --bind "enter:accept"
)

if [[ $? -ne 0 ]]; then
    echo "fzf was cancelled. Exiting script."
    exit 1
fi

query=$(echo "$selection" | sed -n '1p')
picked=$(echo "$selection" | sed -n '2p')
dir_choice="${picked:-$query}"

if [[ -z "$dir_choice" ]]; then
    echo "Error: No directory selected or typed. Exiting."
    exit 1
fi

QUESTIONS_DIR="$BASE_DIR/$dir_choice"

echo "Using questions directory: '$QUESTIONS_DIR'"

if [[ ! -d "$QUESTIONS_DIR" ]]; then
    echo "Error: Directory '$QUESTIONS_DIR' does not exist."
    exit 1
fi

# --- START TESTING ---

find "$QUESTIONS_DIR" -type f > "$FILELIST"

if [[ ! -s "$FILELIST" ]]; then
    echo "Error: No questions found in '$QUESTIONS_DIR'."
    exit 1
fi

while true; do
    length=$(wc -l < "$FILELIST")

    if (( length == 0 )); then
        echo "All questions completed!"
        break
    fi

    line=$(shuf -i 1-"$length" -n 1)
    filepath=$(sed -n "${line}p" "$FILELIST" | xargs)

    if [[ ! -f "$filepath" ]]; then
        echo "Warning: file '$filepath' not found. Skipping."
        sed -i "${line}d" "$FILELIST"
        continue
    fi

    question_content=$(awk '/^###### Important points to remember ######/ {exit} {print}' "$filepath")

    if [[ -z "$question_content" ]]; then
        echo "Warning: file '$filepath' had no valid question part. Skipping."
        sed -i "${line}d" "$FILELIST"
        continue
    fi

    tmpfile=$(mktemp)
    echo -e "${question_content}\n\n###### answer below #####\n" > "$tmpfile"

    echo "Please write your answer. Save and quit when done."
    nvim "$tmpfile" || {
        echo "Warning: Neovim exited abnormally. Skipping question."
        rm -f "$tmpfile"
        sed -i "${line}d" "$FILELIST"
        continue
    }

    user_input=$(<"$tmpfile")
    rm -f "$tmpfile"

    if [[ -z "$user_input" ]]; then
        echo "Warning: Empty answer. Skipping."
        sed -i "${line}d" "$FILELIST"
        continue
    fi

absolute_path="$filepath"

augmented_user_input="[Question absolute path: $absolute_path]

$user_input"

input="$prefix

$augmented_user_input"

    # Send to codex
    codex -m gpt-4.1 "$input" || {
        echo "Warning: Codex request failed. Continuing."
    }

    sed -i "${line}d" "$FILELIST"
done
