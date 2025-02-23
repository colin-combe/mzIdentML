#!/bin/bash

# Check if tidy is installed
if ! command -v tidy &> /dev/null; then
    echo "Error: tidy is not installed. Please install it and try again."
    exit 1
fi

# Process each AsciiDoc file given as an argument
for file in "$@"; do
    if [[ ! -f "$file" ]]; then
        echo "Skipping: $file is not a valid file"
        continue
    fi

    awk '
    BEGIN {inside=0; content="";}
    /^\[source,xml\]/ {inside=1; print; next;}
    inside && /^----/ {inside++; if (inside == 2) {next;}}  # Start of XML content
    inside == 1 {content = content $0 "\n"; next;}
    inside == 2 {
        # Write content to a temporary file
        tmpfile = "tidy_tmp.xml"
        print content > tmpfile
        close(tmpfile)

        # Run tidy on the temporary file and capture output
        cmd = "tidy -xml -indent -quiet -wrap 0 " tmpfile " 2>/dev/null"
        while ((cmd | getline formatted) > 0) {
            print formatted;
        }
        close(cmd)

        content=""; inside=0;
    }
    !inside {print;}
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

done

echo "Processing complete."
