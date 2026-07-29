package ru.brikster.chatty.repository.player;

import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

class IsolatedSqliteDriverTest {

    private final Path dataFolder = Path.of("build", "tmp", "sqlite-driver-reload-test");

    @Test
    void reusesContentAddressedDriverJarWhenReopening() throws Exception {
        String jdbcUrl = "jdbc:sqlite:" + dataFolder.resolve("database.sqlite");

        openAndClose(jdbcUrl);
        openAndClose(jdbcUrl);

        try (var files = Files.list(dataFolder.resolve("lib"))) {
            assertEquals(1, files.filter(path -> path.getFileName().toString().endsWith(".jar")).count());
        }
    }

    private void openAndClose(String jdbcUrl) throws Exception {
        try (IsolatedSqliteDriver.LoadedDataSource loadedDriver =
                     IsolatedSqliteDriver.createDataSource(dataFolder, jdbcUrl);
             Connection connection = loadedDriver.dataSource().getConnection()) {
            assertFalse(connection.isClosed());
        }
    }
}
