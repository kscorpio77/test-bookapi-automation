#!/bin/bash

set -e

# ============================================================
# Testbook API - Local Environment Startup
#
# Gets the latest application code from GitHub,
# builds the Docker image and starts the API on port 8080.
#
# This script DOES NOT run automation tests.
# ============================================================

APP_REPO_URL="https://github.com/kscorpio77/testbookapiworkflowdemo.git"
APP_DIR="../testbookapiworkflowdemo"
BRANCH="main"

IMAGE_NAME="testbook-api"
IMAGE_TAG="latest"
CONTAINER_NAME="bookapi"

HOST_PORT="8080"
CONTAINER_PORT="8080"

BASE_URL="http://localhost:${HOST_PORT}"

echo "=========================================="
echo " TESTBOOK API LOCAL ENVIRONMENT"
echo "=========================================="


# ------------------------------------------------------------
# 1. Stop/remove previous Testbook container
# ------------------------------------------------------------

echo ""
echo "Removing previous Testbook container if present..."

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true


# ------------------------------------------------------------
# 2. Check whether port 8080 is available
# ------------------------------------------------------------

echo ""
echo "Checking port ${HOST_PORT}..."

if lsof -iTCP:${HOST_PORT} -sTCP:LISTEN >/dev/null 2>&1; then

    echo ""
    echo "ERROR: Port ${HOST_PORT} is already being used."
    echo ""
    echo "Process using port ${HOST_PORT}:"
    lsof -iTCP:${HOST_PORT} -sTCP:LISTEN
    echo ""
    echo "Stop that application before running this script."
    echo ""
    echo "If Jenkins is using port 8080, stop Jenkins first."
    exit 1

fi

echo "Port ${HOST_PORT} is available."


# ------------------------------------------------------------
# 3. Get latest application code
# ------------------------------------------------------------

echo ""
echo "=========================================="
echo "Getting latest Testbook API source code"
echo "=========================================="

if [ -d "$APP_DIR/.git" ]; then

    echo "Repository already exists. Updating..."

    cd "$APP_DIR"

    git fetch origin
    git checkout "$BRANCH"
    git pull origin "$BRANCH"

else

    echo "Repository not found. Cloning..."

    git clone \
        --branch "$BRANCH" \
        "$APP_REPO_URL" \
        "$APP_DIR"

    cd "$APP_DIR"

fi


# ------------------------------------------------------------
# 4. Show application version
# ------------------------------------------------------------

echo ""
echo "Building application from:"

git log -1 --oneline


# ------------------------------------------------------------
# 5. Build Docker image
# ------------------------------------------------------------

echo ""
echo "=========================================="
echo "Building Docker image"
echo "=========================================="

docker build \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    .


# ------------------------------------------------------------
# 6. Start Testbook API
# ------------------------------------------------------------

echo ""
echo "=========================================="
echo "Starting Testbook API on port 8080"
echo "=========================================="

docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    "${IMAGE_NAME}:${IMAGE_TAG}"


# ------------------------------------------------------------
# 7. Wait for application
# ------------------------------------------------------------

echo ""
echo "Waiting for Testbook API..."

MAX_RETRIES=30
RETRY_COUNT=0

until curl --fail --silent \
    "${BASE_URL}/api/books" > /dev/null
do

    RETRY_COUNT=$((RETRY_COUNT + 1))

    if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then

        echo ""
        echo "ERROR: Testbook API failed to start."
        echo ""
        echo "Container logs:"
        docker logs "$CONTAINER_NAME"

        exit 1

    fi

    echo "Waiting... ${RETRY_COUNT}/${MAX_RETRIES}"

    sleep 2

done


# ------------------------------------------------------------
# 8. Success
# ------------------------------------------------------------

echo ""
echo "=========================================="
echo " TESTBOOK API IS UP AND RUNNING"
echo "=========================================="
echo ""
echo "Base URL:"
echo "  ${BASE_URL}"
echo ""
echo "Books API:"
echo "  ${BASE_URL}/api/books"
echo ""
echo "Container:"
docker ps --filter "name=${CONTAINER_NAME}"
echo ""
echo "You can now run your RestAssured tests."
echo ""
echo "To view logs:"
echo "  docker logs -f ${CONTAINER_NAME}"
echo ""
echo "To stop the application:"
echo "  docker stop ${CONTAINER_NAME}"
echo ""