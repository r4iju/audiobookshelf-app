package com.audiobookshelf.android.journeys;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

/**
 * Serves exports the way a file manager does when the user opens one with the app: a content URI of
 * unknown type. "legacy-export" is the archive the legacy app's own exporter wrote; "corrupt" is that
 * archive with one byte of its PDF changed; "not-an-export" is any other file. Java, because this runs
 * in the test package's own process without the app's Kotlin runtime.
 */
public class ArchiveProvider extends ContentProvider {
    public static final String AUTHORITY = "com.audiobookshelf.journeys.archives";

    @Override public boolean onCreate() { return true; }

    private File file(Uri uri) throws IOException {
        String name = uri.getLastPathSegment();
        File target = new File(getContext().getCacheDir(), name);
        if (target.exists()) return target;
        try (InputStream source = getContext().getAssets().open("legacy-export.absmigration"); OutputStream out = new FileOutputStream(target)) {
            switch (name) {
                case "legacy-export.absmigration": copy(source, out); break;
                case "corrupt.absmigration": corrupt(source, out); break;
                case "not-an-export.absmigration": out.write("These are notes, not an export.".getBytes()); break;
                default: throw new FileNotFoundException(name);
            }
        }
        return target;
    }

    private static void corrupt(InputStream source, OutputStream out) throws IOException {
        try (ZipInputStream zip = new ZipInputStream(source); ZipOutputStream rewritten = new ZipOutputStream(out)) {
            for (ZipEntry entry; (entry = zip.getNextEntry()) != null; ) {
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                copy(zip, bytes);
                byte[] data = bytes.toByteArray();
                if (entry.getName().endsWith(".pdf")) data[100]++;
                rewritten.putNextEntry(new ZipEntry(entry.getName()));
                rewritten.write(data);
                rewritten.closeEntry();
            }
        }
    }

    private static void copy(InputStream in, OutputStream out) throws IOException {
        byte[] buffer = new byte[1 << 16];
        for (int read; (read = in.read(buffer)) >= 0; ) out.write(buffer, 0, read);
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        try {
            return ParcelFileDescriptor.open(file(uri), ParcelFileDescriptor.MODE_READ_ONLY);
        } catch (IOException failure) {
            throw new FileNotFoundException(failure.getMessage());
        }
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        MatrixCursor cursor = new MatrixCursor(new String[] { OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE });
        try {
            cursor.addRow(new Object[] { uri.getLastPathSegment(), file(uri).length() });
        } catch (IOException ignored) {}
        return cursor;
    }

    @Override public String getType(Uri uri) { return "application/octet-stream"; }
    @Override public Uri insert(Uri uri, ContentValues values) { return null; }
    @Override public int delete(Uri uri, String selection, String[] selectionArgs) { return 0; }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) { return 0; }
}
