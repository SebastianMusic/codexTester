#!/bin/bash

# --- SETTINGS ---

BASE_DIR="$HOME/anki/q"  # or relative like ./questions if you want
mkdir -p "$BASE_DIR"


# --- CHOOSE DIRECTORY ---

# Always allow typing even if no results
selection=$(
    (find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sed "s|$BASE_DIR/||" || true) \
    | fzf --prompt="Select or type new directory: " --print-query
)

query=$(echo "$selection" | sed -n '1p')      # first line = what you typed
picked=$(echo "$selection" | sed -n '2p')     # second line = what you selected (if any)

# Decide which one to use
if [[ -n "$picked" ]]; then
    # If user selected an existing directory
    dir_choice="$picked"
else
    # If user typed something
    dir_choice="$query"
fi

if [[ -z "$dir_choice" ]]; then
    echo "Error: No directory selected or typed. Exiting."
    exit 1
fi

chosen_dir="$BASE_DIR/$dir_choice"

# Create the directory if needed
mkdir -p "$chosen_dir"


# --- GET TOPIC ---

tmp_topic=$(mktemp)
echo "Write your topic. Save and quit when done."
nvim "$tmp_topic"

topic=$(cat "$tmp_topic" | xargs)
rm "$tmp_topic"

if [[ -z "$topic" ]]; then
    echo "Error: topic was empty after trimming. Exiting."
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

# --- GENERATE AND SAVE IN BACKGROUND ---

(
    tmp_prompt=$(mktemp)

    cat <<EOF > "$tmp_prompt"
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

    full_prompt=$(cat "$tmp_prompt")
    rm "$tmp_prompt"

    tmp_codex=$(mktemp)
    codex -q "$full_prompt" > "$tmp_codex"

    response=$(<"$tmp_codex")
    rm "$tmp_codex"

    generated_content=$(echo "$response" | jq -r '.content[] | select(.type=="output_text") | .text' 2>/dev/null | awk '
        BEGIN { found=0 }
        /^###### Answer below ######/ { found=1; print; exit }
        { print }
    ')

    if [[ -n "$generated_content" ]]; then
        echo "$generated_content" > "${chosen_dir}/${filename}.md"
    fi
) > /dev/null 2>&1 &

disown

echo "Started background generation for '${chosen_dir}/${filename}.md'. You can exit now."
