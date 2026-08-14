#!/usr/bin/env python3
"""
compare_adoc_specs.py

Compares two versions of an mzIdentML AsciiDoc specification document and emits
an AsciiDoc "changes" report (added / removed / changed).

Two comparison modes are supported, because the two mzIdentML specification
documents are structured differently:

  --mode element
      For the model documentation (model-in-xml-schema.adoc), which is built
      from "=== Element <Name>" sections, each carrying a *Definition:*, a
      *Type:*, an *Attributes:* table and a *Subelements:* table.  Elements are
      matched by name and compared field by field, including per-attribute and
      per-subelement differences.

  --mode section
      For prose documents such as crosslinking_ext.adoc, which have no element
      structure.  Sections are matched by heading text and reported as added,
      removed or modified.

Usage:
    python3 compare_adoc_specs.py --old OLD.adoc --new NEW.adoc --out OUT.adoc \
        --mode element --title "..." --old-label "1.3.0" --new-label "1.3.x"

This mirrors the equivalent script in the mzTab-M repository, adapted to
mzIdentML's document structure.
"""

import argparse
import os
import re
from dataclasses import dataclass, field
from typing import Optional

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------
@dataclass
class Attribute:
    name: str
    data_type: str = ""
    use: str = ""
    definition: str = ""

    def fields(self) -> dict[str, str]:
        return {
            "Data Type": self.data_type,
            "Use": self.use,
            "Definition": self.definition,
        }


@dataclass
class Subelement:
    name: str
    min_occurs: str = ""
    max_occurs: str = ""
    definition: str = ""

    def fields(self) -> dict[str, str]:
        return {
            "minOccurs": self.min_occurs,
            "maxOccurs": self.max_occurs,
            "Definition": self.definition,
        }


@dataclass
class Element:
    name: str
    definition: str = ""
    type_: str = ""
    attributes: dict[str, Attribute] = field(default_factory=dict)
    subelements: dict[str, Subelement] = field(default_factory=dict)


@dataclass
class Section:
    title: str
    level: int
    body: str = ""


@dataclass
class XsdMember:
    """An attribute or child element declared inside an XML Schema component."""
    name: str
    kind: str = ""
    type_: str = ""
    use: str = ""
    occurs: str = ""
    documentation: str = ""

    def fields(self) -> dict[str, str]:
        return {
            "Kind": self.kind,
            "Type": self.type_,
            "Use": self.use,
            "Occurs": self.occurs,
            "Documentation": self.documentation,
        }


@dataclass
class XsdComponent:
    """A top-level XML Schema component: element, complexType, simpleType, group."""
    name: str
    kind: str = ""
    type_: str = ""
    base: str = ""
    documentation: str = ""
    enumerations: list[str] = field(default_factory=list)
    members: dict[str, XsdMember] = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Normalisation helpers
# ---------------------------------------------------------------------------
def _canon(name: str) -> str:
    """Normalise a name for cross-version matching."""
    n = name.strip().lower()
    # Subelement cells are cross-references: <<element-cvparam>> or
    # <<element-cvparam, cvParam>> -- reduce to the target anchor.
    m = re.match(r"^<<\s*([^,>]+?)\s*(?:,.*)?>>$", n)
    if m:
        n = m.group(1)
    n = n.replace("element-", "")
    n = re.sub(r"[`*_]", "", n)
    n = re.sub(r"\s+", " ", n)
    return n.strip()


def _norm_text(text: str) -> str:
    """Normalise body text so cosmetic whitespace changes are not 'changes'."""
    lines = [l.rstrip() for l in text.strip().splitlines()]
    out: list[str] = []
    for l in lines:
        if not l and out and not out[-1]:
            continue  # collapse runs of blank lines
        out.append(l)
    return "\n".join(out).strip()


# ---------------------------------------------------------------------------
# AsciiDoc table parsing
# ---------------------------------------------------------------------------
def _split_row(line: str) -> list[str]:
    """Split an AsciiDoc table row '|a |b |c' into its cells."""
    return [c.strip() for c in line.lstrip("|").split("|")]


#: Block delimiters that hide their contents from the structural parsers.
#  AsciiDoc requires these to start at column 0, and a block can only be closed
#  by the same delimiter that opened it -- an indented '....' inside a '----'
#  listing is literal content, not a fence.
FENCES = ("----", "....")


def _strip_fenced(lines: list[str]) -> list[str]:
    """Blank out lines inside ----/.... delimited blocks, preserving numbering."""
    out: list[str] = []
    fence: Optional[str] = None
    for line in lines:
        text = line.rstrip()          # keep leading whitespace: fences are col 0
        if fence is None:
            if text in FENCES:
                fence = text
                out.append("")
                continue
        else:
            if text == fence:
                fence = None
            out.append("")
            continue
        out.append(line)
    return out


def _table_blocks(body: str) -> list[list[str]]:
    """Split a body into the line-lists of each |===...|=== delimited table."""
    blocks: list[list[str]] = []
    current: Optional[list[str]] = None
    for line in _strip_fenced(body.splitlines()):
        if line.rstrip() == "|===":
            if current is None:
                current = []          # opening delimiter
            else:
                blocks.append(current)  # closing delimiter
                current = None
            continue
        if current is not None:
            current.append(line)
    return blocks


def _parse_table(body: str, header_first_cell: str) -> list[list[str]]:
    """
    Locate the AsciiDoc table whose header row starts with `header_first_cell`
    and return its data rows as lists of cell strings.

    Cell text may wrap onto continuation lines that do not begin with '|';
    those are appended to the final cell of the current row.
    """
    want = header_first_cell.strip().lower()

    for block in _table_blocks(body):
        rows: list[list[str]] = []
        seen_header = False
        current: Optional[list[str]] = None

        for line in block:
            stripped = line.strip()
            if stripped.startswith("|"):
                cells = _split_row(stripped)
                if not seen_header:
                    first = re.sub(r"[`*_]", "", cells[0]).strip().lower()
                    if first != want:
                        break        # not the table we want; try the next block
                    seen_header = True
                    continue
                if current:
                    rows.append(current)
                current = cells
            elif seen_header and current is not None and stripped:
                current[-1] = (current[-1] + " " + stripped).strip()

        if seen_header:
            if current:
                rows.append(current)
            return rows

    return []


def _parse_attributes(body: str) -> dict[str, Attribute]:
    out: dict[str, Attribute] = {}
    for cells in _parse_table(body, "Attribute Name"):
        cells = (cells + ["", "", "", ""])[:4]
        name = re.sub(r"[`*_]", "", cells[0]).strip()
        if not name:
            continue
        out[_canon(name)] = Attribute(name, cells[1], cells[2], cells[3])
    return out


def _parse_subelements(body: str) -> dict[str, Subelement]:
    out: dict[str, Subelement] = {}
    for cells in _parse_table(body, "Subelement Name"):
        cells = (cells + ["", "", "", ""])[:4]
        raw = cells[0].strip()
        if not raw:
            continue
        out[_canon(raw)] = Subelement(raw, cells[1], cells[2], cells[3])
    return out


# ---------------------------------------------------------------------------
# Element-mode parser
# ---------------------------------------------------------------------------
ELEMENT_RE = re.compile(r"^===\s+Element\s+<(.+?)>\s*$")


def _extract_labelled(body: str, label: str) -> str:
    """
    Extract the value following a '*Label:*' marker.  The value may be inline
    ('*Type:* MzIdentMLType') or on the following lines, and ends at the next
    '*Label:*' marker or a block delimiter.
    """
    pat = re.compile(r"^\*" + re.escape(label) + r":?\*[ \t]*(.*)$", re.M)
    m = pat.search(body)
    if not m:
        return ""
    inline = m.group(1).strip()
    rest = body[m.end():].splitlines()
    collected: list[str] = []
    for line in rest:
        s = line.strip()
        if re.match(r"^\*[A-Za-z][A-Za-z ]*:?\*", s):
            break
        if s in ("|===", "----") or s.startswith("[cols=") or s.startswith("[source"):
            break
        collected.append(line.rstrip())
    value = inline
    tail = _norm_text("\n".join(collected))
    if tail:
        value = (value + "\n" + tail).strip() if value else tail
    return _norm_text(value)


def parse_elements(path: str) -> dict[str, Element]:
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()

    # Detect headings on a fence-stripped view so that anything resembling a
    # heading inside a [source,xml] example cannot start a spurious section;
    # bodies are still sliced from the original lines.
    starts = [
        (i, m.group(1))
        for i, l in enumerate(_strip_fenced(lines))
        if (m := ELEMENT_RE.match(l))
    ]
    elements: dict[str, Element] = {}

    for k, (start, name) in enumerate(starts):
        end = starts[k + 1][0] if k + 1 < len(starts) else len(lines)
        body = "\n".join(lines[start + 1:end])
        el = Element(
            name=name,
            definition=_extract_labelled(body, "Definition"),
            type_=_extract_labelled(body, "Type"),
            attributes=_parse_attributes(body),
            subelements=_parse_subelements(body),
        )
        elements[_canon(name)] = el
    return elements


# ---------------------------------------------------------------------------
# Section-mode parser
# ---------------------------------------------------------------------------
HEADING_RE = re.compile(r"^(={2,4})\s+(.+?)\s*$")


def parse_sections(path: str) -> dict[str, Section]:
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()

    starts: list[tuple[int, int, str]] = []
    for i, l in enumerate(_strip_fenced(lines)):
        m = HEADING_RE.match(l)
        if m:
            starts.append((i, len(m.group(1)), m.group(2)))

    sections: dict[str, Section] = {}
    for k, (start, level, title) in enumerate(starts):
        end = starts[k + 1][0] if k + 1 < len(starts) else len(lines)
        body = _norm_text("\n".join(lines[start + 1:end]))
        key = _canon(title)
        if key in sections:  # disambiguate repeated headings
            n = 2
            while f"{key} #{n}" in sections:
                n += 1
            key = f"{key} #{n}"
        sections[key] = Section(title=title, level=level, body=body)
    return sections


# ---------------------------------------------------------------------------
# XML Schema parser
# ---------------------------------------------------------------------------
XS = "{http://www.w3.org/2001/XMLSchema}"


def _xsd_doc(node) -> str:
    """Concatenated xsd:documentation text directly annotating a node."""
    parts: list[str] = []
    for ann in node.findall(f"{XS}annotation"):
        for doc in ann.findall(f"{XS}documentation"):
            text = "".join(doc.itertext()).strip()
            if text:
                parts.append(re.sub(r"\s+", " ", text))
    return " ".join(parts)


def _xsd_members(node) -> dict[str, XsdMember]:
    """Attributes and child element declarations inside a component."""
    members: dict[str, XsdMember] = {}

    for attr in node.iter(f"{XS}attribute"):
        name = attr.get("name") or attr.get("ref")
        if not name:
            continue
        members[f"attribute:{_canon(name)}"] = XsdMember(
            name=name,
            kind="attribute",
            type_=attr.get("type", ""),
            use=attr.get("use", ""),
            documentation=_xsd_doc(attr),
        )

    for el in node.iter(f"{XS}element"):
        if el is node:
            continue
        name = el.get("name") or el.get("ref")
        if not name:
            continue
        lo = el.get("minOccurs", "1")
        hi = el.get("maxOccurs", "1")
        members[f"element:{_canon(name)}"] = XsdMember(
            name=name,
            kind="element",
            type_=el.get("type", ""),
            occurs=f"{lo}..{hi}",
            documentation=_xsd_doc(el),
        )

    return members


def parse_xsd(path: str) -> dict[str, XsdComponent]:
    """Parse the top-level components of an XML Schema document."""
    import xml.etree.ElementTree as ET

    root = ET.parse(path).getroot()
    components: dict[str, XsdComponent] = {}

    for child in root:
        tag = child.tag
        if not tag.startswith(XS):
            continue
        kind = tag[len(XS):]
        if kind not in ("element", "complexType", "simpleType", "group"):
            continue
        name = child.get("name")
        if not name:
            continue

        base = ""
        enums: list[str] = []
        for restr in child.iter(f"{XS}restriction"):
            base = base or restr.get("base", "")
            for en in restr.findall(f"{XS}enumeration"):
                enums.append(en.get("value", ""))
        for ext in child.iter(f"{XS}extension"):
            base = base or ext.get("base", "")

        components[f"{kind}:{_canon(name)}"] = XsdComponent(
            name=name,
            kind=kind,
            type_=child.get("type", ""),
            base=base,
            documentation=_xsd_doc(child),
            enumerations=enums,
            members=_xsd_members(child),
        )

    return components


# ---------------------------------------------------------------------------
# AsciiDoc rendering helpers
# ---------------------------------------------------------------------------
def _cell(text: str) -> str:
    """Escape text for a regular AsciiDoc table cell."""
    if not text:
        return "—"
    text = text.replace("|", "{vbar}")
    lines = [l.rstrip() for l in text.splitlines() if l.rstrip()]
    return (" +\n").join(lines).strip() or "—"


def _ordered_keys(old: dict, new: dict) -> list[str]:
    """Old order first, then keys that only exist in new."""
    keys = list(old.keys())
    keys += [k for k in new.keys() if k not in old]
    return keys


# ---------------------------------------------------------------------------
# Element comparison
# ---------------------------------------------------------------------------
def _element_changes(a: Element, b: Element) -> list[str]:
    """Human-readable list of what differs between two elements."""
    changed: list[str] = []
    if _norm_text(a.definition) != _norm_text(b.definition):
        changed.append("Definition")
    if _norm_text(a.type_) != _norm_text(b.type_):
        changed.append("Type")

    for label, old_map, new_map in (
        ("Attributes", a.attributes, b.attributes),
        ("Subelements", a.subelements, b.subelements),
    ):
        added = [k for k in new_map if k not in old_map]
        removed = [k for k in old_map if k not in new_map]
        modified = [
            k for k in old_map
            if k in new_map and old_map[k].fields() != new_map[k].fields()
        ]
        bits = []
        if added:
            bits.append(f"{len(added)} added")
        if removed:
            bits.append(f"{len(removed)} removed")
        if modified:
            bits.append(f"{len(modified)} modified")
        if bits:
            changed.append(f"{label} ({', '.join(bits)})")
    return changed


def _render_member_table(
    out: list[str],
    heading: str,
    columns: list[str],
    old_map: dict,
    new_map: dict,
    old_label: str,
    new_label: str,
) -> None:
    """Render an added/removed/modified table for attributes or subelements."""
    added = [k for k in new_map if k not in old_map]
    removed = [k for k in old_map if k not in new_map]
    modified = [
        k for k in old_map
        if k in new_map and old_map[k].fields() != new_map[k].fields()
    ]
    if not (added or removed or modified):
        return

    out.append(f"*{heading}*")
    out.append("")
    out.append('[cols="2,1,~",options="header"]')
    out.append("|===")
    out.append(f"| Name | Change | Detail")
    out.append("")

    for k in added:
        m = new_map[k]
        detail = "; ".join(f"{c}: {m.fields()[c]}" for c in columns if m.fields().get(c))
        out.append(f"| `{_cell(m.name)}`")
        out.append(f"| 🟢 Added")
        out.append(f"| {_cell(detail)}")
        out.append("")
    for k in removed:
        m = old_map[k]
        detail = "; ".join(f"{c}: {m.fields()[c]}" for c in columns if m.fields().get(c))
        out.append(f"| `{_cell(m.name)}`")
        out.append(f"| 🔴 Removed")
        out.append(f"| {_cell(detail)}")
        out.append("")
    for k in modified:
        o, n = old_map[k], new_map[k]
        diffs = [c for c in columns if o.fields().get(c, "") != n.fields().get(c, "")]
        detail = " +\n".join(
            f"{c}: {old_label} `{o.fields().get(c) or '—'}` → "
            f"{new_label} `{n.fields().get(c) or '—'}`"
            for c in diffs
        )
        out.append(f"| `{_cell(n.name)}`")
        out.append(f"| ⚠️ Changed")
        out.append(f"| {detail}")
        out.append("")

    out.append("|===")
    out.append("")


def render_element_report(
    old: dict[str, Element],
    new: dict[str, Element],
    title: str,
    old_label: str,
    new_label: str,
    doc_label: str = "Model in XML Schema",
) -> str:
    out: list[str] = []
    keys = _ordered_keys(old, new)

    added = [k for k in keys if k not in old]
    removed = [k for k in keys if k not in new]
    changed = [
        k for k in keys
        if k in old and k in new and _element_changes(old[k], new[k])
    ]

    out.append(f"= {title}")
    out.append(":toc: left")
    out.append(":toclevels: 3")
    out.append("")
    out.append(
        f"Element-by-element comparison of the mzIdentML model documentation "
        f"between {old_label} and {new_label}."
    )
    out.append("")
    out.append("*Legend:*")
    out.append("")
    out.append(f"* 🟢 *Added in {new_label}* – element is new, not present in {old_label}")
    out.append(f"* 🔴 *Removed in {new_label}* – element existed in {old_label} but is absent in {new_label}")
    out.append("* ⚠️ *Changed* – the definition, type, attributes or subelements differ")
    out.append("")

    out.append("== Summary")
    out.append("")
    out.append('[cols="~,1,1,1,1,1",options="header"]')
    out.append("|===")
    out.append(f"| Document | {old_label} elements | {new_label} elements | Added | Removed | Changed")
    out.append("")
    out.append(
        f"| {doc_label} | {len(old)} | {len(new)} | "
        f"{len(added)} | {len(removed)} | {len(changed)}"
    )
    out.append("")
    out.append("|===")
    out.append("")

    if not (added or removed or changed):
        out.append(
            f"No element-level differences were found between {old_label} and "
            f"{new_label}."
        )
        out.append("")
        return "\n".join(out)

    if added:
        out.append(f"== 🟢 Elements added in {new_label}")
        out.append("")
        out.append('[cols="2,~",options="header"]')
        out.append("|===")
        out.append("| Element | Definition")
        out.append("")
        for k in added:
            out.append(f"| `<{_cell(new[k].name)}>`")
            out.append(f"| {_cell(new[k].definition)}")
            out.append("")
        out.append("|===")
        out.append("")

    if removed:
        out.append(f"== 🔴 Elements removed in {new_label}")
        out.append("")
        out.append('[cols="2,~",options="header"]')
        out.append("|===")
        out.append("| Element | Definition")
        out.append("")
        for k in removed:
            out.append(f"| `<{_cell(old[k].name)}>`")
            out.append(f"| {_cell(old[k].definition)}")
            out.append("")
        out.append("|===")
        out.append("")

    if changed:
        out.append("== ⚠️ Elements changed")
        out.append("")
        for k in changed:
            o, n = old[k], new[k]
            out.append(f"=== `<{n.name}>`")
            out.append("")
            out.append(f"NOTE: Changed: {', '.join(_element_changes(o, n))}")
            out.append("")

            if _norm_text(o.definition) != _norm_text(n.definition):
                out.append('[cols="1,~",options="header"]')
                out.append("|===")
                out.append(f"| Field | Value")
                out.append("")
                out.append(f"| Definition ({old_label})")
                out.append(f"| {_cell(o.definition)}")
                out.append("")
                out.append(f"| Definition ({new_label})")
                out.append(f"| {_cell(n.definition)}")
                out.append("")
                out.append("|===")
                out.append("")

            if _norm_text(o.type_) != _norm_text(n.type_):
                out.append(
                    f"*Type:* {old_label} `{o.type_ or '—'}` → "
                    f"{new_label} `{n.type_ or '—'}`"
                )
                out.append("")

            _render_member_table(
                out, "Attributes", ["Data Type", "Use", "Definition"],
                o.attributes, n.attributes, old_label, new_label,
            )
            _render_member_table(
                out, "Subelements", ["minOccurs", "maxOccurs", "Definition"],
                o.subelements, n.subelements, old_label, new_label,
            )

    return "\n".join(out)


# ---------------------------------------------------------------------------
# Section comparison
# ---------------------------------------------------------------------------
def render_section_report(
    old: dict[str, Section],
    new: dict[str, Section],
    title: str,
    old_label: str,
    new_label: str,
    doc_label: str = "Document",
) -> str:
    out: list[str] = []
    keys = _ordered_keys(old, new)

    added = [k for k in keys if k not in old]
    removed = [k for k in keys if k not in new]
    changed = [
        k for k in keys
        if k in old and k in new and old[k].body != new[k].body
    ]

    out.append(f"= {title}")
    out.append(":toc: left")
    out.append(":toclevels: 3")
    out.append("")
    out.append(
        f"Section-by-section comparison between {old_label} and {new_label}. "
        "This document has no element structure, so it is compared by section "
        "heading; sections whose text differs are listed as modified."
    )
    out.append("")
    out.append("*Legend:*")
    out.append("")
    out.append(f"* 🟢 *Added in {new_label}* – section is new")
    out.append(f"* 🔴 *Removed in {new_label}* – section no longer present")
    out.append("* ⚠️ *Modified* – section text differs")
    out.append("")

    out.append("== Summary")
    out.append("")
    out.append('[cols="~,1,1,1,1,1",options="header"]')
    out.append("|===")
    out.append(f"| Document | {old_label} sections | {new_label} sections | Added | Removed | Modified")
    out.append("")
    out.append(
        f"| {doc_label} | {len(old)} | {len(new)} | "
        f"{len(added)} | {len(removed)} | {len(changed)}"
    )
    out.append("")
    out.append("|===")
    out.append("")

    if not (added or removed or changed):
        out.append(
            f"No section-level differences were found between {old_label} and "
            f"{new_label}."
        )
        out.append("")
        return "\n".join(out)

    def _list_table(heading: str, items: list[str], src: dict[str, Section]) -> None:
        if not items:
            return
        out.append(f"== {heading}")
        out.append("")
        out.append('[cols="1,~",options="header"]')
        out.append("|===")
        out.append("| Level | Section")
        out.append("")
        for k in items:
            s = src[k]
            out.append(f"| {'=' * s.level}")
            out.append(f"| {_cell(s.title)}")
            out.append("")
        out.append("|===")
        out.append("")

    _list_table(f"🟢 Sections added in {new_label}", added, new)
    _list_table(f"🔴 Sections removed in {new_label}", removed, old)

    if changed:
        out.append("== ⚠️ Sections modified")
        out.append("")
        out.append('[cols="1,~,1,1",options="header"]')
        out.append("|===")
        out.append(f"| Level | Section | {old_label} lines | {new_label} lines")
        out.append("")
        for k in changed:
            o, n = old[k], new[k]
            out.append(f"| {'=' * n.level}")
            out.append(f"| {_cell(n.title)}")
            out.append(f"| {len(o.body.splitlines())}")
            out.append(f"| {len(n.body.splitlines())}")
            out.append("")
        out.append("|===")
        out.append("")
        out.append(
            "NOTE: Section text differences are summarised by line count only. "
            "Use `git diff` on the source document to review the wording changes."
        )
        out.append("")

    return "\n".join(out)


# ---------------------------------------------------------------------------
# XML Schema comparison
# ---------------------------------------------------------------------------
def _xsd_changes(a: XsdComponent, b: XsdComponent) -> list[str]:
    changed: list[str] = []
    if _norm_text(a.documentation) != _norm_text(b.documentation):
        changed.append("Documentation")
    if a.type_ != b.type_:
        changed.append("Type")
    if a.base != b.base:
        changed.append("Base")
    if a.enumerations != b.enumerations:
        added = [e for e in b.enumerations if e not in a.enumerations]
        removed = [e for e in a.enumerations if e not in b.enumerations]
        bits = []
        if added:
            bits.append(f"{len(added)} added")
        if removed:
            bits.append(f"{len(removed)} removed")
        changed.append(f"Enumerations ({', '.join(bits)})" if bits else "Enumerations")

    added = [k for k in b.members if k not in a.members]
    removed = [k for k in a.members if k not in b.members]
    modified = [
        k for k in a.members
        if k in b.members and a.members[k].fields() != b.members[k].fields()
    ]
    bits = []
    if added:
        bits.append(f"{len(added)} added")
    if removed:
        bits.append(f"{len(removed)} removed")
    if modified:
        bits.append(f"{len(modified)} modified")
    if bits:
        changed.append(f"Attributes/elements ({', '.join(bits)})")
    return changed


def render_xsd_report(
    old: dict[str, XsdComponent],
    new: dict[str, XsdComponent],
    title: str,
    old_label: str,
    new_label: str,
    doc_label: str = "XML Schema",
) -> str:
    out: list[str] = []
    keys = _ordered_keys(old, new)

    added = [k for k in keys if k not in old]
    removed = [k for k in keys if k not in new]
    changed = [
        k for k in keys
        if k in old and k in new and _xsd_changes(old[k], new[k])
    ]

    out.append(f"= {title}")
    out.append(":toc: left")
    out.append(":toclevels: 3")
    out.append("")
    out.append(
        f"Comparison of the XML Schema definition between {old_label} and "
        f"{new_label}, covering global elements, complex types, simple types "
        "and groups, together with the attributes and child elements each "
        "declares."
    )
    out.append("")
    out.append("*Legend:*")
    out.append("")
    out.append(f"* 🟢 *Added in {new_label}* – component is new")
    out.append(f"* 🔴 *Removed in {new_label}* – component no longer present")
    out.append("* ⚠️ *Changed* – documentation, type, base, enumerations or members differ")
    out.append("")

    out.append("== Summary")
    out.append("")
    out.append('[cols="~,1,1,1,1,1",options="header"]')
    out.append("|===")
    out.append(f"| Document | {old_label} components | {new_label} components | Added | Removed | Changed")
    out.append("")
    out.append(
        f"| {doc_label} | {len(old)} | {len(new)} | "
        f"{len(added)} | {len(removed)} | {len(changed)}"
    )
    out.append("")
    out.append("|===")
    out.append("")

    if not (added or removed or changed):
        out.append(
            f"No schema-level differences were found between {old_label} and "
            f"{new_label}."
        )
        out.append("")
        return "\n".join(out)

    def _list_table(heading: str, items: list[str], src: dict[str, XsdComponent]) -> None:
        if not items:
            return
        out.append(f"== {heading}")
        out.append("")
        out.append('[cols="1,2,~",options="header"]')
        out.append("|===")
        out.append("| Kind | Name | Documentation")
        out.append("")
        for k in items:
            c = src[k]
            out.append(f"| {c.kind}")
            out.append(f"| `{_cell(c.name)}`")
            out.append(f"| {_cell(c.documentation)}")
            out.append("")
        out.append("|===")
        out.append("")

    _list_table(f"🟢 Components added in {new_label}", added, new)
    _list_table(f"🔴 Components removed in {new_label}", removed, old)

    if changed:
        out.append("== ⚠️ Components changed")
        out.append("")
        for k in changed:
            o, n = old[k], new[k]
            out.append(f"=== `{n.name}` ({n.kind})")
            out.append("")
            out.append(f"NOTE: Changed: {', '.join(_xsd_changes(o, n))}")
            out.append("")

            if _norm_text(o.documentation) != _norm_text(n.documentation):
                out.append('[cols="1,~",options="header"]')
                out.append("|===")
                out.append("| Field | Value")
                out.append("")
                out.append(f"| Documentation ({old_label})")
                out.append(f"| {_cell(o.documentation)}")
                out.append("")
                out.append(f"| Documentation ({new_label})")
                out.append(f"| {_cell(n.documentation)}")
                out.append("")
                out.append("|===")
                out.append("")

            for lbl, ov, nv in (("Type", o.type_, n.type_), ("Base", o.base, n.base)):
                if ov != nv:
                    out.append(f"*{lbl}:* {old_label} `{ov or '—'}` → {new_label} `{nv or '—'}`")
                    out.append("")

            if o.enumerations != n.enumerations:
                enum_added = [e for e in n.enumerations if e not in o.enumerations]
                enum_removed = [e for e in o.enumerations if e not in n.enumerations]
                if enum_added:
                    out.append(f"*Enumerations added:* {', '.join('`%s`' % e for e in enum_added)}")
                    out.append("")
                if enum_removed:
                    out.append(f"*Enumerations removed:* {', '.join('`%s`' % e for e in enum_removed)}")
                    out.append("")

            _render_member_table(
                out, "Attributes and child elements",
                ["Kind", "Type", "Use", "Occurs", "Documentation"],
                o.members, n.members, old_label, new_label,
            )

    return "\n".join(out)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare two versions of an mzIdentML AsciiDoc specification document.",
    )
    parser.add_argument("--old", required=True, metavar="PATH",
                        help="Path to the old (baseline) AsciiDoc file")
    parser.add_argument("--new", required=True, metavar="PATH",
                        help="Path to the new (current) AsciiDoc file")
    parser.add_argument("--out", required=True, metavar="PATH",
                        help="Path of the AsciiDoc report to write")
    parser.add_argument("--mode", choices=("element", "section", "xsd"), default="element",
                        help="Comparison granularity (default: %(default)s)")
    parser.add_argument("--title", default=None, help="Report document title")
    parser.add_argument("--old-label", default="1.3.0", help="Label for the old version")
    parser.add_argument("--new-label", default="1.3.x", help="Label for the new version")
    parser.add_argument("--doc-label", default=None,
                        help="Name of the document, used in the summary table row")
    args = parser.parse_args()

    for path in (args.old, args.new):
        if not os.path.isfile(path):
            raise SystemExit(f"ERROR: input not found: {path}")

    if args.mode == "element":
        title = args.title or (
            f"mzIdentML Element Comparison: {args.old_label} vs {args.new_label}"
        )
        old = parse_elements(args.old)
        new = parse_elements(args.new)
        print(f"Parsed old spec: {args.old} ({len(old)} elements)")
        print(f"Parsed new spec: {args.new} ({len(new)} elements)")
        report = render_element_report(
            old, new, title, args.old_label, args.new_label,
            args.doc_label or "Model in XML Schema",
        )
    elif args.mode == "xsd":
        title = args.title or (
            f"mzIdentML Schema Comparison: {args.old_label} vs {args.new_label}"
        )
        old = parse_xsd(args.old)
        new = parse_xsd(args.new)
        print(f"Parsed old schema: {args.old} ({len(old)} components)")
        print(f"Parsed new schema: {args.new} ({len(new)} components)")
        report = render_xsd_report(
            old, new, title, args.old_label, args.new_label,
            args.doc_label or "XML Schema",
        )
    else:
        title = args.title or (
            f"{args.doc_label or 'mzIdentML'} Section Comparison: "
            f"{args.old_label} vs {args.new_label}"
        )
        old = parse_sections(args.old)
        new = parse_sections(args.new)
        print(f"Parsed old spec: {args.old} ({len(old)} sections)")
        print(f"Parsed new spec: {args.new} ({len(new)} sections)")
        report = render_section_report(
            old, new, title, args.old_label, args.new_label,
            args.doc_label or "Document",
        )

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(report + "\n")
    print(f"Wrote comparison to: {args.out}")


if __name__ == "__main__":
    main()
