#!/usr/bin/env python3
"""
Convert nested tables in AsciiDoc to flat section-based layout.
This fixes PDF truncation errors when generating documentation.
"""

import re

def convert_file(input_path, output_path):
    """Convert the AsciiDoc file by removing outer tables with nested content."""

    with open(input_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    result = []
    i = 0

    while i < len(lines):
        line = lines[i].rstrip('\n')

        # Check if we're at an element section with the problematic table structure
        if line.startswith('=== Element'):
            result.append(line)
            i += 1

            # Skip blank lines
            while i < len(lines) and lines[i].strip() == '':
                result.append(lines[i].rstrip('\n'))
                i += 1

            # Check if next line is [cols="1,5"] which indicates outer table
            if i < len(lines) and lines[i].strip() == '[cols="1,5"]':
                # Skip the [cols="1,5"]
                i += 1

                # Skip the opening |===
                if i < len(lines) and lines[i].strip() == '|===':
                    i += 1

                    # Process the outer table content
                    i = process_outer_table(lines, i, result)
                    continue

        # Not a special case, just add the line
        result.append(line)
        i += 1

    # Post-process: remove standalone | | lines that are leftovers
    result = [line for line in result if line.strip() != '| |']

    # Write output
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(result))


def process_outer_table(lines, i, result):
    """Process the content of an outer table and convert to flat format."""

    while i < len(lines):
        line = lines[i].rstrip('\n')

        # Check for end of outer table
        if line == '|===':
            i += 1
            break

        # Definition row
        if line.startswith('|*Definition:*'):
            if line == '|*Definition:* a|':
                # Multi-line definition
                result.append('*Definition:*')
                result.append('')
                i += 1
                # Collect definition lines
                while i < len(lines) and not lines[i].startswith('|*'):
                    result.append(lines[i].rstrip('\n'))
                    i += 1
                continue
            else:
                # Single-line definition
                match = re.match(r'\|\*Definition:\* \|(.+)$', line)
                if match:
                    result.append('*Definition:*')
                    result.append('')
                    result.append(match.group(1))
                    i += 1
                    continue

        # Type row
        elif line.startswith('|*Type:*'):
            match = re.match(r'\|\*Type:\* \|(.+)$', line)
            if match:
                result.append('')
                result.append('*Type:* ' + match.group(1))
                i += 1
                continue

        # Attributes row
        elif line.startswith('|*Attributes:*'):
            if line == '|*Attributes:* |none':
                result.append('')
                result.append('*Attributes:* none')
                i += 1
                continue
            elif line == '|*Attributes:* a|':
                result.append('')
                result.append('*Attributes:*')
                result.append('')
                i += 1
                # Extract nested table
                i = extract_nested_table(lines, i, result)
                continue

        # Subelements row
        elif line.startswith('|*Subelements:*'):
            if line == '|*Subelements:* |none':
                result.append('')
                result.append('*Subelements:* none')
                i += 1
                continue
            elif line == '|*Subelements:* a|':
                result.append('')
                result.append('*Subelements:*')
                result.append('')
                i += 1
                # Extract nested table
                i = extract_nested_table(lines, i, result)
                continue

        # Graphical Context row
        elif line.startswith('|*Graphical Context:*'):
            match = re.match(r'\|\*Graphical Context:\* a\|(.+)$', line)
            if match:
                result.append('')
                result.append('*Graphical Context:*')
                result.append('')
                result.append(match.group(1))
                i += 1
                continue

        # Example Context row
        elif line.startswith('|*Example Context:*'):
            result.append('')
            result.append('*Example Context:*')
            result.append('')
            i += 1
            # Collect all lines until next |* or |===
            while i < len(lines) and not lines[i].startswith('|*') and lines[i].strip() != '|===':
                result.append(lines[i].rstrip('\n'))
                i += 1
            continue

        # cvParam Mapping Rules row
        elif line.startswith('|*cvParam Mapping Rules:*'):
            result.append('')
            result.append('*cvParam Mapping Rules:*')
            result.append('')
            i += 1
            # Collect all lines until next |* or |===
            while i < len(lines) and not lines[i].startswith('|*') and lines[i].strip() != '|===':
                result.append(lines[i].rstrip('\n'))
                i += 1
            continue

        # Example cvParams row
        elif line.startswith('|*Example cvParams:*'):
            result.append('')
            result.append('*Example cvParams:*')
            result.append('')
            i += 1
            # Collect all lines until next |* or |===
            while i < len(lines) and not lines[i].startswith('|*') and lines[i].strip() != '|===':
                result.append(lines[i].rstrip('\n'))
                i += 1
            continue

        # Example userParams row
        elif line.startswith('|*Example userParams:*'):
            result.append('')
            result.append('*Example userParams:*')
            result.append('')
            i += 1
            # Collect all lines until next |* or |===
            while i < len(lines) and not lines[i].startswith('|*') and lines[i].strip() != '|===':
                result.append(lines[i].rstrip('\n'))
                i += 1
            continue

        # Empty row (| |)
        elif line == '| |':
            # Skip empty rows
            i += 1
            continue

        else:
            # Unknown row, skip
            i += 1
            continue

    return i


def extract_nested_table(lines, i, result):
    """Extract a nested table (using ! delimiters) and convert to | delimiters."""

    # Skip any blank lines
    while i < len(lines) and lines[i].strip() == '':
        i += 1

    # Look for [cols=...] line
    if i < len(lines) and lines[i].strip().startswith('[cols='):
        # Found the nested table definition
        cols_line = lines[i].strip().rstrip(',')  # Remove trailing comma
        result.append(cols_line)
        i += 1

        # Now process the table content, converting ! to |
        if i < len(lines) and lines[i].strip() == '!===':
            result.append('|===')
            i += 1

            # Process table rows until we find closing !===
            while i < len(lines):
                line = lines[i].rstrip('\n')

                if line == '!===':
                    result.append('|===')
                    i += 1
                    break
                elif line.startswith('!'):
                    # Convert all ! to |
                    result.append(line.replace('!', '|'))  # Replace all occurrences
                    i += 1
                else:
                    # Continuation line (not starting with !)
                    result.append(line)
                    i += 1

    return i


if __name__ == '__main__':
    import sys

    input_file = 'model-in-xml-schema.adoc'
    output_file = 'model-in-xml-schema-converted.adoc'

    if len(sys.argv) > 1:
        input_file = sys.argv[1]
    if len(sys.argv) > 2:
        output_file = sys.argv[2]

    print(f'Converting {input_file} -> {output_file}')
    convert_file(input_file, output_file)
    print('Done!')
