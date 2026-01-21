#!/usr/bin/env python3
"""
Format XML content inside [source,xml] blocks in AsciiDoc files.
Handles documentation-style XML fragments with ellipsis, incomplete tags, etc.
"""

import re
import sys
from xml.dom import minidom
from pathlib import Path


def format_xml(xml_string, indent="    ", return_error=False):
    """Pretty print XML string. Returns original if parsing fails."""
    original = xml_string.strip()
    if not original:
        return (original, None) if return_error else original

    xml_string = original

    # Preserve and temporarily replace ellipsis patterns that break parsing
    placeholders = {}
    placeholder_count = [0]

    def make_placeholder(text):
        placeholder_count[0] += 1
        key = f"__PLACEHOLDER_{placeholder_count[0]}__"
        placeholders[key] = text
        return key

    # Replace >... patterns (truncated content)
    xml_string = re.sub(r'>\.\.\.', lambda m: '>' + make_placeholder('...'), xml_string)

    # Replace ... at end of attributes or content
    xml_string = re.sub(r'\.\.\.(?=<|$|\s*$)', lambda m: make_placeholder('...'), xml_string)

    # Wrap in root element to handle fragments
    wrapped = f"<_root_>{xml_string}</_root_>"

    try:
        dom = minidom.parseString(wrapped.encode('utf-8'))
        pretty = dom.toprettyxml(indent=indent)

        # Remove XML declaration
        lines = pretty.split('\n')
        if lines[0].startswith('<?xml'):
            lines = lines[1:]

        # Remove empty lines and clean up
        result_lines = []
        for line in lines:
            if line.strip():
                result_lines.append(line.rstrip())

        result = '\n'.join(result_lines)

        # Remove the wrapper
        result = re.sub(r'^<_root_>\n?', '', result)
        result = re.sub(r'\n?</_root_>$', '', result)

        # Dedent one level since we removed the wrapper
        dedented_lines = []
        for line in result.split('\n'):
            if line.startswith(indent):
                dedented_lines.append(line[len(indent):])
            else:
                dedented_lines.append(line)
        result = '\n'.join(dedented_lines)

        # Restore placeholders
        for key, value in placeholders.items():
            result = result.replace(key, value)

        return (result, None) if return_error else result

    except Exception as e:
        # If parsing fails, return original unchanged
        return (original, str(e)) if return_error else original


def process_adoc_file(filepath, dry_run=False, list_errors=False, add_comments=False):
    """Process an AsciiDoc file, formatting XML in [source,xml] blocks."""
    content = filepath.read_text(encoding='utf-8')

    # Pattern to match [source,xml] followed by ---- block
    # Use \n---- to ensure we match the closing delimiter at start of line
    pattern = r'(\[source,xml[^\]]*\]\n----\n)(.*?)(\n----)'

    changes = []
    errors = []

    def replace_xml(match):
        prefix = match.group(1)
        xml_content = match.group(2)
        suffix = match.group(3)

        # Calculate line number of this block
        start_pos = match.start()
        line_num = content[:start_pos].count('\n') + 1

        formatted, error = format_xml(xml_content, return_error=True)

        if error:
            errors.append((line_num, error))
            if add_comments:
                # Check if comment already exists
                if '//todo' not in prefix:
                    if 'mismatched tag' in error:
                        comment = "//todo - mismatched tag, probably due to truncation, fix?\n"
                    elif 'invalid token' in error:
                        comment = "//todo - invalid token, probably needs XML escaping (&lt; &gt;), fix?\n"
                    else:
                        comment = f"//todo - XML parse error: {error}, fix?\n"
                    prefix = prefix.replace('[source,xml', comment + '[source,xml')
            return f"{prefix}{xml_content}{suffix}"
        elif formatted != xml_content.strip():
            changes.append(True)

        return f"{prefix}{formatted}{suffix}"

    new_content = re.sub(pattern, replace_xml, content, flags=re.DOTALL)

    if list_errors and errors:
        print(f"\n{filepath}:")
        for line_num, error in errors:
            print(f"  Line {line_num}: {error}")

    if new_content != content:
        if dry_run:
            print(f"Would modify: {filepath} ({len(changes)} blocks formatted)")
        else:
            filepath.write_text(new_content, encoding='utf-8')
            print(f"Modified: {filepath} ({len(changes)} blocks formatted)")
        return True
    else:
        print(f"No changes: {filepath}")
        return False


def main():
    import argparse
    parser = argparse.ArgumentParser(description='Format XML in AsciiDoc [source,xml] blocks')
    parser.add_argument('files', nargs='*', help='AsciiDoc files to process (default: find all .adoc files)')
    parser.add_argument('--dry-run', '-n', action='store_true', help='Show what would be changed without modifying files')
    parser.add_argument('--list-errors', '-e', action='store_true', help='List problematic XML blocks with line numbers')
    parser.add_argument('--add-comments', '-c', action='store_true', help='Add //todo comments before unparseable blocks')
    args = parser.parse_args()

    if args.files:
        files = [Path(f) for f in args.files]
    else:
        files = list(Path('.').rglob('*.adoc'))

    modified = 0
    for f in files:
        if f.suffix == '.adoc' and 'backup' not in f.name:
            if process_adoc_file(f, dry_run=args.dry_run, list_errors=args.list_errors, add_comments=args.add_comments):
                modified += 1

    if not args.list_errors:
        print(f"\n{'Would modify' if args.dry_run else 'Modified'} {modified} file(s)")


if __name__ == '__main__':
    main()
