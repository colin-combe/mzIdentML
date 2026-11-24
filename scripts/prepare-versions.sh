#!/bin/bash
# Prepare every v* branch for the Antora build (antora-playbook.yml publishes
# the v* branches, reading each from its worktree: 'worktrees: true').
#
# For each local v* branch this:
#   1. uses the current checkout if it is that branch, otherwise adds a linked
#      worktree for it under build/worktrees/<branch>;
#   2. builds that branch's specification PDF/DOCX with its own
#      build-spec-docs.sh and puts them in its Antora attachments folder (they
#      are never committed);
#   3. writes the branch's last commit hash and date into its antora.yml, so the
#      pages and the PDF/DOCX of each version name the commit they come from.
#
# Used by CI. It edits antora.yml in each worktree, so run it locally only in a
# throwaway clone; for a local preview use scripts/build-site.sh instead.
#
# Usage: scripts/prepare-versions.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

CURRENT="$(git rev-parse --abbrev-ref HEAD)"
mapfile -t BRANCHES < <(git for-each-ref --format='%(refname:short)' 'refs/heads/v*')
if [ "${#BRANCHES[@]}" -eq 0 ]; then
  echo "ERROR: no local v* branches, so there is nothing to publish." >&2
  exit 1
fi

for branch in "${BRANCHES[@]}"; do
  echo "==> ${branch}"
  if [ "${branch}" = "${CURRENT}" ]; then
    wt="${ROOT}"
  else
    wt="${ROOT}/build/worktrees/${branch}"
    [ -d "${wt}" ] || git worktree add --quiet "${wt}" "${branch}"
  fi

  # Full ref, in case a tag has the same name as the branch.
  sha="$(git rev-parse --short "refs/heads/${branch}")"
  date="$(TZ=UTC git log -1 --format=%cd --date=format-local:'%Y-%m-%d %H:%M:%S UTC' "refs/heads/${branch}")"
  component="${wt}/docs/mzidentml"
  attachments="${component}/modules/ROOT/attachments"
  mkdir -p "${attachments}"

  # Named after spec-basename / xl-basename in the branch's antora.yml.
  "${wt}/scripts/build-spec-docs.sh" -o "${attachments}" -c "${sha}" -d "${date}"

  sed -i -E \
    -e "s|^( *commit-hash:).*|\1 '${sha}'|" \
    -e "s|^( *build-date:).*|\1 '${date}'|" \
    "${component}/antora.yml"
done
