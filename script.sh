#!/bin/bash

# Define where your questions are
QUESTIONS_DIR="q/discrete"

# Print what we interpreted the directory as
echo "Using questions directory: '$QUESTIONS_DIR'"

# Check if the directory actually exists
if [ ! -d "$QUESTIONS_DIR" ]; then
    echo "Error: Directory '$QUESTIONS_DIR' does not exist."
    exit 1
fi

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
