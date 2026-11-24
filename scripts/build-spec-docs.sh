#!/bin/bash
# Build the standalone specification documents (PDF and DOCX) of this checkout.
#
# The specification sources are the Antora partials under
# docs/mzidentml/modules/developers/partials/ (each a complete AsciiDoc document;
# the site includes only their tagged body). Their figures are the Antora images
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
# Usage: scripts/build-spec-docs.sh -o <output_dir> -c <commit_hash> -d <build_date> <name>...
#   <name>  document base name, e.g. mzidentml or crosslinking_ext
# Writes <output_dir>/<name>.pdf and <output_dir>/<name>.docx for each name.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="${ROOT}/docs/mzidentml/modules/developers"
ASCIIDOCTOR_IMAGE="asciidoctor/docker-asciidoctor:1"

usage() {
  echo "Usage: $0 -o <output_dir> -c <commit_hash> -d <build_date> <name>..." >&2
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
[ -n "${OUT}" ] && [ -n "${SHA}" ] && [ -n "${DATE}" ] && [ "$#" -gt 0 ] || usage
command -v docker > /dev/null || { echo "ERROR: docker not found on PATH" >&2; exit 1; }
command -v pandoc > /dev/null || { echo "ERROR: pandoc not found on PATH" >&2; exit 1; }

SRC="$(mktemp -d)"
trap 'rm -rf "${SRC}"' EXIT
# Copy all partials: mzidentml.adoc includes model-in-xml-schema.adoc.
cp "${MODULE}"/partials/*.adoc "${SRC}/"
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

for name in "$@"; do
  if [ ! -f "${SRC}/${name}.adoc" ]; then
    echo "ERROR: ${MODULE}/partials/${name}.adoc not found" >&2
    exit 1
  fi

  echo "==> ${name}.pdf"
  asciidoctor_run asciidoctor-pdf -D output "${name}.adoc"

  echo "==> ${name}.docx"
  # Written next to img/ so pandoc finds the figures. toc! and nofooter keep the
  # TOC and "Last updated" footer out of the document body; the shift makes the
  # HTML's <h1> title and <h2> sections into Word's title and Heading 1.
  asciidoctor_run asciidoctor -a toc! -a nofooter -o "${name}-forDocx.html" "${name}.adoc"
  (cd "${SRC}" && pandoc --from html --to docx --shift-heading-level-by=-1 \
    --output "output/${name}.docx" "${name}-forDocx.html")

  cp -v "${SRC}/output/${name}".{pdf,docx} "${OUT}/"
done
