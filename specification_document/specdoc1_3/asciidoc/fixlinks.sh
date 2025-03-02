#!/bin/bash

# Define the input file
INPUT_FILE="model-in-xml-schema.adoc"
TEMP_FILE="temp.adoc"

# Use awk to process the file

awk '
{
    if (match($0, /^=== Element <([a-zA-Z0-9_-]+)>$/, groups)) {
        # Replace the previous line with the new replacement text
        if (prev_line) {
            print "[[element-" tolower(groups[1]) ", " groups[1] "]]";
            prev_line = "";
        }
        print;  # Print the matched "=== Element <ANYSTRING>" line
    } else {
        # Store the previous line (it might need to be replaced)
        if (prev_line) {
            print prev_line;
        }
        prev_line = $0;  # Save the current line as the previous line
    }
}
END {
    # If theres a leftover previous line, print it
    if (prev_line) print prev_line;
}' "$INPUT_FILE" > "$TEMP_FILE"

# Replace the original file with the modified content
mv "$TEMP_FILE" "$INPUT_FILE"

echo "Replacement completed in $INPUT_FILE"
