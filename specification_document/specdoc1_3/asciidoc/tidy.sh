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
    inside == 1 && /^----/ {inside=2; print; next;}  # Start XML block
    inside == 2 && /^----/ {
        # End of XML block, process XML
        tmpfile = "tidy_tmp.xml"
        print content > tmpfile
        close(tmpfile)

        # Run tidy and capture formatted XML
        cmd = "tidy -xml -indent -quiet -wrap 0 " tmpfile " 2>/dev/null"
        formatted = ""
        while ((cmd | getline line) > 0) {
            formatted = formatted line "\n";
        }
        close(cmd)

        # Print formatted XML if available
        if (formatted != "") {
            print formatted;
        } else {
            print content;  # Fall back to original content if tidy fails
        }

        print;  # Print closing ----
        inside=0;
        next;
    }
    inside == 2 {content = content $0 "\n"; next;}  # Collect XML content
    {print;}  # Print everything else
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

done

echo "Processing complete."
