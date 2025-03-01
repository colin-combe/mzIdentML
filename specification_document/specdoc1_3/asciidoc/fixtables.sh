#!/bin/bash

# Process each file given as an argument
for file in "$@"; do
    if [[ ! -f "$file" ]]; then
        echo "Skipping: $file is not a valid file"
        continue
    fi

    awk '
    BEGIN {inside=0;}
    /^\[cols=",,,",options="header",]/ {inside=1; print; next;}  # Start replacing bars
    inside == 1 && /^\|===/ {inside=2;}  # Detect |=== and start replacing it
    inside == 2 { gsub("\\|", "!"); print; inside = 3; next} # Replace | with ! and reset after |===
    inside == 3 { gsub("\\|", "!"); print; if ($0 ~ /^!===/) inside=0; next; } # Replace | with ! and reset after |===
    {print;}
    ' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
done

echo "Processing complete."