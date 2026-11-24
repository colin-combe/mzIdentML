#!/bin/bash
# Build and optionally preview the mzIdentML Antora documentation site using Docker.
#
# The preview shows the current branch only, whatever its name, including
# uncommitted changes. (The published site is built by CI from every v* branch;
# see antora-playbook.yml and prepare-versions.sh.)
#
# Usage:
#   ./build-site.sh          # build only
#   ./build-site.sh --serve  # build and start a local HTTP server for preview
#   ./build-site.sh --clean  # remove node_modules before building (force reinstall)
#   ./build-site.sh --with-spec  # rebuild the spec PDF/DOCX even if present
#
# The spec PDF/DOCX (Antora attachments, i.e. the per-version downloads) are
# built automatically when missing; --with-spec forces a rebuild after the spec
# sources change.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/build/site"
ANTORA_IMAGE="antora/antora:3.1.14"
SERVE=false
WITH_SPEC=false
SPEC_NAMES=(mzidentml crosslinking_ext)
ATTACHMENTS_DIR="${SCRIPT_DIR}/docs/mzidentml/modules/ROOT/attachments"
CLEANUP=()
trap 'rm -rf ${CLEANUP[@]+"${CLEANUP[@]}"}' EXIT

for arg in "$@"; do
  case "$arg" in
    --serve) SERVE=true ;;
    --clean) rm -rf "${SCRIPT_DIR}/node_modules" ;;
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

# Install Antora + extensions via npm inside the Antora Docker image.
# The antora/antora image ships with Node.js and npm; we override the entrypoint
# to run npm so both steps use the same Node version.
if [ ! -d "${SCRIPT_DIR}/node_modules" ]; then
  echo "==> Installing Antora dependencies (first run)..."
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -v "${SCRIPT_DIR}:/antora" \
    -w /antora \
    --entrypoint npm \
    "${ANTORA_IMAGE}" \
    install --cache /antora/.npm-cache
  echo "    Done. Commit package-lock.json to enable reproducible builds (npm ci)."
else
  echo "==> node_modules present, skipping npm install (use --clean to force reinstall)."
fi

# Build the spec PDF/DOCX when any is missing, so the download links resolve.
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
  "${SCRIPT_DIR}/build-spec-docs.sh" -o "${ATTACHMENTS_DIR}" \
    -c "$(git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || echo local)" \
    -d "$(date -u +'%Y-%m-%d %H:%M:%S UTC')" "${SPEC_NAMES[@]}"
  echo "    Copied PDF/DOCX to ${ATTACHMENTS_DIR}"
fi

# Same playbook, but reading only the current branch (HEAD) from this checkout. It sits next to
# antora-playbook.yml because Antora resolves the playbook's paths relative to it.
PREVIEW_PLAYBOOK="${SCRIPT_DIR}/.antora-preview-playbook.yml"
CLEANUP+=("${PREVIEW_PLAYBOOK}")
sed -e "s/^\( *branches:\).*/\1 HEAD/" -e "s/^\( *worktrees:\).*/\1 ./" \
  "${SCRIPT_DIR}/antora-playbook.yml" > "${PREVIEW_PLAYBOOK}"

echo "==> Building Antora site..."
docker run --rm \
  -u "$(id -u):$(id -g)" \
  -v "${SCRIPT_DIR}:/antora" \
  -w /antora \
  "${ANTORA_IMAGE}" \
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
  echo "  ./build-site.sh --serve"
  echo "  python3 -m http.server 8080 --directory '${OUTPUT_DIR}'"
fi
