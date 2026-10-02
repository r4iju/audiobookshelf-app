package com.audiobookshelf.android.journeys;

import android.app.Activity;
import android.content.ComponentName;
import android.media.browse.MediaBrowser;
import android.os.Bundle;
import android.widget.TextView;

/**
 * An app that is neither a car nor an assistant trying to browse the library, from the test package's
 * own process and user id. It shows whether the media service let it in.
 */
public class ForeignBrowserActivity extends Activity {
    private MediaBrowser browser;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView view = new TextView(this);
        view.setText("connecting");
        setContentView(view);
        ComponentName service = new ComponentName("com.audiobookshelf.app.nativepreview", "com.audiobookshelf.android.playback.PlaybackService");
        browser = new MediaBrowser(this, service, new MediaBrowser.ConnectionCallback() {
            @Override
            public void onConnected() {
                view.setText("browse allowed " + browser.getRoot());
            }

            @Override
            public void onConnectionFailed() {
                view.setText("browse refused");
            }
        }, null);
        browser.connect();
    }

    @Override
    protected void onDestroy() {
        browser.disconnect();
        super.onDestroy();
    }
}
