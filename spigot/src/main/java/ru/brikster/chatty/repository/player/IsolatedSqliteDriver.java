package ru.brikster.chatty.repository.player;

import org.jetbrains.annotations.NotNull;

import javax.sql.DataSource;
import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.util.HexFormat;

/**
 * Loads the bundled SQLite JDBC driver through a dedicated classloader that is
 * isolated from the server.
 *
 * <p>The driver cannot be used the usual way for two reasons:
 * <ul>
 *   <li>Chatty must not rely on the {@code org.sqlite} the server provides —
 *       legacy servers (e.g. 1.8.x) ship an ancient, non-JDBC4 build that
 *       breaks HikariCP with an {@code AbstractMethodError}.</li>
 *   <li>The driver cannot be shaded/relocated into the plugin jar either: its
 *       native library has the original {@code org/sqlite/...} class paths
 *       compiled into the binary, which a relocation cannot rewrite.</li>
 * </ul>
 *
 * <p>So the modern driver is shipped as a nested jar ({@value #BUNDLED_JAR}) and
 * loaded here with the platform classloader as parent — it sees the JDK (and
 * the JDBC interfaces) but neither the server's {@code org.sqlite} nor the
 * plugin's classes. HikariCP and the rest of Chatty only ever touch the driver
 * through the shared {@code java.sql}/{@code javax.sql} interfaces.
 */
final class IsolatedSqliteDriver {

    // Embedded with a non-".jar" extension so the shadowJar build step does not
    // unzip it; see the embedSqliteDriver task in spigot/build.gradle.
    private static final String BUNDLED_JAR = "/lib/sqlite-jdbc.jardata";

    private IsolatedSqliteDriver() {
    }

    /**
     * Extracts the bundled driver and returns a {@link DataSource} backed by it.
     *
     * @param dataFolder the plugin data folder (the driver jar is extracted into
     *                   {@code <dataFolder>/lib})
     * @param jdbcUrl    the {@code jdbc:sqlite:...} URL of the database
     */
    static @NotNull LoadedDataSource createDataSource(@NotNull Path dataFolder, @NotNull String jdbcUrl) {
        URLClassLoader driverLoader = null;
        try {
            byte[] bundledBytes;
            try (InputStream bundled = IsolatedSqliteDriver.class.getResourceAsStream(BUNDLED_JAR)) {
                if (bundled == null) {
                    throw new IllegalStateException("Bundled SQLite driver " + BUNDLED_JAR + " is missing from the plugin jar");
                }
                bundledBytes = bundled.readAllBytes();
            }

            String fingerprint = HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(bundledBytes), 0, 8);
            Path driverJar = dataFolder.resolve("lib").resolve("sqlite-jdbc-" + fingerprint + ".jar");
            Files.createDirectories(driverJar.getParent());

            if (Files.notExists(driverJar)) {
                try {
                    Files.write(driverJar, bundledBytes, StandardOpenOption.CREATE_NEW);
                } catch (FileAlreadyExistsException ignored) {
                    // Another concurrent initialization wrote the same content.
                }
            }

            // Parent = platform classloader: the JDK and the java.sql interfaces,
            // but not the server classpath. The repository closes this loader
            // after Hikari has closed all pooled connections.
            driverLoader = new URLClassLoader(
                    new URL[]{driverJar.toUri().toURL()},
                    ClassLoader.getPlatformClassLoader());

            Class<?> dataSourceClass = driverLoader.loadClass("org.sqlite.SQLiteDataSource");
            DataSource dataSource = (DataSource) dataSourceClass.getDeclaredConstructor().newInstance();
            dataSourceClass.getMethod("setUrl", String.class).invoke(dataSource, jdbcUrl);
            return new LoadedDataSource(dataSource, driverLoader);
        } catch (Exception e) {
            if (driverLoader != null) {
                try {
                    driverLoader.close();
                } catch (IOException closeException) {
                    e.addSuppressed(closeException);
                }
            }
            throw new IllegalStateException("Cannot initialize the bundled SQLite driver", e);
        }
    }

    static final class LoadedDataSource implements Closeable {

        private final DataSource dataSource;
        private final URLClassLoader driverLoader;

        private LoadedDataSource(DataSource dataSource, URLClassLoader driverLoader) {
            this.dataSource = dataSource;
            this.driverLoader = driverLoader;
        }

        DataSource dataSource() {
            return dataSource;
        }

        @Override
        public void close() throws IOException {
            driverLoader.close();
        }
    }

}
