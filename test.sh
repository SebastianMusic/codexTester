#!/bin/bash

# --- SETTINGS ---

BASE_DIR="$HOME/anki/q"  # Or wherever your main questions folder is

mkdir -p "$BASE_DIR"

# --- CHOOSE DIRECTORY ---

selection=$(
    (find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sed "s|$BASE_DIR/||" || true) \
    | fzf --prompt="Select a directory to test from: " --print-query --bind "enter:accept"
)

query=$(echo "$selection" | sed -n '1p')
picked=$(echo "$selection" | sed -n '2p')

dir_choice="${picked:-$query}"

if [[ -z "$dir_choice" ]]; then
    echo "Error: No directory selected or typed. Exiting."
    exit 1
fi

QUESTIONS_DIR="$BASE_DIR/$dir_choice"

# Print what we interpreted the directory as
echo "Using questions directory: '$QUESTIONS_DIR'"

# Check if the directory actually exists
if [ ! -d "$QUESTIONS_DIR" ]; then
    echo "Error: Directory '$QUESTIONS_DIR' does not exist."
    exit 1
fi

# --- START TESTING ---

# Generate list of files from the directory
find "$QUESTIONS_DIR" -type f > filelist.txt

length=1
prefix=$(cat prefix.md)

while (( length > 0 )); do
    length=$(wc -l < filelist.txt)
    
    if (( length == 0 )); then
        break
    fi

    # Pick random file path
    line=$(shuf -i 1-${length} -n 1)
    filepath=$(sed -n "${line}p" filelist.txt | xargs)

    # Read entire content of the selected file
    question_content=$(<"$filepath")

    # Prepare temp file
    tmpfile=$(mktemp)
    echo -e "${question_content}\n\n###### answer below #####\n" > "$tmpfile"

    echo "Please write your answer. Save and quit when done."
    nvim "$tmpfile"

    user_input=$(<"$tmpfile")
    rm "$tmpfile"

    # Combine prefix + user input (which includes question and answer)
    input="${prefix}${user_input}"

    codex -m gpt-4.1 "$input"

    # Remove the used file path from filelist.txt
    sed -i "${line}d" filelist.txt
done
