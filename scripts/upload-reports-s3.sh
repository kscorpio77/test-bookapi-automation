
#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# TESTBOOK API - AWS S3 REPORT UPLOAD
#
# Responsibilities:
#
# 1. Verify AWS CLI installation
# 2. Verify AWS authentication
# 3. Verify S3 bucket availability
# 4. Upload Allure HTML reports
# 5. Upload raw Allure results
# 6. Upload Maven Surefire reports
# 7. Upload Docker application logs
# 8. Publish upload details in GitHub Actions
#
# NOTE:
# The S3 bucket is created manually in AWS.
# This script does NOT create or modify buckets.
# ============================================================

# ============================================================
# STEP 1 - LOAD CONFIGURATION
# ============================================================

AWS_REGION="${AWS_REGION:-eu-north-1}"

# Required GitHub repository variable
REPORTS_BUCKET="${REPORTS_BUCKET:?ERROR: REPORTS_BUCKET is not configured}"

REPORT_PREFIX="${REPORT_PREFIX:-testbook-api}"

RUN_ID="${GITHUB_RUN_ID:-local}"
RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"

# Report locations
ALLURE_REPORT_DIR="${ALLURE_REPORT_DIR:-target/allure-report}"
ALLURE_RESULTS_DIR="${ALLURE_RESULTS_DIR:-target/allure-results}"
SUREFIRE_REPORT_DIR="${SUREFIRE_REPORT_DIR:-target/surefire-reports}"
LOG_DIR="${LOG_DIR:-target/docker-logs}"

# Unique S3 destination for every workflow run
S3_DESTINATION="s3://${REPORTS_BUCKET}/${REPORT_PREFIX}/runs/${RUN_ID}/attempt-${RUN_ATTEMPT}"

echo "============================================"
echo " TESTBOOK API - S3 REPORT UPLOAD"
echo "============================================"

echo "AWS Region     : $AWS_REGION"
echo "S3 Bucket      : $REPORTS_BUCKET"
echo "S3 Destination : $S3_DESTINATION"

# ============================================================
# STEP 2 - VERIFY AWS CLI
# ============================================================

echo ""
echo "===== Checking AWS CLI ====="

if ! command -v aws >/dev/null 2>&1; then
    echo "ERROR: AWS CLI is not installed."
    exit 1
fi

aws --version

# ============================================================
# STEP 3 - VERIFY AWS AUTHENTICATION
# ============================================================

echo ""
echo "===== Verifying AWS Authentication ====="

if ! aws sts get-caller-identity; then
    echo "ERROR: AWS authentication failed."
    echo "Check the IAM Role ARN and GitHub OIDC configuration."
    exit 1
fi

echo "AWS authentication successful."

# ============================================================
# STEP 4 - VERIFY S3 BUCKET
# ============================================================

echo ""
echo "===== Checking S3 Bucket ====="

if ! aws s3api head-bucket \
    --bucket "$REPORTS_BUCKET" \
    --region "$AWS_REGION"; then

    echo "ERROR: Cannot access S3 bucket: $REPORTS_BUCKET"
    echo "Check bucket name, region and IAM permissions."
    exit 1
fi

echo "S3 bucket exists and is accessible."

# ============================================================
# STEP 5 - UPLOAD REPORT DIRECTORIES
# ============================================================

UPLOAD_COUNT=0

upload_directory() {

    local SOURCE="$1"
    local TARGET="$2"

    echo ""
    echo "Checking directory: $SOURCE"

    # Verify directory exists and contains files
    if [ ! -d "$SOURCE" ]; then
        echo "WARNING: Directory does not exist: $SOURCE"
        return 0
    fi

    if [ -z "$(find "$SOURCE" -type f -print -quit)" ]; then
        echo "WARNING: Directory is empty: $SOURCE"
        return 0
    fi

    echo "Uploading $SOURCE to S3..."

    aws s3 sync \
        "$SOURCE" \
        "${S3_DESTINATION}/${TARGET}/" \
        --region "$AWS_REGION" \
        --only-show-errors

    UPLOAD_COUNT=$((UPLOAD_COUNT + 1))

    echo "SUCCESS: Uploaded $SOURCE"
}

# ============================================================
# STEP 6 - UPLOAD ALLURE HTML REPORT
# ============================================================

upload_directory \
    "$ALLURE_REPORT_DIR" \
    "allure-html-report"

# ============================================================
# STEP 7 - UPLOAD RAW ALLURE RESULTS
# ============================================================

upload_directory \
    "$ALLURE_RESULTS_DIR" \
    "allure-results"

# ============================================================
# STEP 8 - UPLOAD MAVEN SUREFIRE REPORTS
# ============================================================

upload_directory \
    "$SUREFIRE_REPORT_DIR" \
    "surefire-reports"

# ============================================================
# STEP 9 - UPLOAD DOCKER APPLICATION LOGS
# ============================================================

upload_directory \
    "$LOG_DIR" \
    "docker-logs"

# ============================================================
# STEP 10 - VERIFY UPLOAD RESULTS
# ============================================================

echo ""
echo "============================================"
echo " S3 UPLOAD SUMMARY"
echo "============================================"

if [ "$UPLOAD_COUNT" -eq 0 ]; then

    echo "ERROR: No report directories were uploaded."
    echo "Check Maven, Allure and Docker log generation."

    exit 1

fi

echo "Successfully uploaded $UPLOAD_COUNT directories."

echo ""
echo "S3 Location:"
echo "${S3_DESTINATION}/"

# ============================================================
# STEP 11 - PUBLISH GITHUB ACTIONS SUMMARY
# ============================================================

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then

    {
        echo ""
        echo "## AWS S3 Report Upload"
        echo ""
        echo "| Property | Value |"
        echo "|---|---|"
        echo "| Bucket | \`${REPORTS_BUCKET}\` |"
        echo "| Region | \`${AWS_REGION}\` |"
        echo "| Uploaded Directories | ${UPLOAD_COUNT} |"
        echo ""
        echo "**S3 Destination:**"
        echo ""
        echo "\`${S3_DESTINATION}/\`"
        echo ""
    } >> "$GITHUB_STEP_SUMMARY"

fi

echo ""
echo "AWS S3 report upload completed successfully."
