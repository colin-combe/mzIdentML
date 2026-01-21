#!/usr/bin/env python3
"""
Script to compact lines in AsciiDoc cvParam Mapping Rules tables.
Adds AsciiDoc line continuation ( +) and removes blank lines to reduce cell height.
"""

import sys

def should_add_continuation(line, next_content_line):
    """Determine if we should add ' +' to current line and remove blank line."""
    line_stripped = line.rstrip()
    next_stripped = next_content_line.strip()

    # Skip if line is empty or starts with table markers
    if not line_stripped or line_stripped.startswith('|') or line_stripped.startswith('!'):
        return False

    # Pattern 1: e.g.: followed by e.g.:
    if line_stripped.startswith('e.g.:') and next_stripped.startswith('e.g.:'):
        return True

    # Pattern 2: [et al.] followed by MAY/MUST/Path
    if line_stripped.endswith('[et al.]'):
        if next_stripped.startswith(('MAY ', 'MUST ', 'Path ')):
            return True

    # Pattern 3: MAY/MUST line followed by e.g.:
    if line_stripped.startswith(('MAY ', 'MUST ')):
        if next_stripped.startswith('e.g.:'):
            return True

    # Pattern 4: MAY/MUST line followed by another MAY/MUST
    if line_stripped.startswith(('MAY ', 'MUST ')):
        if next_stripped.startswith(('MAY ', 'MUST ')):
            return True

    # Pattern 5: e.g.: (last in group) followed by [et al.] link
    if line_stripped.startswith('e.g.:') and not line_stripped.endswith(' +'):
        if next_stripped.endswith('[et al.]') or next_stripped.startswith('http') and 'et al.' in next_stripped:
            return True

    # Pattern 6: Any line (like Path continuation "Hypothesis") followed by MAY/MUST
    # This catches wrapped Path names where continuation text is on the next line
    if next_stripped.startswith(('MAY ', 'MUST ')):
        # Only if current line doesn't already end with + and is part of mapping rules
        if not line_stripped.endswith(' +') and not line_stripped.startswith(('Path ', '|', '!')):
            return True

    # Pattern 7: Path line followed by MAY/MUST (directly)
    if line_stripped.startswith('Path ') and next_stripped.startswith(('MAY ', 'MUST ')):
        return True

    return False

def fix_lines(content):
    """Process the content and compact lines."""
    lines = content.split('\n')
    result = []
    i = 0

    while i < len(lines):
        line = lines[i]

        # Check if current line is followed by blank line, then another content line
        if i + 2 < len(lines) and lines[i + 1].strip() == '':
            next_content_line = lines[i + 2]

            if should_add_continuation(line, next_content_line):
                # Add ' +' if not already present
                line_stripped = line.rstrip()
                if not line_stripped.endswith(' +'):
                    result.append(line_stripped + ' +')
                else:
                    result.append(line)
                # Skip the blank line
                i += 2
                continue

        result.append(line)
        i += 1

    return '\n'.join(result)

def run_multiple_passes(content, max_passes=10):
    """Run multiple passes until no more changes are made."""
    for pass_num in range(max_passes):
        new_content = fix_lines(content)
        if new_content == content:
            print(f"Converged after {pass_num + 1} passes")
            return new_content
        content = new_content
    print(f"Warning: did not converge after {max_passes} passes")
    return content

if __name__ == '__main__':
    input_file = sys.argv[1] if len(sys.argv) > 1 else 'model-in-xml-schema.adoc'

    with open(input_file, 'r') as f:
        content = f.read()

    original_lines = content.count('\n')
    fixed_content = run_multiple_passes(content)
    new_lines = fixed_content.count('\n')

    with open(input_file, 'w') as f:
        f.write(fixed_content)

    print(f"Fixed {input_file}")
    print(f"Reduced from {original_lines} to {new_lines} lines ({original_lines - new_lines} lines removed)")
