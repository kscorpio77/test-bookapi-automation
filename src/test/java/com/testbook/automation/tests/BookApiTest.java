package com.testbook.automation.tests;

import com.testbook.automation.base.BaseTest;
import com.testbook.automation.model.Book;
import io.restassured.response.Response;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class BookApiTest extends BaseTest {

    @Test
    void homeReturnsApiInformation() {
        Response response = bookApiClient.getHome();

        response.then().statusCode(200);
        assertThat(response.asString())
                .isEqualTo("Spring Boot REST API is running. Use /api/books");
        assertThat(response.getContentType()).startsWith("text/plain");
    }

    @Test
    void getAllBooksReturnsAJsonArray() {
        Response response = bookApiClient.getAllBooks();

        response.then()
                .statusCode(200)
                .spec(jsonResponseSpecification);
        List<Book> books = response.jsonPath().getList("$", Book.class);
        assertThat(books).isNotNull();
    }

    @Test
    void createBookReturnsSavedBook() {
        Long bookId = null;
        try {
            Response response = bookApiClient.createBook(newBook("Created Book", 18.75));

            response.then()
                    .statusCode(200)
                    .spec(jsonResponseSpecification);
            Book createdBook = response.as(Book.class);
            bookId = createdBook.getId();

            assertThat(bookId).isNotNull();
            assertThat(createdBook.getTitle()).isEqualTo("Created Book");
            assertThat(createdBook.getAuthor()).isEqualTo("Automation Author");
            assertThat(createdBook.getPrice()).isEqualTo(18.75);
        } finally {
            deleteIfCreated(bookId);
        }
    }

    @Test
    void createBookRejectsNonPositivePrice() {
        Response response = bookApiClient.createBook(newBook("Invalid Book", 0.0));

        response.then()
                .statusCode(400)
                .spec(jsonResponseSpecification);
        assertThat(response.jsonPath().getString("message")).isEqualTo("Validation failed");
        assertThat(response.jsonPath().getMap("errors"))
                .containsEntry("price", "price must be greater than 0");
    }

    @Test
    void endToEndCrudLifecycleUsesGeneratedId() {
        Long bookId = null;
        boolean deleteCompleted = false;
        try {
            Response createResponse = bookApiClient.createBook(newBook("Lifecycle Book", 25.50));
            createResponse.then()
                    .statusCode(200)
                    .spec(jsonResponseSpecification);
            Book createdBook = createResponse.as(Book.class);
            bookId = createdBook.getId();

            assertThat(bookId).isNotNull();

            Response getResponse = bookApiClient.getBookById(bookId);
            getResponse.then()
                    .statusCode(200)
                    .spec(jsonResponseSpecification);
            assertBook(getResponse.as(Book.class), bookId, "Lifecycle Book", "Automation Author", 25.50);

            Response updateResponse = bookApiClient.updateBook(
                    bookId, newBook("Updated Lifecycle Book", 31.25));
            updateResponse.then()
                    .statusCode(200)
                    .spec(jsonResponseSpecification);
            assertBook(updateResponse.as(Book.class), bookId,
                    "Updated Lifecycle Book", "Automation Author", 31.25);

            Response updatedGetResponse = bookApiClient.getBookById(bookId);
            updatedGetResponse.then()
                    .statusCode(200)
                    .spec(jsonResponseSpecification);
            assertBook(updatedGetResponse.as(Book.class), bookId,
                    "Updated Lifecycle Book", "Automation Author", 31.25);

            Response deleteResponse = bookApiClient.deleteBook(bookId);
            deleteResponse.then().statusCode(204);
            deleteCompleted = true;

            Response missingResponse = bookApiClient.getBookById(bookId);
            missingResponse.then().statusCode(404);
            assertThat(missingResponse.asString()).isEmpty();
        } finally {
            if (bookId != null && !deleteCompleted) {
                deleteIfCreated(bookId);
            }
        }
    }

    @Test
    void updateBookRejectsNonPositivePrice() {
        Long bookId = createBookAndReturnId("Update Validation Book", 12.0);
        try {
            Response response = bookApiClient.updateBook(bookId, newBook("Invalid Update", -1.0));

            response.then()
                    .statusCode(400)
                    .spec(jsonResponseSpecification);
            assertThat(response.jsonPath().getString("message")).isEqualTo("Validation failed");
            assertThat(response.jsonPath().getMap("errors"))
                    .containsEntry("price", "price must be greater than 0");
        } finally {
            deleteIfCreated(bookId);
        }
    }

    @Test
    void updateBookReturnsNotFoundForMissingId() {
        Long bookId = createBookAndReturnId("Missing Update Book", 14.0);
        bookApiClient.deleteBook(bookId).then().statusCode(204);

        Response response = bookApiClient.updateBook(bookId, newBook("Updated Missing Book", 15.0));

        response.then().statusCode(404);
        bookApiClient.deleteBook(bookId).then().statusCode(204);
    }

    @Test
    void deleteReturnsNoContentAndMissingBookLookupReturnsNotFound() {
        Long bookId = createBookAndReturnId("Delete Book", 9.99);
        boolean deleteCompleted = false;
        try {
            Response deleteResponse = bookApiClient.deleteBook(bookId);
            deleteResponse.then().statusCode(204);
            deleteCompleted = true;

            Response missingResponse = bookApiClient.getBookById(bookId);
            missingResponse.then().statusCode(404);
            assertThat(missingResponse.asString()).isEmpty();

            bookApiClient.deleteBook(bookId).then().statusCode(204);
        } finally {
            if (!deleteCompleted) {
                deleteIfCreated(bookId);
            }
        }
    }

    private Long createBookAndReturnId(String title, double price) {
        Response response = bookApiClient.createBook(newBook(title, price));
        response.then()
                .statusCode(200)
                .spec(jsonResponseSpecification);
        Long id = response.as(Book.class).getId();
        assertThat(id).isNotNull();
        return id;
    }

    private void deleteIfCreated(Long bookId) {
        if (bookId != null) {
            bookApiClient.deleteBook(bookId).then().statusCode(204);
        }
    }

    private Book newBook(String title, double price) {
        return new Book(title, "Automation Author", price);
    }

    private void assertBook(Book actual, Long expectedId, String title, String author, double price) {
        assertThat(actual.getId()).isEqualTo(expectedId);
        assertThat(actual.getTitle()).isEqualTo(title);
        assertThat(actual.getAuthor()).isEqualTo(author);
        assertThat(actual.getPrice()).isEqualTo(price);
    }
}
