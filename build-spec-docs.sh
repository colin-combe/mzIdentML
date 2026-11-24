#!/bin/bash
# Build the standalone specification documents (PDF and DOCX) of this checkout.
#
# The specification sources are the Antora partials under
# docs/mzidentml/modules/developers/partials/ (each a complete AsciiDoc document;
# the site includes only their tagged body). Their figures are the Antora images
# under docs/mzidentml/modules/developers/images/img/. This script assembles both
# in a temporary folder, in the layout build-docs.sh expects, and runs it.
#
# Used by prepare-versions.sh (CI, every v* branch with its own copy of this
# script) and build-site.sh (local preview).
#
# Usage: ./build-spec-docs.sh -o <output_dir> -c <commit_hash> -d <build_date> <name>...
#   <name>  document base name, e.g. mzidentml or crosslinking_ext
# Writes <output_dir>/<name>.pdf and <output_dir>/<name>.docx for each name.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="${ROOT}/docs/mzidentml/modules/developers"

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

SRC="$(mktemp -d)"
trap 'rm -rf "${SRC}"' EXIT
# Copy all partials: mzidentml.adoc includes model-in-xml-schema.adoc.
cp "${MODULE}"/partials/*.adoc "${SRC}/"
cp -R "${MODULE}/images/img" "${SRC}/img"

mkdir -p "${OUT}"
for name in "$@"; do
  if [ ! -f "${SRC}/${name}.adoc" ]; then
    echo "ERROR: ${MODULE}/partials/${name}.adoc not found" >&2
    exit 1
  fi
  "${ROOT}/build-docs.sh" -i "${SRC}" -o "${SRC}/output" -c "${SHA}" -d "${DATE}" -f "${name}.adoc" -r
  cp -v "${SRC}/output/${name}".{pdf,docx} "${OUT}/"
done
