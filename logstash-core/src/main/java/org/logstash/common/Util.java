package org.logstash.common;

import java.io.BufferedWriter;
import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.SeekableByteChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.OpenOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * Created by andrewvc on 12/23/16.
 */
public class Util {
    // Modified from http://stackoverflow.com/a/11009612/11105

    public static MessageDigest defaultMessageDigest() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException(e);
        }
    }

    public static String digest(String base) {
        MessageDigest digest = defaultMessageDigest();
        byte[] hash = digest.digest(base.getBytes(StandardCharsets.UTF_8));
        return bytesToHexString(hash);
    }

    public static String bytesToHexString(byte[] bytes) {
        StringBuilder hexString = new StringBuilder();

        for (byte aHash : bytes) {
            String hex = Integer.toHexString(0xff & aHash);
            if (hex.length() == 1) hexString.append('0');
            hexString.append(hex);
        }

        return hexString.toString();
    }

    /**
     * Unzips a ZipInputStream to a given directory
     * @param input the ZipInputStream
     * @param output path to the output
     * @param omitParentDir omit the parent dir the zip is packaged with
     * @throws IOException
     */
    public static void unzipToDirectory(final ZipInputStream input, final Path output, boolean omitParentDir) throws IOException {
        ZipEntry entry;
        final int bufSize = 4096;
        byte[] buffer = new byte[bufSize];
        while ((entry = input.getNextEntry()) != null) {
            // Skip the top level dir
            final String destinationPath = omitParentDir ?
                    entry.getName().replaceFirst("[^/]+/", "") :
                    entry.getName();

            final Path fullPath = Paths.get(output.toString(), destinationPath);
            // Create parent directories as required
            if (entry.isDirectory()) {
                Files.createDirectories(fullPath);
            } else {
                Files.createDirectories(fullPath.getParent());

                int readLength;
                try (SeekableByteChannel outputWriter = Files.newByteChannel(fullPath, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
                    while ((readLength = input.read(buffer, 0, bufSize)) != -1) {
                        outputWriter.write(ByteBuffer.wrap(buffer, 0, readLength));
                    }
                }
            }
        }
    }
}
