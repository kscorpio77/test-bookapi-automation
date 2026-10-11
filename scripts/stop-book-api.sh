#!/usr/bin/env bash

# ============================================================
# Testbook API - Docker Cleanup
#
# Stops and removes only the Book API demo container.
# Keeps the Docker image for future use.
# ============================================================

set -Eeuo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-bookapi}"

echo "=========================================="
echo "Cleaning up Book API container"
echo "=========================================="

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is unavailable. Skipping cleanup."
    exit 0
fi

if ! docker info >/dev/null 2>&1; then
    echo "Docker Engine is unavailable."
    exit 0
fi

if docker container inspect "$CONTAINER_NAME" \
    >/dev/null 2>&1; then

    echo "Removing container: $CONTAINER_NAME"

    docker rm -f "$CONTAINER_NAME"

else
    echo "No Book API container found."
fi

echo "Cleanup completed."
