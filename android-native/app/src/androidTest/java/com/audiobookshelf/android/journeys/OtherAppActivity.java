package com.audiobookshelf.android.journeys;

import android.app.Activity;
import android.net.Uri;
import android.os.Bundle;
import android.widget.TextView;

import java.io.InputStream;
import java.io.OutputStream;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;

/**
 * Another app receiving an opened download. It runs in the test package's own process and user id,
 * so it reads only what the preview app explicitly granted, and shows what it could do for UiAutomator.
 * Java, because that process has the test APK alone, without the Kotlin runtime the app provides.
 */
public class OtherAppActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Uri uri = getIntent().getData();
        StringBuilder report = new StringBuilder();
        try (InputStream input = getContentResolver().openInputStream(uri)) {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[64 * 1024];
            long size = 0;
            for (int read; (read = input.read(buffer)) >= 0; size += read) digest.update(buffer, 0, read);
            StringBuilder hex = new StringBuilder();
            for (byte b : digest.digest()) hex.append(String.format("%02x", b));
            report.append("read ").append(size).append(" sha ").append(hex);
        } catch (Exception failure) {
            report.append("read refused ").append(failure.getClass().getSimpleName());
        }
        boolean wrote;
        try (OutputStream output = getContentResolver().openOutputStream(uri, "wa")) {
            wrote = true;
        } catch (Exception refused) {
            wrote = false;
        }
        report.append(wrote ? "\nwrite allowed" : "\nwrite refused");
        // Guesses at neighbouring files: anything readable here was exposed without being opened.
        List<String> segments = uri.getPathSegments();
        String folder = String.join("/", segments.subList(0, segments.size() - 1));
        List<String> readable = new ArrayList<>();
        for (String path : new String[] {folder + "/track-1.wav", folder + "/cover.jpg", folder + "/../../listening-journal.json", "downloads.json"}) {
            Uri other = new Uri.Builder().scheme("content").authority(uri.getAuthority()).path(path).build();
            try (InputStream ignored = getContentResolver().openInputStream(other)) {
                readable.add(other.toString());
            } catch (Exception refused) {
                // Refused, as it should be.
            }
        }
        report.append(readable.isEmpty() ? "\nothers refused" : "\nothers readable " + readable);
        TextView view = new TextView(this);
        view.setText(report);
        setContentView(view);
    }
}
