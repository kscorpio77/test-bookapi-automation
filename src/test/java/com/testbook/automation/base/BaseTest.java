package com.testbook.automation.base;

import com.testbook.automation.client.BookApiClient;
import com.testbook.automation.config.ConfigManager;
import io.restassured.RestAssured;
import io.restassured.builder.RequestSpecBuilder;
import io.restassured.builder.ResponseSpecBuilder;
import io.restassured.http.ContentType;
import io.restassured.specification.RequestSpecification;
import io.restassured.specification.ResponseSpecification;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;

public abstract class BaseTest {
    protected static RequestSpecification requestSpecification;
    protected static ResponseSpecification jsonResponseSpecification;
    protected BookApiClient bookApiClient;

    @BeforeAll
    static void configureRestAssured() {
        RestAssured.baseURI = ConfigManager.getBaseUrl();
        RestAssured.enableLoggingOfRequestAndResponseIfValidationFails();

        requestSpecification = new RequestSpecBuilder()
                .setBaseUri(ConfigManager.getBaseUrl())
                .setAccept(ContentType.ANY)
                .setContentType(ContentType.JSON)
                .build();

        jsonResponseSpecification = new ResponseSpecBuilder()
                .expectContentType(ContentType.JSON)
                .build();
    }

    @BeforeEach
    void createApiClient() {
        bookApiClient = new BookApiClient(requestSpecification);
    }
}
