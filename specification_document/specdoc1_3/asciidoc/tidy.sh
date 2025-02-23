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

    # When encountering the start of an XML block
    /^\[source,xml\]/ {
        inside=1;
        print;
        next;
    }

    # When inside an XML block and encountering the first "----" line (start of XML content)
    inside == 1 && /^----/ {
        inside=2;
        print;
        next;
    }

    # When inside the XML content, accumulate the lines until the closing "----"
    inside == 2 && /^----/ {
        # Ensure the temporary file is cleared before we write the new content
        tmpfile = "tidy_tmp.xml"
        system("rm -f " tmpfile)  # Remove previous temporary file

        # Write the collected content to the temporary file
        print content > tmpfile
        close(tmpfile)

        # Run tidy to format the XML content
        cmd = "tidy -xml -indent -quiet -wrap 0 --indent-spaces 4 " tmpfile " 2>/dev/null"
        formatted = ""
        while ((cmd | getline line) > 0) {
            formatted = formatted line "\n";
        }
        close(cmd)

        # Print the formatted XML if tidy succeeded, otherwise print original content
        if (formatted != "") {
            print formatted;
        } else {
            print content;  # Fallback to original content if tidy fails
        }

        print;  # Print the closing ---- line
        inside=0;  # Reset "inside" flag
        content="";  # Clear accumulated content for next block
        next;
    }

    # While inside an XML block, accumulate the content
    inside == 2 {
        content = content $0 "\n";
        next;
    }

    # Print everything else (non-XML content) unchanged
    {print;}

    ' "$file" > "$file.tmp"

done

echo "Processing complete."
