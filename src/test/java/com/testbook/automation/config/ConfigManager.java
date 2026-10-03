package com.testbook.automation.config;

import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;

public final class ConfigManager {
    private static final String BASE_URL_PROPERTY = "base.url";
    private static final String BASE_URL_ENVIRONMENT_VARIABLE = "BASE_URL";
    private static final Properties PROPERTIES = loadProperties();

    private ConfigManager() {
    }

    public static String getBaseUrl() {
        String baseUrl = firstNonBlank(
                System.getProperty(BASE_URL_PROPERTY),
                System.getenv(BASE_URL_ENVIRONMENT_VARIABLE),
                PROPERTIES.getProperty(BASE_URL_PROPERTY));

        if (baseUrl == null) {
            throw new IllegalStateException("No base URL configured; set -Dbase.url, BASE_URL, or config.properties.");
        }

        return baseUrl;
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value.trim();
            }
        }
        return null;
    }

    private static Properties loadProperties() {
        Properties properties = new Properties();
        try (InputStream input = ConfigManager.class.getClassLoader().getResourceAsStream("config.properties")) {
            if (input == null) {
                throw new IllegalStateException("Required config.properties resource was not found.");
            }
            properties.load(input);
            return properties;
        } catch (IOException exception) {
            throw new IllegalStateException("Unable to load config.properties.", exception);
        }
    }
}
