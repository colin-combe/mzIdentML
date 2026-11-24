#!/bin/bash
# Build and optionally preview the mzIdentML Antora documentation site using Docker.
#
# The preview shows the current branch only, whatever its name, including
# uncommitted changes. (The published site is built by CI from every v* branch;
# see antora-playbook.yml and prepare-versions.sh.)
#
# Usage:
#   scripts/build-site.sh          # build only
#   scripts/build-site.sh --serve  # build and start a local HTTP server for preview
#   scripts/build-site.sh --clean  # remove node_modules before building (force reinstall)
#   scripts/build-site.sh --with-spec  # rebuild the spec PDF/DOCX even if present
#
# The spec PDF/DOCX (Antora attachments, i.e. the per-version downloads) are
# built automatically when missing; --with-spec forces a rebuild after the spec
# sources change.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${ROOT}/build/site"
# Node.js image used to install and run Antora from package-lock.json, so the
# preview uses the same Antora and extension versions as CI (npm ci on Node LTS).
NODE_IMAGE="node:lts-alpine"
SERVE=false
WITH_SPEC=false
ATTACHMENTS_DIR="${ROOT}/docs/mzidentml/modules/ROOT/attachments"
CLEANUP=()
trap 'rm -rf ${CLEANUP[@]+"${CLEANUP[@]}"}' EXIT

for arg in "$@"; do
  case "$arg" in
    --serve) SERVE=true ;;
    --clean) rm -rf "${ROOT}/node_modules" ;;
    --with-spec) WITH_SPEC=true ;;
    --help|-h)
      echo "Usage: $0 [--serve] [--clean] [--with-spec]"
      echo "  --serve      Start a local HTTP server after building (requires Python 3)"
      echo "  --clean      Remove node_modules and reinstall before building"
      echo "  --with-spec  Rebuild the specification PDF/DOCX even if already present"
      echo "               (they are built automatically when missing)"
      exit 0
      ;;
  esac
done

echo "==> Checking for Docker..."
if ! command -v docker &>/dev/null; then
  echo "ERROR: Docker is not installed or not on PATH." >&2
  exit 1
fi

# Run a command in the Node.js image, in this checkout (mounted at /antora).
node_run() {
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -v "${ROOT}:/antora" \
    -w /antora \
    "${NODE_IMAGE}" \
    "$@"
}

# Install Antora + extensions exactly as locked in package-lock.json.
if [ ! -d "${ROOT}/node_modules" ]; then
  echo "==> Installing Antora dependencies (first run)..."
  node_run npm ci --cache /antora/.npm-cache
else
  echo "==> node_modules present, skipping npm install (use --clean to force reinstall)."
fi

# Build the spec PDF/DOCX when any is missing, so the download links resolve.
# Their names are spec-basename / xl-basename in antora.yml (e.g. mzidentml-1.3.0).
SPEC_NAMES=()
for key in spec-basename xl-basename; do
  SPEC_NAMES+=("$(sed -n "s/^ *${key}: *//p" "${ROOT}/docs/mzidentml/antora.yml" | tr -d "'\"")")
done
if [ "${WITH_SPEC}" = false ]; then
  for f in "${SPEC_NAMES[@]}"; do
    if [ ! -f "${ATTACHMENTS_DIR}/${f}.pdf" ] || [ ! -f "${ATTACHMENTS_DIR}/${f}.docx" ]; then
      echo "==> Spec PDF/DOCX not found in ${ATTACHMENTS_DIR}; building them."
      WITH_SPEC=true
      break
    fi
  done
fi

if [ "${WITH_SPEC}" = true ]; then
  echo "==> Building specification PDF/DOCX..."
  # Drop any left from earlier names, so the site only carries the current ones.
  rm -f "${ATTACHMENTS_DIR}"/*.pdf "${ATTACHMENTS_DIR}"/*.docx
  "${ROOT}/scripts/build-spec-docs.sh" -o "${ATTACHMENTS_DIR}" \
    -c "$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo local)" \
    -d "$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
  echo "    Copied PDF/DOCX to ${ATTACHMENTS_DIR}"
fi

# Same playbook, but reading only the current branch (HEAD) from this checkout. It sits next to
# antora-playbook.yml because Antora resolves the playbook's paths relative to it.
PREVIEW_PLAYBOOK="${ROOT}/.antora-preview-playbook.yml"
CLEANUP+=("${PREVIEW_PLAYBOOK}")
sed -e "s/^\( *branches:\).*/\1 HEAD/" -e "s/^\( *worktrees:\).*/\1 ./" \
  "${ROOT}/antora-playbook.yml" > "${PREVIEW_PLAYBOOK}"

echo "==> Building Antora site..."
node_run node node_modules/@antora/cli/bin/antora \
  --cache-dir /antora/.cache/antora \
  --clean \
  "$(basename "${PREVIEW_PLAYBOOK}")"

echo ""
echo "==> Site built at: ${OUTPUT_DIR}"

if [ "${SERVE}" = true ]; then
  echo ""
  echo "==> Starting local preview server at http://localhost:8080 ..."
  echo "    Press Ctrl+C to stop."
  python3 -m http.server 8080 --directory "${OUTPUT_DIR}"
else
  echo ""
  echo "To preview the site, run one of:"
  echo "  scripts/build-site.sh --serve"
  echo "  python3 -m http.server 8080 --directory '${OUTPUT_DIR}'"
fi
