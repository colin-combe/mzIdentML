#!/bin/bash
#
# Validates the example files: first against the XML schema with xmllint, then semantically
# against the CV mapping and object rules of the version each file declares, using the
# command line jar of the latest mzidentml-validator release from
# https://github.com/HUPO-PSI/mzidentml-validator (downloaded once and cached).
#
# Usage: scripts/validate.sh [options] [path ...]
#
#   path            file or directory to validate; defaults to ./examples
#   --report-only   report semantic messages without failing the run (they fail it by default)
#   --schema-only   skip the semantic validation
#   -h, --help      show this help
#
# Environment:
#   MZID_VALIDATOR_JAR        a local mzidentml-validator *-cmd.jar to use instead of a release
#   MZID_VALIDATOR_VERSION    release tag to download (default latest)
#   MZID_VALIDATOR_CACHE      where downloaded jars are kept (default ./.cache/mzidentml-validator)
#   MZID_SEMANTIC_STRICT      set to 0 for the same as --report-only
#   MZID_SEMANTIC_LEVEL       lowest message level to report (default ERROR)
#   MZID_SEMANTIC_TIMEOUT     seconds a single file may take (default 1800)
#   MZID_VALIDATOR_JAVA_OPTS  options passed to java (default -Xmx4g); the JDK's XML
#                             entity size limits are always lifted as well
#   GITHUB_TOKEN              optional, used for the GitHub API call to avoid rate limits
#
# Exit codes: 0 ok, 2 setup error, 3 schema validation failed, 4 semantic validation failed.
#
set -uo pipefail

# Always work relative to the repository root, whatever the caller's cwd is, but keep the
# caller's cwd so that a path given on the command line can be resolved against it too.
ORIG_PWD="$PWD"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
cd "$(dirname "${SELF}")/.." || exit 1

V_DIR="./examples"
SCHEMA_DIR="./schema"
V_FAILED=()
V_COUNT=0

SEM_COUNT=0
SEM_FAILED=()
SEM_ERRORED=()

SEMANTIC_REQUESTED=1
SEMANTIC_ENABLED=0
SEMANTIC_STRICT="${MZID_SEMANTIC_STRICT:-1}"
SEMANTIC_LEVEL="${MZID_SEMANTIC_LEVEL:-ERROR}"
SEMANTIC_TIMEOUT="${MZID_SEMANTIC_TIMEOUT:-1800}"
JAVA_OPTS="${MZID_VALIDATOR_JAVA_OPTS:--Xmx4g}"
# Newer JDKs (24 and later) cap the size of XML entities by default, and the validator stops
# at that cap on large files with many entity references (e.g. &quot;), with
# "JAXP00010003: The length of entity ... exceeds the 100,000 limit". 0 means no limit,
# which is the default of older JDKs. They go before JAVA_OPTS, which can still override them.
XML_LIMIT_OPTS="-Djdk.xml.maxGeneralEntitySizeLimit=0 -Djdk.xml.totalEntitySizeLimit=0"
VALIDATOR_JAR=""
VALIDATOR_REPO="HUPO-PSI/mzidentml-validator"
VALIDATOR_VERSION="${MZID_VALIDATOR_VERSION:-latest}"
VALIDATOR_CACHE="${MZID_VALIDATOR_CACHE:-./.cache/mzidentml-validator}"

# The versions the mzidentml-validator has rule files for; anything else gets schema checks only.
SEMANTIC_VERSIONS=" 1.1.0 1.1.1 1.2.0 1.3.0 "

usage() {
  sed -n '3,26p' "${SELF}" | sed 's/^#\{1,2\} \{0,1\}//'
}

# Prefix each line of stdin so error output stays inside the "#" banner style.
indent() {
  while IFS= read -r line; do
    [ -n "$line" ] && echo "#   $line"
  done
}

# Downloads the *-cmd.jar of the requested validator release into the cache (unless it is
# there already) and prints its path. Progress and problems go to stderr.
fetch_release_jar() {
  local api json tag url dest
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")

  if ! command -v curl >/dev/null 2>&1; then
    echo "# curl not found, cannot download the validator" >&2
    return 1
  fi

  if [ "$VALIDATOR_VERSION" = "latest" ]; then
    api="https://api.github.com/repos/$VALIDATOR_REPO/releases/latest"
  else
    api="https://api.github.com/repos/$VALIDATOR_REPO/releases/tags/$VALIDATOR_VERSION"
  fi

  if ! json=$(curl -fsSL ${auth[@]+"${auth[@]}"} -H "Accept: application/vnd.github+json" "$api" 2>&1); then
    echo "# could not query $api: $json" >&2
    return 1
  fi

  tag=$(sed -n 's/^ *"tag_name": *"\([^"]*\)".*/\1/p' <<<"$json" | head -1)
  url=$(grep -o '"browser_download_url": *"[^"]*-cmd\.jar"' <<<"$json" | sed 's/.*: *"\(.*\)"/\1/' | head -1)
  if [ -z "$tag" ] || [ -z "$url" ]; then
    echo "# release $VALIDATOR_VERSION of $VALIDATOR_REPO has no *-cmd.jar asset" >&2
    return 1
  fi

  mkdir -p "$VALIDATOR_CACHE" || return 1
  dest="$VALIDATOR_CACHE/$(basename "$url")"
  if [ ! -s "$dest" ]; then
    echo "# Downloading mzidentml-validator $tag from $url" >&2
    if ! curl -fsSL -o "$dest.part" "$url" || ! unzip -tq "$dest.part" >/dev/null 2>&1; then
      echo "# download of $url failed" >&2
      rm -f "$dest.part"
      return 1
    fi
    mv "$dest.part" "$dest"
  fi
  echo "$dest"
}

# The jar to validate with: MZID_VALIDATOR_JAR if given, else the requested release, else -
# when the download is not possible (e.g. offline) - the newest jar already in the cache.
find_validator_jar() {
  if [ -n "${MZID_VALIDATOR_JAR:-}" ]; then
    if [ -f "$MZID_VALIDATOR_JAR" ]; then
      echo "$MZID_VALIDATOR_JAR"
    else
      echo "# MZID_VALIDATOR_JAR=$MZID_VALIDATOR_JAR does not exist" >&2
    fi
    return
  fi

  local jar
  if jar=$(fetch_release_jar); then
    echo "$jar"
    return
  fi

  jar=$(ls -t "$VALIDATOR_CACHE"/*-cmd.jar 2>/dev/null | head -1)
  if [ -n "$jar" ]; then
    echo "# WARNING: falling back to the cached $jar, which may not be the latest release" >&2
    echo "$jar"
  fi
}

TARGETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --report-only)
      SEMANTIC_STRICT=0
      ;;
    --strict)
      # The old opt-in flag; strict is the default now.
      SEMANTIC_STRICT=1
      ;;
    --schema-only)
      SEMANTIC_REQUESTED=0
      ;;
    -*)
      echo "# ERROR: unknown option $1"
      usage
      exit 2
      ;;
    *)
      # A relative path is taken from where the caller stands, if it exists there.
      if [[ "$1" != /* ]] && [ -e "$ORIG_PWD/$1" ] && [ ! -e "$1" ]; then
        TARGETS+=("$ORIG_PWD/$1")
      else
        TARGETS+=("$1")
      fi
      ;;
  esac
  shift
done

if ! command -v xmllint >/dev/null 2>&1; then
  echo "# ERROR: xmllint not found (install libxml2-utils)"
  exit 2
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
  if [ ! -d "$V_DIR" ]; then
    echo "# ERROR: example directory $V_DIR not found"
    exit 2
  fi
  TARGETS=("$V_DIR")
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Collect example files: plain .mzid plus the gzipped ones.
V_FILES=()
for target in "${TARGETS[@]}"; do
  if [ -d "$target" ]; then
    mapfile -d '' -t FOUND < <(find "$target" \( -iname '*.mzid' -o -iname '*.mzid.gz' \) -print0 | sort -z)
    [ ${#FOUND[@]} -gt 0 ] && V_FILES+=("${FOUND[@]}")
  elif [ -f "$target" ]; then
    V_FILES+=("$target")
  else
    echo "# ERROR: no such file or directory: $target"
    exit 2
  fi
done

if [ ${#V_FILES[@]} -eq 0 ]; then
  echo "# ERROR: no example files found under ${TARGETS[*]}"
  exit 2
fi

# In strict mode (the default) not being able to run the semantic validation is an error,
# so that CI cannot pass by silently skipping it. With --report-only it is just skipped.
semantic_unavailable() {
  echo "################################################################################"
  if [ "$SEMANTIC_STRICT" = "1" ]; then
    echo "# ERROR: cannot run the semantic validation: $1"
    echo "#   install it, or use --schema-only / --report-only to do without"
    echo "################################################################################"
    exit 2
  fi
  echo "# Skipping semantic validation: $1"
  echo "################################################################################"
}

if [ "$SEMANTIC_REQUESTED" -eq 1 ]; then
  if ! command -v java >/dev/null 2>&1; then
    semantic_unavailable "java (11 or later) not found"
  elif ! VALIDATOR_JAR=$(find_validator_jar) || [ -z "$VALIDATOR_JAR" ]; then
    semantic_unavailable "no mzidentml-validator *-cmd.jar (set MZID_VALIDATOR_JAR to use a local one)"
  else
    SEMANTIC_ENABLED=1
    echo "################################################################################"
    echo "# Semantic validation using $VALIDATOR_JAR"
    echo "# Reporting messages of level $SEMANTIC_LEVEL and above"
    echo "################################################################################"
  fi
fi

# Runs the semantic validation of a single file and reports what came back.
# $1: the file as named on the command line, $2: the (decompressed) XML to validate,
# $3: the mzIdentML version it declares.
semantic_validation() {
  local name="$1" xml="$2" version="$3"

  if [[ "$SEMANTIC_VERSIONS" != *" $version "* ]]; then
    echo "# No semantic rules for mzIdentML $version - skipping semantic validation"
    return
  fi

  echo "# Starting semantic validation of $name"

  # The validator loads the rules for the version the file declares, so it needs no more
  # than the file itself. It exits 0 when nothing was reported, 1 when it has messages
  # and 2 when it could not validate at all.
  timeout "$SEMANTIC_TIMEOUT" java $XML_LIMIT_OPTS $JAVA_OPTS -jar "$VALIDATOR_JAR" \
    -e -f "$xml" -l "$SEMANTIC_LEVEL" >"$TMP_DIR/sem.out" 2>"$TMP_DIR/sem.err"
  local result=$?
  SEM_COUNT=$((SEM_COUNT + 1))

  case $result in
    0)
      echo "# Semantic validation successful"
      ;;
    1)
      echo "# SEMANTIC VALIDATION MESSAGES"
      # A single message can span several lines, so print the whole block between the
      # summary line and the statistics that follow it.
      sed -n '/^The following .* messages were obtained/,/^Invalid XML schema validation:/p' "$TMP_DIR/sem.out" \
        | sed '$d' | indent
      SEM_FAILED+=("$name")
      ;;
    *)
      if [ $result -eq 124 ]; then
        echo "# SEMANTIC VALIDATION COULD NOT BE RUN (timed out after ${SEMANTIC_TIMEOUT}s)"
      else
        echo "# SEMANTIC VALIDATION COULD NOT BE RUN (validator exited with $result)"
      fi
      tail -n 10 "$TMP_DIR/sem.err" | indent
      SEM_ERRORED+=("$name")
      ;;
  esac
}

for i in "${V_FILES[@]}"; do
  echo -e "################################################################################"
  echo -e "# Starting basic validation of $i"

  # xmllint cannot read gzip, so decompress to a scratch copy first.
  if [[ "$i" == *.gz ]]; then
    XML="$TMP_DIR/$(basename "${i%.gz}")"
    if ! gzip -cd "$i" > "$XML" 2>"$TMP_DIR/err"; then
      echo -e "# VALIDATION FAILED"
      echo -e "# Errors:"
      indent < "$TMP_DIR/err"
      V_FAILED+=("$i")
      rm -f "$XML"
      echo -e "################################################################################"
      continue
    fi
  else
    XML="$i"
  fi

  # Read the version attribute off the root element (not just any version="" in the file).
  # This parse also surfaces any well-formedness errors.
  VERSION=$(xmllint --xpath 'string(/*/@version)' "$XML" 2>"$TMP_DIR/err")

  if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "# VALIDATION FAILED"
    echo -e "# Errors:"
    if [ -s "$TMP_DIR/err" ]; then
      indent < "$TMP_DIR/err"
    else
      echo "#   root element has no usable version attribute (got '$VERSION')"
    fi
    V_FAILED+=("$i")
    [ "$XML" = "$i" ] || rm -f "$XML"
    echo -e "################################################################################"
    continue
  fi

  SCHEMA="$SCHEMA_DIR/mzIdentML${VERSION}.xsd"

  if [ ! -f "$SCHEMA" ]; then
    echo -e "# VALIDATION FAILED"
    echo "#   no schema for version $VERSION (expected $SCHEMA)"
    V_FAILED+=("$i")
    [ "$XML" = "$i" ] || rm -f "$XML"
    echo -e "################################################################################"
    continue
  fi

  echo "# Using schema: $SCHEMA"
  ERRORS=$(xmllint --noout --schema "$SCHEMA" "$XML" 2>&1)
  RESULT=$?
  V_COUNT=$((V_COUNT + 1))

  if [ $RESULT -ne 0 ]; then
    echo -e "# VALIDATION FAILED"
    echo -e "# Errors:"
    echo "$ERRORS" | indent
    V_FAILED+=("$i")
  else
    echo -e "# Validation successful"
    if [ "$SEMANTIC_ENABLED" -eq 1 ]; then
      semantic_validation "$i" "$XML" "$VERSION"
    fi
  fi

  [ "$XML" = "$i" ] || rm -f "$XML"
  echo -e "################################################################################"
done

EXIT_CODE=0

if [ ${#V_FAILED[@]} -ne 0 ]; then
  echo -e "################################################################################"
  echo -e "# Validation failed for ${#V_FAILED[@]} of ${#V_FILES[@]} files! Please check the following files:"
  for i in "${V_FAILED[@]}"
  do
   echo "# $i"
  done
  echo -e "################################################################################"
  EXIT_CODE=3
else
  echo -e "################################################################################"
  echo -e "# Validation of all ${V_COUNT} files successful!"
  echo -e "################################################################################"
fi

if [ "$SEMANTIC_ENABLED" -eq 1 ]; then
  echo -e "################################################################################"
  echo "# Semantic validation: ${SEM_COUNT} files checked, ${#SEM_FAILED[@]} with messages, ${#SEM_ERRORED[@]} could not be run"
  for i in ${SEM_FAILED[@]+"${SEM_FAILED[@]}"}
  do
   echo "# messages: $i"
  done
  for i in ${SEM_ERRORED[@]+"${SEM_ERRORED[@]}"}
  do
   echo "# could not be run: $i"
  done
  if [ $(( ${#SEM_FAILED[@]} + ${#SEM_ERRORED[@]} )) -ne 0 ]; then
    if [ "$SEMANTIC_STRICT" = "1" ]; then
      [ "$EXIT_CODE" -eq 0 ] && EXIT_CODE=4
    else
      echo "# (report-only - drop --report-only to let these fail the run)"
    fi
  fi
  echo -e "################################################################################"
fi

exit $EXIT_CODE
