#!/usr/bin/env bash

# ============================================================
# Testbook API - Build and Start Application
#
# Responsibilities:
# 1. Validate required tools
# 2. Build Docker image
# 3. Remove previous demo container if present
# 4. Start the Book API container
# 5. Wait until the REST API is ready
#
# Works on:
# - macOS with Docker Desktop
# - GitHub Actions Ubuntu runner
#
# Usage:
#   bash scripts/start-book-api.sh [APP_DIRECTORY]
#
# Example:
#   bash scripts/start-book-api.sh ./book-api
# ============================================================

set -Eeuo pipefail

APP_DIR="${1:-./book-api}"

IMAGE_NAME="${IMAGE_NAME:-testbook-api:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-bookapi}"
HOST_PORT="${HOST_PORT:-8080}"
CONTAINER_PORT="${CONTAINER_PORT:-8080}"

BASE_URL="http://localhost:${HOST_PORT}"
HEALTH_URL="${BASE_URL}/api/books"

MAX_ATTEMPTS=60
SLEEP_SECONDS=2

START_TIME=$(date +%s)

log() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

on_exit() {
    EXIT_CODE=$?
    END_TIME=$(date +%s)
    TOTAL=$((END_TIME - START_TIME))

    echo ""
    echo "Script execution time: ${TOTAL} seconds"

    if [ "$EXIT_CODE" -ne 0 ]; then
        echo "Startup failed."

        if docker container inspect "$CONTAINER_NAME" \
            >/dev/null 2>&1; then

            echo "Container logs:"
            docker logs --tail 100 "$CONTAINER_NAME" || true
        fi
    fi
}

trap on_exit EXIT

# ------------------------------------------------------------
# Step 1: Validate required tools
# ------------------------------------------------------------

log "STEP 1: Checking required tools"

for TOOL in docker curl; do

    command -v "$TOOL" >/dev/null 2>&1 ||
        fail "$TOOL is not installed."

    echo "OK: $TOOL"
done

docker info >/dev/null 2>&1 ||
    fail "Docker Engine is not running."

[ -d "$APP_DIR" ] ||
    fail "Application directory not found: $APP_DIR"

[ -f "$APP_DIR/Dockerfile" ] ||
    fail "Dockerfile not found inside $APP_DIR"

# ------------------------------------------------------------
# Step 2: Build Docker image
# ------------------------------------------------------------

log "STEP 2: Building Docker image"

docker build \
    --tag "$IMAGE_NAME" \
    "$APP_DIR"

echo "Docker image built: $IMAGE_NAME"

# ------------------------------------------------------------
# Step 3: Remove existing demo container
# ------------------------------------------------------------

log "STEP 3: Checking existing container"

if docker container inspect "$CONTAINER_NAME" \
    >/dev/null 2>&1; then

    echo "Removing existing container: $CONTAINER_NAME"

    docker rm -f "$CONTAINER_NAME"
else
    echo "No existing demo container found."
fi

# ------------------------------------------------------------
# Step 4: Start the application
# ------------------------------------------------------------

log "STEP 4: Starting Book API"

docker run \
    --detach \
    --name "$CONTAINER_NAME" \
    --publish "${HOST_PORT}:${CONTAINER_PORT}" \
    "$IMAGE_NAME"

echo "Container started."

docker ps \
    --filter "name=^/${CONTAINER_NAME}$"

# ------------------------------------------------------------
# Step 5: Wait for the application
# ------------------------------------------------------------

log "STEP 5: Waiting for Book API"

echo "Checking: $HEALTH_URL"

for ((ATTEMPT=1; ATTEMPT<=MAX_ATTEMPTS; ATTEMPT++)); do

    if curl \
        --fail \
        --silent \
        --show-error \
        --output /dev/null \
        --max-time 3 \
        "$HEALTH_URL" 2>/dev/null; then

        log "BOOK API IS READY"

        echo "Application URL: $BASE_URL"
        echo "Books endpoint : $HEALTH_URL"

        exit 0
    fi

    # Detect a container that crashed.
    RUNNING=$(docker inspect \
        --format '{{.State.Running}}' \
        "$CONTAINER_NAME" 2>/dev/null || echo false)

    if [ "$RUNNING" != "true" ]; then
        fail "Docker container stopped unexpectedly."
    fi

    echo "Waiting for application: $ATTEMPT/$MAX_ATTEMPTS"

    sleep "$SLEEP_SECONDS"
done

fail "Book API did not become ready within the allowed time."
