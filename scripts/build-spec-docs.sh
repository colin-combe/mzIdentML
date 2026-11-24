#!/bin/bash
# Build the standalone specification documents (PDF and DOCX) of this checkout.
#
# The specification sources are Antora pages under
# docs/mzidentml/modules/developers/pages/ (specification.adoc, which includes
# _model-in-xml-schema.adoc, and crosslinking.adoc), each a complete AsciiDoc
# document. The PDF/DOCX are named after spec-basename and xl-basename in this
# checkout's docs/mzidentml/antora.yml (e.g. mzidentml-1.3.0), which also link
# them on the site. Their figures are the Antora images
# under docs/mzidentml/modules/developers/images/img/. Both are copied into a
# temporary folder, so that the documents find their figures at img/... as they
# do in Antora, and built there:
#   PDF   asciidoctor-pdf (Docker image ASCIIDOCTOR_IMAGE);
#   DOCX  asciidoctor to HTML (same image), then pandoc. HTML rather than
#         DocBook, because pandoc's DocBook reader ignores image sizes and
#         scales every image to the full text width, which wrecks tables with
#         small inline images; its HTML reader honours them. pandoc rasterises
#         SVG figures with rsvg-convert (librsvg2-bin) when it is installed.
#
# Used by prepare-versions.sh (CI, every v* branch with its own copy of this
# script) and build-site.sh (local preview). Needs Docker and pandoc.
#
# Usage: scripts/build-spec-docs.sh -o <output_dir> -c <commit_hash> -d <build_date>
# Writes <output_dir>/<spec-basename>.{pdf,docx} and <output_dir>/<xl-basename>.{pdf,docx}.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="${ROOT}/docs/mzidentml/modules/developers"
ANTORA_YML="${ROOT}/docs/mzidentml/antora.yml"
ASCIIDOCTOR_IMAGE="asciidoctor/docker-asciidoctor:1"
# Source page (without .adoc) and the antora.yml attribute naming its PDF/DOCX.
DOCS=("specification:spec-basename" "crosslinking:xl-basename")

usage() {
  echo "Usage: $0 -o <output_dir> -c <commit_hash> -d <build_date>" >&2
  exit 1
}

OUT="" SHA="" DATE=""
while getopts "o:c:d:h" opt; do
  case "$opt" in
    o) OUT="$OPTARG" ;;
    c) SHA="$OPTARG" ;;
    d) DATE="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ -n "${OUT}" ] && [ -n "${SHA}" ] && [ -n "${DATE}" ] && [ "$#" -eq 0 ] || usage
command -v docker > /dev/null || { echo "ERROR: docker not found on PATH" >&2; exit 1; }
command -v pandoc > /dev/null || { echo "ERROR: pandoc not found on PATH" >&2; exit 1; }

SRC="$(mktemp -d)"
trap 'rm -rf "${SRC}"' EXIT
# Copy all pages: specification.adoc includes _model-in-xml-schema.adoc.
cp "${MODULE}"/pages/*.adoc "${SRC}/"
cp -R "${MODULE}/images/img" "${SRC}/img"
mkdir -p "${SRC}/output" "${OUT}"

# Run an Asciidoctor command (asciidoctor or asciidoctor-pdf) with the common
# options, in ${SRC} (mounted at the image's /documents).
asciidoctor_run() {
  local cmd="$1"
  shift
  docker run --rm -u "$(id -u):$(id -g)" -v "${SRC}:/documents" -w /documents \
    "${ASCIIDOCTOR_IMAGE}" "${cmd}" \
    -d book -a "commit-hash=${SHA}" -a "build-date=${DATE}" "$@"
}

for doc in "${DOCS[@]}"; do
  page="${doc%%:*}"
  key="${doc#*:}"
  name="$(sed -n "s/^ *${key}: *//p" "${ANTORA_YML}" | tr -d "'\"")"
  if [ -z "${name}" ]; then
    echo "ERROR: ${key} is not set in ${ANTORA_YML}" >&2
    exit 1
  fi

  echo "==> ${name}.pdf (from ${page}.adoc)"
  asciidoctor_run asciidoctor-pdf -o "output/${name}.pdf" "${page}.adoc"

  echo "==> ${name}.docx (from ${page}.adoc)"
  # Written next to img/ so pandoc finds the figures. toc! and nofooter keep the
  # TOC and "Last updated" footer out of the document body; the shift makes the
  # HTML's <h1> title and <h2> sections into Word's title and Heading 1.
  asciidoctor_run asciidoctor -a toc! -a nofooter -o "${page}-forDocx.html" "${page}.adoc"
  (cd "${SRC}" && pandoc --from html --to docx --shift-heading-level-by=-1 \
    --output "output/${name}.docx" "${page}-forDocx.html")

  cp -v "${SRC}/output/${name}".{pdf,docx} "${OUT}/"
done
