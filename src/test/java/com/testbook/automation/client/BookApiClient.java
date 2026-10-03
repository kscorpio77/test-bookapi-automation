package com.testbook.automation.client;

import com.testbook.automation.model.Book;
import io.restassured.RestAssured;
import io.restassured.http.ContentType;
import io.restassured.response.Response;
import io.restassured.specification.RequestSpecification;

import java.util.Objects;

public class BookApiClient {
    private static final String BOOKS_PATH = "/api/books";
    private final RequestSpecification requestSpecification;

    public BookApiClient(RequestSpecification requestSpecification) {
        this.requestSpecification = Objects.requireNonNull(requestSpecification);
    }

    public Response getHome() {
        return RestAssured.given()
                .spec(requestSpecification)
                .when()
                .get("/");
    }

    public Response getAllBooks() {
        return RestAssured.given()
                .spec(requestSpecification)
                .when()
                .get(BOOKS_PATH);
    }

    public Response getBookById(Long id) {
        return RestAssured.given()
                .spec(requestSpecification)
                .when()
                .get(BOOKS_PATH + "/{id}", id);
    }

    public Response createBook(Book book) {
        return RestAssured.given()
                .spec(requestSpecification)
                .contentType(ContentType.JSON)
                .body(book)
                .when()
                .post(BOOKS_PATH);
    }

    public Response updateBook(Long id, Book book) {
        return RestAssured.given()
                .spec(requestSpecification)
                .contentType(ContentType.JSON)
                .body(book)
                .when()
                .put(BOOKS_PATH + "/{id}", id);
    }

    public Response deleteBook(Long id) {
        return RestAssured.given()
                .spec(requestSpecification)
                .when()
                .delete(BOOKS_PATH + "/{id}", id);
    }
}
