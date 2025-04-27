#!/bin/bash

# --- SETTINGS ---

BASE_DIR="$HOME/anki/q"  # or relative like ./questions if you want
mkdir -p "$BASE_DIR"

# --- CHOOSE DIRECTORY ---

selection=$(
    (find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sed "s|$BASE_DIR/||" || true) \
    | fzf --prompt="Select or type new directory: " --print-query --bind "enter:accept"
)

# Immediately check if fzf was cancelled
if [[ $? -ne 0 ]]; then
    echo "fzf was cancelled. Exiting."
    exit 1
fi

query=$(echo "$selection" | sed -n '1p')
picked=$(echo "$selection" | sed -n '2p')

dir_choice="${picked:-$query}"

if [[ -z "$dir_choice" ]]; then
    echo "Error: No directory selected or typed. Exiting."
    exit 1
fi

chosen_dir="$BASE_DIR/$dir_choice"
mkdir -p "$chosen_dir"

# --- MANUAL QUESTION CREATION ---

tmp_question=$(mktemp)

# Prefill with the standard template
cat <<EOF > "$tmp_question"
###### Question ######

###### Important points to remember ######

###### Answer below ######
EOF

# Open Neovim for editing the question manually
echo "Write your question manually. Save and quit when done."
nvim "$tmp_question"

# Read your manually written question
question_content=$(cat "$tmp_question")
rm "$tmp_question"

if [[ -z "$question_content" ]]; then
    echo "Error: Question content was empty. Exiting."
    exit 1
fi

# --- GET FILENAME ---

tmp_filename=$(mktemp)
echo "Write the filename (without extension). Save and quit when done."
nvim "$tmp_filename"

filename=$(cat "$tmp_filename" | xargs)
rm "$tmp_filename"

if [[ -z "$filename" ]]; then
    echo "Error: filename was empty after trimming. Exiting."
    exit 1
fi

# --- SAVE MANUALLY WRITTEN QUESTION ---

# Save the manual question directly
echo "$question_content" > "${chosen_dir}/${filename}.md"

echo "Saved manual question to '${chosen_dir}/${filename}.md'"


