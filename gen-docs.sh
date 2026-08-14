#!/bin/bash
# Regenerate AsciiDoc documentation partials for the Antora documentation site.
#
# The specification is authored as standalone AsciiDoc documents under
# specification_document/specdoc1_3/asciidoc/ (which are also built to
# HTML/PDF/DOCX by build-docs.sh for release artifacts).  This script strips
# the standalone document headers so the bodies can be pulled into Antora pages
# via include::partial$...[] directives.
#
# Run this script whenever:
#   - specification_document/specdoc1_3/asciidoc/mzidentml.adoc changes
#   - specification_document/specdoc1_3/asciidoc/model-in-xml-schema.adoc changes
#   - specification_document/specdoc1_3/asciidoc/crosslinking_ext.adoc changes
#
# It also generates the "changes" documents that compare the released 1.3.0
# specification against the current (1.3.x) source -- see the --changes flag.
#
# Usage:
#   ./gen-docs.sh              # regenerate spec + crosslinking + changes
#   ./gen-docs.sh --spec       # regenerate the main specification partial only
#   ./gen-docs.sh --crosslinking   # regenerate the crosslinking extension partial only
#   ./gen-docs.sh --changes    # regenerate the 1.3.0 -> 1.3.x changes documents only
#   ./gen-docs.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ADOC_SRC="${SCRIPT_DIR}/specification_document/specdoc1_3/asciidoc"
PARTIALS_DIR="${SCRIPT_DIR}/docs/mzidentml/modules/developers/partials"

SPEC_SRC="${ADOC_SRC}/mzidentml.adoc"
SPEC_PARTIAL="${PARTIALS_DIR}/mzidentml.adoc"
MODEL_SRC="${ADOC_SRC}/model-in-xml-schema.adoc"
MODEL_PARTIAL="${PARTIALS_DIR}/model-in-xml-schema.adoc"

XL_SRC="${ADOC_SRC}/crosslinking_ext.adoc"
XL_PARTIAL="${PARTIALS_DIR}/crosslinking_ext.adoc"

# --- Changes documents --------------------------------------------------------
# Frozen copies of the released text act as the comparison baseline.  Refresh
# them only when a new version is released (i.e. when today's source becomes
# the new baseline).
CHANGES_PY="${SCRIPT_DIR}/compare_adoc_specs.py"

CHANGES_OLD_LABEL="1.3.0"
CHANGES_NEW_LABEL="1.3.x"

# Main specification prose (mzidentml.adoc).  Compared section by section: its
# own body is narrative, and the element definitions it include::s from
# model-in-xml-schema.adoc are compared separately below.
SPEC_CHANGES_OLD="${ADOC_SRC}/mzidentml_1_3_0.adoc"
SPEC_CHANGES_NEW="${SPEC_SRC}"
SPEC_CHANGES_OUT="${ADOC_SRC}/mzidentml_1_3_0_to_1_3_x_changes.adoc"
SPEC_CHANGES_PARTIAL="${PARTIALS_DIR}/mzidentml_1_3_0_to_1_3_x_changes.adoc"

# Model documentation (model-in-xml-schema.adoc), compared element by element.
CHANGES_OLD="${ADOC_SRC}/model-in-xml-schema_1_3_0.adoc"
CHANGES_NEW="${MODEL_SRC}"
CHANGES_OUT="${ADOC_SRC}/model-in-xml-schema_1_3_0_to_1_3_x_changes.adoc"
CHANGES_PARTIAL="${PARTIALS_DIR}/model-in-xml-schema_1_3_0_to_1_3_x_changes.adoc"

# XML Schema.  Every released schema is checked in under schema/ as its own
# versioned file, so no frozen baseline is needed: mzIdentML1.3.0.xsd *is* the
# released 1.3.0 schema.  The current schema is the highest-versioned file
# present, so a future mzIdentML1.3.1.xsd is picked up automatically.
XSD_DIR="${SCRIPT_DIR}/schema"
XSD_CHANGES_OLD="${XSD_DIR}/mzIdentML1.3.0.xsd"
# '|| true' keeps a no-match glob from aborting the script under 'set -e';
# run_comparison reports the missing file properly instead.
XSD_CHANGES_NEW="$(ls -1 "${XSD_DIR}"/mzIdentML*.xsd 2>/dev/null | sort -V | tail -1 || true)"
XSD_CHANGES_OUT="${ADOC_SRC}/mzidentml_schema_1_3_0_to_1_3_x_changes.adoc"
XSD_CHANGES_PARTIAL="${PARTIALS_DIR}/mzidentml_schema_1_3_0_to_1_3_x_changes.adoc"

XL_CHANGES_OLD_LABEL="1.0.0"
XL_CHANGES_NEW_LABEL="1.0.x"
XL_CHANGES_OLD="${ADOC_SRC}/crosslinking_ext_1_0_0.adoc"
XL_CHANGES_NEW="${XL_SRC}"
XL_CHANGES_OUT="${ADOC_SRC}/crosslinking_ext_1_0_0_to_1_0_x_changes.adoc"
XL_CHANGES_PARTIAL="${PARTIALS_DIR}/crosslinking_ext_1_0_0_to_1_0_x_changes.adoc"

DO_SPEC=true
DO_XL=true
DO_CHANGES=true

for arg in "$@"; do
  case "$arg" in
    --spec)         DO_SPEC=true;  DO_XL=false; DO_CHANGES=false ;;
    --crosslinking) DO_SPEC=false; DO_XL=true;  DO_CHANGES=false ;;
    --changes)      DO_SPEC=false; DO_XL=false; DO_CHANGES=true  ;;
    --help|-h)
      echo "Usage: $0 [--spec] [--crosslinking] [--changes]"
      echo ""
      echo "Regenerates AsciiDoc partials consumed by the Antora documentation site."
      echo "Run from the repository root after editing the specification documents."
      echo ""
      echo "Options:"
      echo "  --spec          Regenerate only the main specification partial"
      echo "  --crosslinking  Regenerate only the crosslinking extension partial"
      echo "  --changes       Regenerate only the ${CHANGES_OLD_LABEL} -> ${CHANGES_NEW_LABEL} changes documents"
      echo ""
      echo "Output files:"
      echo "  ${SPEC_PARTIAL}"
      echo "  ${MODEL_PARTIAL}"
      echo "  ${XL_PARTIAL}"
      echo "  ${SPEC_CHANGES_OUT}"
      echo "  ${SPEC_CHANGES_PARTIAL}"
      echo "  ${CHANGES_OUT}"
      echo "  ${CHANGES_PARTIAL}"
      echo "  ${XSD_CHANGES_OUT}"
      echo "  ${XSD_CHANGES_PARTIAL}"
      echo "  ${XL_CHANGES_OUT}"
      echo "  ${XL_CHANGES_PARTIAL}"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

mkdir -p "${PARTIALS_DIR}"
CHANGED=()

# Strip the AsciiDoc document header (= title, :attribute: lines, ifdef blocks,
# etc.) so the file is safe for Antora include:: directives.  The document body
# starts at the [preface] block (either the block-style [preface] attribute or
# the [[preface]] anchor, whichever appears first).
strip_header() {
  awk '/^\[preface\]/{f=1} /^\[\[preface\]\]/{f=1} f{print}' "$1" > "$2"
}

# --- Main specification partial ----------------------------------------------
if [ "${DO_SPEC}" = true ]; then
  echo "==> Generating main specification partial..."
  echo "    Input:  ${SPEC_SRC}"
  echo "    Output: ${SPEC_PARTIAL}"
  strip_header "${SPEC_SRC}" "${SPEC_PARTIAL}"

  # mzidentml.adoc does include::model-in-xml-schema.adoc[].  Co-locate that file
  # (already headless: starts with "== Model in XML Schema") next to the spec
  # partial so Antora resolves the relative include within the partials family.
  echo "    Copying model-in-xml-schema.adoc alongside the partial..."
  cp "${MODEL_SRC}" "${MODEL_PARTIAL}"

  echo "    Done."
  CHANGED+=("${SPEC_PARTIAL}" "${MODEL_PARTIAL}")
fi

# --- Crosslinking extension partial ------------------------------------------
if [ "${DO_XL}" = true ]; then
  echo "==> Generating crosslinking extension partial..."
  echo "    Input:  ${XL_SRC}"
  echo "    Output: ${XL_PARTIAL}"
  strip_header "${XL_SRC}" "${XL_PARTIAL}"

  echo "    Done."
  CHANGED+=("${XL_PARTIAL}")
fi

# --- Changes documents --------------------------------------------------------
# Strip a standalone document header (the '= Title' line and any ':attribute:'
# lines) so the report can be pulled in with include::partial$...[].  Unlike
# strip_header() above this keeps the introduction and legend, which sit between
# the header and the first '==' section.
strip_doc_header() {
  awk 'BEGIN{h=1}
       h && (/^= /||/^:[A-Za-z][A-Za-z0-9_-]*:/||/^[[:space:]]*$/){next}
       {h=0; print}' "$1" > "$2"
}

# Run one comparison: <label> <mode> <old> <new> <out> <partial> <old-label> <new-label>
run_comparison() {
  local label="$1" mode="$2" old="$3" new="$4" out="$5" partial="$6" ol="$7" nl="$8" dl="$9"

  echo "==> Generating ${label} (${ol} -> ${nl}, ${mode}-level)..."
  echo "    Baseline: ${old}"
  echo "    Current:  ${new}"
  echo "    Output:   ${out}"

  if [ ! -f "${old}" ]; then
    echo "ERROR: baseline document not found: ${old}" >&2
    echo "       It is a frozen copy of the released text; restore it from git." >&2
    exit 1
  fi
  if [ ! -f "${new}" ]; then
    echo "ERROR: current document not found: ${new}" >&2
    exit 1
  fi

  python3 "${CHANGES_PY}" \
    --old "${old}" \
    --new "${new}" \
    --out "${out}" \
    --mode "${mode}" \
    --old-label "${ol}" \
    --new-label "${nl}" \
    --doc-label "${dl}"

  strip_doc_header "${out}" "${partial}"
  echo "    Antora partial: ${partial}"
  echo "    Done."
  CHANGED+=("${out}" "${partial}")
}

if [ "${DO_CHANGES}" = true ]; then
  if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is required but not found on PATH." >&2
    exit 1
  fi
  if [ ! -f "${CHANGES_PY}" ]; then
    echo "ERROR: comparison script not found: ${CHANGES_PY}" >&2
    exit 1
  fi

  # Main specification narrative: prose, so compared section by section.
  run_comparison "specification changes document" section \
    "${SPEC_CHANGES_OLD}" "${SPEC_CHANGES_NEW}" "${SPEC_CHANGES_OUT}" "${SPEC_CHANGES_PARTIAL}" \
    "${CHANGES_OLD_LABEL}" "${CHANGES_NEW_LABEL}" "Specification"

  # Model documentation: structured elements, so compared element by element.
  run_comparison "model changes document" element \
    "${CHANGES_OLD}" "${CHANGES_NEW}" "${CHANGES_OUT}" "${CHANGES_PARTIAL}" \
    "${CHANGES_OLD_LABEL}" "${CHANGES_NEW_LABEL}" "Model in XML Schema"

  # XML Schema: compared component by component (elements, types, groups).
  run_comparison "schema changes document" xsd \
    "${XSD_CHANGES_OLD}" "${XSD_CHANGES_NEW}" "${XSD_CHANGES_OUT}" "${XSD_CHANGES_PARTIAL}" \
    "${CHANGES_OLD_LABEL}" "${CHANGES_NEW_LABEL}" "XML Schema"

  # Crosslinking extension: prose document with no element structure, so it is
  # compared section by section instead.
  run_comparison "crosslinking changes document" section \
    "${XL_CHANGES_OLD}" "${XL_CHANGES_NEW}" "${XL_CHANGES_OUT}" "${XL_CHANGES_PARTIAL}" \
    "${XL_CHANGES_OLD_LABEL}" "${XL_CHANGES_NEW_LABEL}" "Crosslinking extension"
fi

echo ""
echo "==> Complete. Stage and commit the updated files:"
for f in "${CHANGED[@]}"; do
  echo "    git add ${f}"
done
echo "    git commit -m 'docs: regenerate Antora partials'"
