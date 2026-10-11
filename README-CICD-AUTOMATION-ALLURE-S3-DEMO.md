# Testbook API — GitHub Actions, Bash, Docker, RestAssured, Allure and AWS S3

## Student hands-on lab

**Goal:** Build and run a Spring Boot Book API in Docker, execute RestAssured API tests, generate Maven Surefire and Allure reports, and automatically publish the reports to both GitHub Actions artifacts and Amazon S3.

**Architecture:** GitHub Actions orchestrates reusable Bash scripts. GitHub uses **OIDC** to assume an AWS IAM role without storing long-lived AWS access keys. The role is authorized to upload test reports to an existing, private S3 bucket.

```text
GitHub Actions (automation repository)
  |-- Checkout automation repository
  |-- Checkout Spring Boot application repository -> ./book-api
  |-- Setup Java 17
  |-- scripts/start-book-api.sh ./book-api  -> Docker container on localhost:8080
  |-- scripts/run-api-tests.sh             -> RestAssured + JUnit + Maven
  |-- scripts/install-allure.sh
  |-- scripts/generate-allure-report.sh    -> Allure HTML
  |-- scripts/stop-book-api.sh             -> stop container / collect logs
  |-- Upload GitHub Actions artifacts
  |-- GitHub OIDC -> AWS IAM role
  `-- scripts/upload-reports-s3.sh         -> private S3 bucket
```

> **Lab conventions:** This guide uses AWS account `316255801172`, region `eu-north-1`, bucket `wf-ksdemo-bucket`, GitHub owner `kscorpio77`, application repository `testbookapiworkflowdemo`, and automation repository `test-bookapi-automation`. If using your own account, substitute **your own** IDs, repository names and bucket. The role ARN is not a password. Never commit AWS access keys or secret access keys.

## 1. Prerequisites

- A GitHub account with access to both repositories.
- An AWS account with permission to configure IAM, an OIDC identity provider and S3.
- A working Spring Boot application repository containing its `Dockerfile`, `pom.xml` and `src/`.
- An automation repository containing its own `pom.xml`, `src/` and the scripts listed below.
- A browser; **no AWS CLI installation is required on the student's computer** to run the GitHub-hosted workflow.
- For optional local execution: Git, Java 17, Maven, Docker Desktop, Bash, and (for local S3 publishing) AWS CLI with appropriate AWS credentials.

### Repository structure

```text
test-bookapi-automation/
├── .github/
│   └── workflows/
│       └── api-test-with-scripts.yml
├── scripts/
│   ├── start-book-api.sh
│   ├── run-api-tests.sh
│   ├── install-allure.sh
│   ├── generate-allure-report.sh
│   ├── stop-book-api.sh
│   └── upload-reports-s3.sh
├── src/
├── pom.xml
└── README.md
```

**Why is there no `book-api` folder in the automation repository?** The workflow creates it **on the GitHub Actions runner** by checking out the separate application repository with `path: book-api`. It does not have to exist on your MacBook. The script `bash scripts/start-book-api.sh ./book-api` passes that newly checked-out folder to the Docker build script.

## 2. Create the S3 bucket in AWS Console

1. Sign in to the [AWS Management Console](https://console.aws.amazon.com/).
2. Open **S3 → General purpose buckets → Create bucket**.
3. Choose **AWS Region: Europe (Stockholm), `eu-north-1`**.
4. Enter an available globally unique bucket name. For the demonstrated setup, the existing bucket is `wf-ksdemo-bucket`; **do not attempt to create a second bucket with the same name**.
5. Keep **Block all public access** enabled. Keep the bucket private.
6. Leave other settings at defaults for this lab, then choose **Create bucket**.
7. Open the bucket and verify its name and region.

> The upload script used in this lab **checks that the bucket exists**. It does not create or change bucket configuration. Bucket creation is a separate, one-time infrastructure setup.

## 3. Configure GitHub as an AWS OIDC identity provider

OIDC lets GitHub prove its identity to AWS and obtain temporary AWS credentials. No long-lived AWS access keys are needed.

1. In AWS Console, open **IAM → Identity providers**.
2. If `token.actions.githubusercontent.com` already exists in this AWS account, open it and confirm the audience includes `sts.amazonaws.com`. **Do not create a duplicate provider.**
3. Otherwise, choose **Add provider**.
4. Select **OpenID Connect**.
5. Provider URL: `https://token.actions.githubusercontent.com`.
6. Audience: `sts.amazonaws.com`.
7. Create the provider.

## 4. Create an IAM role for GitHub Actions

1. Open **IAM → Roles → Create role**.
2. Select **Web identity** (or the equivalent federated-identity option in the current console).
3. Choose the GitHub OIDC provider `token.actions.githubusercontent.com`.
4. Choose audience `sts.amazonaws.com`.
5. If the console asks for GitHub organisation/repository/branch, use `kscorpio77`, `test-bookapi-automation`, and `main` respectively. **You will verify and, if necessary, correct the generated trust policy below.**
6. For this isolated classroom demo, attach the AWS-managed **`AmazonS3FullAccess`** policy. **Do not select `AmazonS3ExpressFullAccess`**: it is for S3 Express directory buckets and does not provide the expected general-purpose bucket permissions.
7. Name the role `GitHubActionsTestbookReportsRole`, then create it.
8. Open the role and copy its **ARN**. For this demonstration:

   ```text
   arn:aws:iam::316255801172:role/GitHubActionsTestbookReportsRole
   ```

### 4.1 Configure the role's trust relationship

Open **IAM → Roles → GitHubActionsTestbookReportsRole → Trust relationships → Edit trust policy**.

**Important:** In the successfully debugged demonstration, CloudTrail showed that GitHub sends an **ID-qualified OIDC subject** with GitHub owner and repository numeric IDs. The default, name-only subject did not match. Use the exact subject emitted by *your own* GitHub repository. The following policy matches the demonstrated repository and its `main` branch:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::316255801172:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:kscorpio77@223097894/test-bookapi-automation@1402997679:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

Choose **Update policy**. This policy answers **who is allowed to assume the role**. The attached `AmazonS3FullAccess` policy answers **what that role can do** after authentication.

**Do not assume all repositories use this subject format.** Other repositories may use a traditional name-only subject, a GitHub Environment subject, or a customised OIDC subject. Use the actual `sub` value from a trusted diagnostic source. Do not use a broad wildcard such as `repo:*` to bypass authentication errors.

### 4.2 Verify the permissions policy

Open the role's **Permissions** tab. The attached policy should read:

```text
AmazonS3FullAccess
```

Not:

```text
AmazonS3ExpressFullAccess
```

If the wrong policy is attached, choose **Add permissions → Attach policies**, select `AmazonS3FullAccess`, attach it, and then remove `AmazonS3ExpressFullAccess`.

**Security note:** `AmazonS3FullAccess` is deliberately broad for this temporary training lab. In a production system, replace it with least-privilege permissions scoped to the required bucket and report prefix (typically including `s3:ListBucket` and `s3:PutObject`, with other actions only as needed). Delete unused demo roles and buckets after the exercise.

## 5. Configure GitHub repository variables

1. Open the **automation** repository: `https://github.com/kscorpio77/test-bookapi-automation`.
2. Select **Settings → Secrets and variables → Actions → Variables**.
3. Click **New repository variable** for each value below.

| Variable name | Demonstration value |
|---|---|
| `AWS_ROLE_ARN` | `arn:aws:iam::316255801172:role/GitHubActionsTestbookReportsRole` |
| `AWS_REGION` | `eu-north-1` |
| `REPORTS_BUCKET` | `wf-ksdemo-bucket` |

These are identifiers/configuration values, not passwords. **Repository variables** are appropriate for this single-environment lab. If you instead created repository **secrets**, use `${{ secrets.NAME }}` rather than `${{ vars.NAME }}` in the workflow.

## 6. Configure the GitHub Actions workflow

Create or edit `.github/workflows/end-to-end-api-automation-docker-allure-s3.yml` in the automation repository.

> **Trigger choice:** The example supports pushes to `main`, manual runs, and `repository_dispatch`. For a controlled classroom demo, you can temporarily remove the `push` and `repository_dispatch` triggers and keep only `workflow_dispatch`. If another workflow file is enabled, it may run separately on the same push; disable the unused workflow from its **Actions** page or remove its triggers.

```yaml
name: Testbook API - CI Automation Pipeline

on:
  push:
    branches:
      - main
  workflow_dispatch:
  repository_dispatch:
    types:
      - book-api-build-success

permissions:
  contents: read
  id-token: write

jobs:
  api-automation:
    name: Build, Test, Generate Reports and Upload to S3
    runs-on: ubuntu-latest
    timeout-minutes: 30

    env:
      BASE_URL: http://localhost:8080
      IMAGE_NAME: testbook-api:latest
      CONTAINER_NAME: bookapi
      HOST_PORT: "8080"
      CONTAINER_PORT: "8080"
      ALLURE_VERSION: "2.29.0"
      ALLURE_RESULTS_DIR: target/allure-results
      ALLURE_REPORT_DIR: target/allure-report
      LOG_DIR: target/docker-logs
      AWS_REGION: ${{ vars.AWS_REGION }}
      REPORTS_BUCKET: ${{ vars.REPORTS_BUCKET }}
      REPORT_PREFIX: testbook-api

    steps:
      - name: Checkout Automation Repository
        uses: actions/checkout@v4

      - name: Checkout Book API Application
        uses: actions/checkout@v4
        with:
          repository: kscorpio77/testbookapiworkflowdemo
          ref: main
          path: book-api
          # If this is a private cross-repository checkout,
          # configure an appropriately scoped read-only token.

      - name: Set Up Java 17
        uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: '17'
          cache: maven

      - name: Verify Build Tools
        run: |
          java -version
          mvn -version
          docker --version
          aws --version
          bash --version

      - name: Build Docker Image and Start Book API
        run: bash scripts/start-book-api.sh ./book-api

      - name: Execute RestAssured API Tests
        run: bash scripts/run-api-tests.sh

      - name: Install Allure Reporting Tool
        if: always()
        run: bash scripts/install-allure.sh

      - name: Generate Allure HTML Report
        if: always()
        run: bash scripts/generate-allure-report.sh

      - name: Collect Logs and Stop Book API
        if: always()
        run: bash scripts/stop-book-api.sh

      - name: Upload Maven Surefire Reports
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: surefire-test-reports
          path: target/surefire-reports/
          if-no-files-found: warn
          retention-days: 30

      - name: Upload Allure HTML Report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: allure-html-report
          path: target/allure-report/
          if-no-files-found: warn
          retention-days: 30

      - name: Upload Raw Allure Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: allure-results
          path: target/allure-results/
          if-no-files-found: warn
          retention-days: 30

      - name: Upload Docker Application Logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: book-api-docker-logs
          path: target/docker-logs/
          if-no-files-found: warn
          retention-days: 30

      - name: Configure AWS Credentials
        id: aws_auth
        if: always()
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
          role-session-name: testbook-api-ci

      - name: Upload Test Reports to AWS S3
        if: ${{ always() && steps.aws_auth.outcome == 'success' }}
        run: bash scripts/upload-reports-s3.sh

      - name: Publish Pipeline Summary
        if: always()
        run: |
          {
            echo '## Testbook API CI Pipeline'
            echo ''
            echo '| Component | Technology |'
            echo '|---|---|'
            echo '| Build | Docker |'
            echo '| Application | Spring Boot |'
            echo '| API Tests | RestAssured + JUnit |'
            echo '| Reporting | Allure + Surefire |'
            echo '| Storage | GitHub Artifacts + Amazon S3 |'
            echo '| AWS Authentication | GitHub OIDC |'
          } >> "$GITHUB_STEP_SUMMARY"
```

**Note:** `if: always()` deliberately collects reports even after test failures. The S3 upload is guarded by the result of the AWS authentication step so it does not produce a second, misleading credentials error. If your application repository is private, `actions/checkout` from another repository may require a separate token with read access. The workflow checks out application `main`; it does not automatically select the exact commit that triggered `repository_dispatch`.

## 7. Add the S3 upload Bash script

Create `scripts/upload-reports-s3.sh` in the automation repository:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

AWS_REGION="${AWS_REGION:-eu-north-1}"
REPORTS_BUCKET="${REPORTS_BUCKET:?ERROR: REPORTS_BUCKET is not configured}"
REPORT_PREFIX="${REPORT_PREFIX:-testbook-api}"
RUN_ID="${GITHUB_RUN_ID:-local}"
RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-1}"

ALLURE_REPORT_DIR="${ALLURE_REPORT_DIR:-target/allure-report}"
ALLURE_RESULTS_DIR="${ALLURE_RESULTS_DIR:-target/allure-results}"
SUREFIRE_REPORT_DIR="${SUREFIRE_REPORT_DIR:-target/surefire-reports}"
LOG_DIR="${LOG_DIR:-target/docker-logs}"

DESTINATION="s3://${REPORTS_BUCKET}/${REPORT_PREFIX}/runs/${RUN_ID}/attempt-${RUN_ATTEMPT}"

command -v aws >/dev/null 2>&1 || {
  echo 'ERROR: AWS CLI is not installed.' >&2
  exit 1
}

echo '===== Verify AWS identity ====='
aws sts get-caller-identity

echo '===== Check existing S3 bucket ====='
aws s3api head-bucket --bucket "$REPORTS_BUCKET" --region "$AWS_REGION" || {
  echo "ERROR: Cannot access bucket $REPORTS_BUCKET; check region, bucket name, and IAM permissions." >&2
  exit 1
}

UPLOAD_COUNT=0
upload_directory() {
  local source="$1"
  local folder="$2"
  if [[ -d "$source" ]] && [[ -n "$(find "$source" -type f -print -quit)" ]]; then
    echo "Uploading $source ..."
    aws s3 sync "$source" "${DESTINATION}/${folder}/" \
      --region "$AWS_REGION" --only-show-errors
    UPLOAD_COUNT=$((UPLOAD_COUNT + 1))
  else
    echo "Skipping $source: missing or empty."
  fi
}

upload_directory "$ALLURE_REPORT_DIR" 'allure-html-report'
upload_directory "$ALLURE_RESULTS_DIR" 'allure-results'
upload_directory "$SUREFIRE_REPORT_DIR" 'surefire-reports'
upload_directory "$LOG_DIR" 'docker-logs'

if (( UPLOAD_COUNT == 0 )); then
  echo 'ERROR: No report directories contained files.' >&2
  exit 1
fi

echo "Uploaded $UPLOAD_COUNT directories to ${DESTINATION}/"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo ''
    echo '## AWS S3 Report Publishing'
    echo ''
    echo "- Bucket: \`${REPORTS_BUCKET}\`"
    echo "- Region: \`${AWS_REGION}\`"
    echo "- S3 path: \`${DESTINATION}/\`"
    echo "- Uploaded directories: ${UPLOAD_COUNT}"
  } >> "$GITHUB_STEP_SUMMARY"
fi
```

**What the script does:** It checks AWS identity, confirms access to the **existing** bucket, uploads any nonempty report folders, and writes the destination to the GitHub Actions summary. The script does not create buckets or expose them publicly.

The other five scripts must already be present and working in `scripts/`:

| Script | Purpose |
|---|---|
| `start-book-api.sh` | Build Docker image, start the Spring Boot container and wait for `/api/books` |
| `run-api-tests.sh` | Run Maven/RestAssured/JUnit tests |
| `install-allure.sh` | Install the Allure command-line tool |
| `generate-allure-report.sh` | Turn Allure results into HTML |
| `stop-book-api.sh` | Collect Docker logs and remove the demo container |
| `upload-reports-s3.sh` | Upload available reports/logs to S3 |

> If Allure is configured to write results to the repository-root `allure-results/` directory instead of `target/allure-results/`, update `ALLURE_RESULTS_DIR` in the workflow accordingly. Allure HTML is not generated merely by uploading Maven Surefire XML: the test project must have the appropriate Allure integration and produce result files.

## 8. Run the pipeline from GitHub (no IntelliJ required)

1. Commit the workflow and scripts to the automation repository's `main` branch.
2. Open the repository on GitHub.
3. Choose **Actions**.
4. Select **Testbook API - CI Automation Pipeline**.
5. Click **Run workflow**, select `main`, and confirm.
6. Open the new workflow run and click the job **Build, Test, Generate Reports and Upload to S3**.
7. Expand each step to inspect its logs.
8. Confirm that **Configure AWS Credentials** says the role was successfully assumed.
9. Confirm that **Upload Test Reports to AWS S3** shows successful uploads.
10. Open the **Summary** and look for the S3 destination.

### Expected GitHub Actions stages

1. Checkout both repositories.
2. Prepare Java/Maven/Docker environment.
3. Build and start the API container.
4. Execute API tests.
5. Install Allure and generate the HTML report.
6. Collect logs and stop the container.
7. Upload GitHub artifacts.
8. Authenticate to AWS using OIDC.
9. Upload reports to S3.
10. Publish the pipeline summary.

## 9. Find the reports

### In GitHub

Open the completed workflow run → **Summary → Artifacts**. Download `surefire-test-reports`, `allure-html-report`, `allure-results`, or `book-api-docker-logs` when available.

### In AWS S3

1. Open **AWS Console → S3 → General purpose buckets**.
2. Click `wf-ksdemo-bucket`.
3. Browse **`testbook-api/ → runs/ → <run-id>/ → attempt-<number>/`**.
4. Open the report folders to see uploaded files.

Example:

```text
s3://wf-ksdemo-bucket/
└── testbook-api/
    └── runs/
        └── 38122003942/
            └── attempt-3/
                ├── allure-html-report/
                │   ├── index.html
                │   └── ...
                ├── allure-results/
                ├── surefire-reports/
                └── docker-logs/       # only if log files were generated
```

**Viewing Allure:** Download the full Allure HTML artifact/report directory and serve it locally with a suitable web server if needed. Simply clicking `index.html` in a private S3 bucket does not turn the bucket into a public report website. Keep reports private; do not disable Block Public Access just to view them.

## 10. Troubleshooting — errors encountered during this lab

### A. `Not authorized to perform sts:AssumeRoleWithWebIdentity`

**Meaning:** AWS does not trust the identity GitHub presented.

**Check:** IAM role → **Trust relationships**, GitHub repository/branch, the exact `AWS_ROLE_ARN` variable, OIDC provider and `id-token: write` permission.

In this lab, CloudTrail revealed that the actual subject was:

```text
repo:kscorpio77@223097894/test-bookapi-automation@1402997679:ref:refs/heads/main
```

The original policy expected:

```text
repo:kscorpio77/test-bookapi-automation:ref:refs/heads/main
```

The mismatch caused authentication to fail. The correction was to match the **actual subject exactly** in the IAM role trust policy.

**Diagnose without editing local code:** Open **AWS CloudTrail → Event history**, search for event name `AssumeRoleWithWebIdentity` around the failed run, and inspect `userIdentity.principalId`, `userIdentity.userName`, `errorCode`, and the role ARN. Relevant STS events may appear in a different region or not expose all claims. Never share OIDC tokens.

### B. `403 Forbidden` on `HeadBucket`

**Meaning:** GitHub successfully assumed the IAM role, but the role could not access the general-purpose S3 bucket.

**Actual issue in this lab:** The role had **`AmazonS3ExpressFullAccess`**, not **`AmazonS3FullAccess`**.

**Fix:** IAM → Roles → `GitHubActionsTestbookReportsRole` → **Permissions → Add permissions → Attach policies** → choose `AmazonS3FullAccess`, then remove `AmazonS3ExpressFullAccess`. Rerun the workflow. If a 403 persists, inspect the bucket policy, AWS organisation restrictions, bucket ownership and region.

### C. `Unable to locate credentials`

**Meaning:** The upload script ran after AWS authentication failed. Fix authentication first. The workflow above prevents the upload step from running unless `aws_auth` succeeded.

### D. `No files were found ... target/docker-logs/`

**Meaning:** The log folder was absent or empty. This is a **warning**, not necessarily the reason the pipeline failed. Check whether the container started, whether `stop-book-api.sh` wrote logs, and whether `LOG_DIR` matches the script's output directory.

### E. Allure report missing or empty

Check the test integration, whether `*-result.json` files were created, and whether the configured `ALLURE_RESULTS_DIR` matches the actual results directory. The `generate-allure-report.sh` script must produce `target/allure-report/index.html` before upload.

### F. Application checkout fails

Verify the application repository name and that the workflow has read access. A private application repository may require an appropriately scoped cross-repository token. The automation repository's default `GITHUB_TOKEN` is generally scoped to its own repository.

### G. Two workflows run at the same time

If both `api-tests.yml` and `end-to-end-api-automation-docker-allure-s3.yml` listen to pushes, both may run. For a classroom demo, use **Actions → select unused workflow → ... → Disable workflow** on GitHub, or restrict triggers in the YAML. Disabling the cloud workflow does not delete the file from your MacBook.

## 11. Student exercises

1. Run the workflow manually and record its GitHub run ID.
2. Explain why the application source is checked out into `./book-api` even though that folder is not committed to the automation repository.
3. Find one Maven Surefire report and one Allure report in the GitHub artifacts.
4. Find the matching `runs/<run-id>/attempt-<number>/` folder in S3.
5. Explain the difference between an **IAM trust policy** and an **IAM permissions policy**.
6. Explain why **OIDC** is preferable to storing permanent AWS access keys in GitHub.
7. Identify what happens when API tests fail: which report-generation and cleanup steps still run?
8. Explain why `AmazonS3ExpressFullAccess` did not provide the expected access to this general-purpose S3 bucket.

## 12. Production best practices and cleanup

- Use GitHub **Environment Variables** for environment-specific values when you have DEV/TEST/PROD, with distinct IAM roles and bucket paths.
- Restrict IAM permissions to the required bucket and report prefix; do not keep `AmazonS3FullAccess` in production.
- Restrict the OIDC trust policy to the intended repository, branch/environment and audience.
- Keep S3 buckets private, enable appropriate encryption, retention/lifecycle policies and audit logging.
- Pin third-party GitHub Actions to reviewed commit SHAs for stricter supply-chain security.
- Consider report retention costs and avoid uploading sensitive customer data or secrets into reports.
- For cleanup after the exercise, delete unneeded report objects and (if dedicated solely to this demo) the bucket, role and OIDC provider only after verifying they are not used elsewhere.

---

**Success criteria:** A manual GitHub Actions run builds the Book API, runs tests, generates reports, successfully assumes the AWS role through OIDC, and uploads the available reports into the expected private S3 run folder.

## 13. To see the LO reports locally on Intellij, execute the following command
Make sure that you have allure installed on the command line in order to execute this command

allure generate target/allure-results --clean -o target/allure-report
