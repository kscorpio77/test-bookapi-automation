# Testbook API Automation

An independent Java 17 API test framework for the Testbook Spring Boot API. This repository sends tests to an already-running API; it does not build, start, or deploy the application.

## Framework architecture

- **ConfigManager** resolves the target base URL from a JVM system property, an environment variable, or the packaged properties file.
- **BaseTest** configures REST Assured's reusable request/response specifications and logs request/response details when an assertion fails.
- **BookApiClient** encapsulates the documented HTTP methods, paths, and request payloads.
- **Book** is the Jackson request/response model for the four contract fields.
- **BookApiTest** contains JUnit 5 scenarios, including a generated-ID CRUD flow and validation/not-found checks. Created records are deleted during cleanup.

## Project structure

```text
.
├── pom.xml
├── README.md
├── .gitignore
├── .github/workflows/api-tests.yml
└── src/test/
    ├── java/com/testbook/automation/
    │   ├── base/BaseTest.java
    │   ├── client/BookApiClient.java
    │   ├── config/ConfigManager.java
    │   ├── model/Book.java
    │   └── tests/BookApiTest.java
    └── resources/config.properties
```

## Technology stack

Java 17, Maven, REST Assured, JUnit 5, Jackson, AssertJ, SLF4J, and Maven Surefire.

## Configuration

`ConfigManager` uses the first non-blank value in this order:

1. JVM system property `base.url`
2. Environment variable `BASE_URL`
3. `base.url` in `src/test/resources/config.properties`

The checked-in default is `http://localhost:8080`. No application URL is embedded in the test/client code.

## Run locally

Start the Testbook API separately, then from this repository run:

```bash
mvn clean test
```

To explicitly set the local URL:

```bash
mvn clean test -Dbase.url=http://localhost:8080
```

The system property takes precedence over `BASE_URL` and the properties-file default.

## Test a deployed AWS/EKS API

Make sure the API is deployed and reachable from the machine or runner executing the suite, then provide its load balancer URL:

```bash
mvn clean test -Dbase.url=http://<AWS-LOAD-BALANCER-URL>
```

Use `https://` if the load balancer is configured for TLS. This project only runs API tests; it does not provision or deploy AWS/EKS resources.

## GitHub Actions

`.github/workflows/api-tests.yml` runs on pushes and can also be started manually with **workflow_dispatch**. The workflow checks out this repository, configures Java 17 with Maven dependency caching, and executes `mvn clean test`.

For a manual run, provide the `base_url` input (default: `http://localhost:8080`). For push-triggered runs, configure the repository variable `API_BASE_URL` with a reachable API URL; if it is unset, the workflow uses the localhost default. The URL is passed as Maven's `-Dbase.url` property. The API must already be running and accessible to the GitHub-hosted runner.
