#!/bin/bash
#
# Validates the example files: first against the XML schema with xmllint, then - if the
# mzidentml-validator command line jar can be found - semantically against the CV mapping
# and object rules of the version each file declares.
#
# Usage: ./validate.sh [options] [path ...]
#
#   path            file or directory to validate; defaults to ./examples
#   --strict        let semantic messages fail the run too (they are report-only by default)
#   --schema-only   skip the semantic validation
#   -h, --help      show this help
#
# Environment:
#   MZID_VALIDATOR_JAR        the mzidentml-validator *-cmd.jar to use; by default the newest
#                             one in ../mzidentml-validator/bin and ../mzidentml-validator/target
#   MZID_SEMANTIC_STRICT      same as --strict when set to 1
#   MZID_SEMANTIC_LEVEL       lowest message level to report (default ERROR)
#   MZID_SEMANTIC_TIMEOUT     seconds a single file may take (default 1800)
#   MZID_VALIDATOR_JAVA_OPTS  options passed to java (default -Xmx4g)
#
# Exit codes: 0 ok, 2 setup error, 3 schema validation failed, 4 semantic messages under --strict.
#
set -uo pipefail

# Always work relative to the repository root, whatever the caller's cwd is, but keep the
# caller's cwd so that a path given on the command line can be resolved against it too.
ORIG_PWD="$PWD"
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

V_DIR="./examples"
SCHEMA_DIR="./schema"
V_FAILED=()
V_COUNT=0

SEM_COUNT=0
SEM_FAILED=()
SEM_ERRORED=()

SEMANTIC_REQUESTED=1
SEMANTIC_ENABLED=0
SEMANTIC_STRICT="${MZID_SEMANTIC_STRICT:-0}"
SEMANTIC_LEVEL="${MZID_SEMANTIC_LEVEL:-ERROR}"
SEMANTIC_TIMEOUT="${MZID_SEMANTIC_TIMEOUT:-1800}"
JAVA_OPTS="${MZID_VALIDATOR_JAVA_OPTS:--Xmx4g}"
VALIDATOR_JAR=""

# The versions the mzidentml-validator has rule files for; anything else gets schema checks only.
SEMANTIC_VERSIONS=" 1.1.0 1.1.1 1.2.0 1.3.0 "

usage() {
  sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'
}

# Prefix each line of stdin so error output stays inside the "#" banner style.
indent() {
  while IFS= read -r line; do
    [ -n "$line" ] && echo "#   $line"
  done
}

# Newest *-cmd.jar of the sibling validator checkout, or nothing if there is none.
find_validator_jar() {
  if [ -n "${MZID_VALIDATOR_JAR:-}" ]; then
    if [ -f "$MZID_VALIDATOR_JAR" ]; then
      echo "$MZID_VALIDATOR_JAR"
    fi
    return
  fi

  local jar
  jar=$(ls -t ../mzidentml-validator/bin/*-cmd.jar ../mzidentml-validator/target/*-cmd.jar 2>/dev/null | head -1)
  [ -n "$jar" ] && echo "$jar"
}

TARGETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --strict)
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

# Semantic validation is a bonus: without java or a validator jar (as on CI) the schema
# validation still runs and still decides the exit code.
if [ "$SEMANTIC_REQUESTED" -eq 1 ]; then
  VALIDATOR_JAR=$(find_validator_jar)
  if ! command -v java >/dev/null 2>&1; then
    echo "################################################################################"
    echo "# Skipping semantic validation: java not found"
    echo "################################################################################"
  elif [ -z "$VALIDATOR_JAR" ]; then
    echo "################################################################################"
    echo "# Skipping semantic validation: no mzidentml-validator *-cmd.jar found"
    echo "#   looked in ../mzidentml-validator/{bin,target}; set MZID_VALIDATOR_JAR to point at one"
    echo "################################################################################"
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
  timeout "$SEMANTIC_TIMEOUT" java $JAVA_OPTS -jar "$VALIDATOR_JAR" \
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
      echo "# (report-only - re-run with --strict to let these fail the build)"
    fi
  fi
  echo -e "################################################################################"
fi

exit $EXIT_CODE
