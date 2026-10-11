#!/usr/bin/env bash
set -Eeuo pipefail

# Installs Allure CLI in the current user's home directory.
# Does not require sudo or change system-wide binaries.
# Compatible with macOS and Linux, with Java and curl installed.

ALLURE_VERSION="${ALLURE_VERSION:-2.29.0}"
INSTALL_ROOT="${HOME}/.local/opt"
BIN_DIR="${HOME}/.local/bin"
ALLURE_HOME="${INSTALL_ROOT}/allure-${ALLURE_VERSION}"

echo "===== Installing Allure ${ALLURE_VERSION} ====="

command -v java >/dev/null ||
  { echo "ERROR: Java is required"; exit 1; }

command -v curl >/dev/null ||
  { echo "ERROR: curl is required"; exit 1; }

mkdir -p "$INSTALL_ROOT" "$BIN_DIR"

if [ ! -x "${ALLURE_HOME}/bin/allure" ]; then

  ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/allure.XXXXXX.tgz")"
  trap 'rm -f "$ARCHIVE"' EXIT

  curl --fail --location --retry 3 \
    --output "$ARCHIVE" \
    "https://github.com/allure-framework/allure2/releases/download/${ALLURE_VERSION}/allure-${ALLURE_VERSION}.tgz"

  tar -xzf "$ARCHIVE" -C "$INSTALL_ROOT"
fi

ln -sfn "${ALLURE_HOME}/bin/allure" \
  "${BIN_DIR}/allure"

# Available to this shell and its child processes.
export PATH="${BIN_DIR}:${PATH}"

# Persist PATH for subsequent GitHub Actions steps.
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$BIN_DIR" >> "$GITHUB_PATH"
fi

echo "===== Installed Allure version ====="
"${BIN_DIR}/allure" --version
