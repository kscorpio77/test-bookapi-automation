#!/usr/bin/env bash
set -Eeuo pipefail

# Executes RestAssured/JUnit tests using Maven.
# Maven's exit status determines whether the CI job passes.

BASE_URL="${BASE_URL:-http://localhost:8080}"

echo "===== Starting RestAssured API tests ====="
echo "Target API: $BASE_URL"

command -v mvn >/dev/null ||
  { echo "ERROR: Maven is not installed"; exit 1; }

mvn --batch-mode --no-transfer-progress \
  clean test \
  "-Dbase.url=${BASE_URL}"

echo "SUCCESS: Maven tests completed"
