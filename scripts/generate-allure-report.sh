#!/usr/bin/env bash
set -Eeuo pipefail

# Converts raw Allure results into an HTML report.
# Keeps reporting separate from test execution.

RESULTS_DIR="${ALLURE_RESULTS_DIR:-target/allure-results}"
REPORT_DIR="${ALLURE_REPORT_DIR:-target/allure-report}"
ALLURE_VERSION="${ALLURE_VERSION:-2.29.0}"

ALLURE_BIN="${HOME}/.local/bin/allure"

echo "===== Generating Allure HTML report ====="
echo "Results: ${RESULTS_DIR}"
echo "Report : ${REPORT_DIR}"

# Fall back to an Allure installation on PATH.
if [ ! -x "$ALLURE_BIN" ]; then
  ALLURE_BIN="$(command -v allure || true)"
fi

if [ -z "$ALLURE_BIN" ] || [ ! -x "$ALLURE_BIN" ]; then
  echo "ERROR: Allure CLI is not installed"
  exit 1
fi

# No results can exist if tests never started.
if [ ! -d "$RESULTS_DIR" ]; then
  echo "WARNING: No Allure results directory found"
  exit 0
fi

# Check for actual Allure test result JSON files.
shopt -s nullglob
RESULT_FILES=("${RESULTS_DIR}"/*-result.json)
shopt -u nullglob

if [ "${#RESULT_FILES[@]}" -eq 0 ]; then
  echo "WARNING: No Allure test results found"
  echo "Check the Allure JUnit integration in pom.xml"
  exit 0
fi

"$ALLURE_BIN" generate \
  "$RESULTS_DIR" \
  --clean \
  --output "$REPORT_DIR"

test -f "${REPORT_DIR}/index.html" ||
  { echo "ERROR: Allure index.html not generated"; exit 1; }

echo "SUCCESS: Allure HTML report generated"
echo "Open: ${REPORT_DIR}/index.html"
