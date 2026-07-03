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
# Usage:
#   ./gen-docs.sh              # regenerate spec + crosslinking partials
#   ./gen-docs.sh --spec       # regenerate the main specification partial only
#   ./gen-docs.sh --crosslinking   # regenerate the crosslinking extension partial only
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

DO_SPEC=true
DO_XL=true

for arg in "$@"; do
  case "$arg" in
    --spec)         DO_SPEC=true;  DO_XL=false ;;
    --crosslinking) DO_SPEC=false; DO_XL=true  ;;
    --help|-h)
      echo "Usage: $0 [--spec] [--crosslinking]"
      echo ""
      echo "Regenerates AsciiDoc partials consumed by the Antora documentation site."
      echo "Run from the repository root after editing the specification documents."
      echo ""
      echo "Options:"
      echo "  --spec          Regenerate only the main specification partial"
      echo "  --crosslinking  Regenerate only the crosslinking extension partial"
      echo ""
      echo "Output files:"
      echo "  ${SPEC_PARTIAL}"
      echo "  ${MODEL_PARTIAL}"
      echo "  ${XL_PARTIAL}"
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

echo ""
echo "==> Complete. Stage and commit the updated files:"
for f in "${CHANGED[@]}"; do
  echo "    git add ${f}"
done
echo "    git commit -m 'docs: regenerate Antora partials'"
