package com.magpie.android;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Checks the project's GitHub Releases for a newer Android build.
 *
 * <p>The gateway bundled in the APK cannot replace itself, so the web page's
 * desktop updater stays out of the way on Android. This class is the app's own
 * update check: it reads the latest release from the repository, compares its
 * version with the installed APK, and hands the release (and its APK asset, if
 * one was uploaded) back to the activity, which opens it in the browser.
 */
final class UpdateChecker {

    /** The repository that publishes this Android port. */
    static final String REPO = "1527183723/magpie-android";
    static final String RELEASES_PAGE = "https://github.com/" + REPO + "/releases/latest";
    private static final String API = "https://api.github.com/repos/" + REPO + "/releases/latest";
    private static final String PREFS = "magpie-updates";
    private static final String KEY_LAST_CHECK = "lastCheck";
    private static final long AUTO_CHECK_INTERVAL_MS = 24L * 60L * 60L * 1000L;

    private static final Pattern VERSION = Pattern.compile("(\\d+)\\.(\\d+)\\.(\\d+)");

    private UpdateChecker() {
    }

    interface Callback {
        /** release is non-null when the request succeeded; error otherwise. */
        void onResult(Release release, String error);
    }

    static final class Release {
        String tag = "";
        String version = "";
        String name = "";
        String notes = "";
        String pageUrl = RELEASES_PAGE;
        String apkUrl;
        long apkSize;
        String apkName;
        boolean newer;
    }

    static boolean autoCheckDue(Context ctx) {
        long last = prefs(ctx).getLong(KEY_LAST_CHECK, 0L);
        return System.currentTimeMillis() - last >= AUTO_CHECK_INTERVAL_MS;
    }

    static void check(Context ctx, Handler handler, Callback callback) {
        final Context app = ctx.getApplicationContext();
        new Thread(() -> {
            Release release = null;
            String error = null;
            try {
                release = fetch(app);
            } catch (Exception e) {
                error = readableError(e);
            }
            prefs(app).edit().putLong(KEY_LAST_CHECK, System.currentTimeMillis()).apply();
            final Release result = release;
            final String failure = error;
            handler.post(() -> callback.onResult(result, failure));
        }, "magpie-update-check").start();
    }

    private static Release fetch(Context ctx) throws Exception {
        String userAgent = "magpie-android/" + currentVersion(ctx);
        HttpURLConnection connection = (HttpURLConnection) new URL(API).openConnection();
        connection.setConnectTimeout(10_000);
        connection.setReadTimeout(15_000);
        connection.setRequestProperty("Accept", "application/vnd.github+json");
        connection.setRequestProperty("X-GitHub-Api-Version", "2022-11-28");
        connection.setRequestProperty("User-Agent", userAgent);
        try {
            int status = connection.getResponseCode();
            InputStream stream = status >= 200 && status < 300
                    ? connection.getInputStream() : connection.getErrorStream();
            String body = readAll(stream);
            if (status == 403 || status == 429) {
                throw new IllegalStateException("GitHub API 请求次数已用完，请稍后再试");
            }
            if (status < 200 || status >= 300) {
                throw new IllegalStateException("GitHub 返回 HTTP " + status);
            }
            return parse(ctx, new JSONObject(body));
        } finally {
            connection.disconnect();
        }
    }

    private static Release parse(Context ctx, JSONObject root) throws Exception {
        Release release = new Release();
        release.tag = root.optString("tag_name", "");
        release.name = root.optString("name", release.tag);
        release.notes = root.optString("body", "");
        release.pageUrl = root.optString("html_url", RELEASES_PAGE);
        release.version = versionOf(release.tag);
        if (release.version.isEmpty()) {
            release.version = versionOf(release.name);
        }

        String abi = Build.SUPPORTED_ABIS.length > 0 ? Build.SUPPORTED_ABIS[0] : "arm64-v8a";
        String preferred = "magpie-android-" + abi + ".apk";
        String universal = "magpie-android-universal.apk";
        JSONArray assets = root.optJSONArray("assets");
        if (assets != null) {
            for (int i = 0; i < assets.length(); i++) {
                JSONObject asset = assets.optJSONObject(i);
                if (asset == null) {
                    continue;
                }
                String name = asset.optString("name", "");
                if (!name.endsWith(".apk")) {
                    continue;
                }
                boolean exact = name.equals(preferred) || name.equals(universal);
                if (release.apkUrl == null || exact) {
                    release.apkName = name;
                    release.apkUrl = asset.optString("browser_download_url", null);
                    release.apkSize = asset.optLong("size", 0L);
                    if (exact) {
                        break;
                    }
                }
            }
        }
        release.newer = isNewer(release.version, currentVersion(ctx));
        return release;
    }

    static String currentVersion(Context ctx) {
        try {
            PackageInfo info = ctx.getPackageManager().getPackageInfo(ctx.getPackageName(), 0);
            return info.versionName == null ? "" : info.versionName;
        } catch (PackageManager.NameNotFoundException e) {
            return "";
        }
    }

    private static String versionOf(String text) {
        Matcher matcher = VERSION.matcher(text == null ? "" : text);
        return matcher.find() ? matcher.group() : "";
    }

    private static boolean isNewer(String latest, String current) {
        int[] a = parts(latest);
        int[] b = parts(current);
        if (a == null || b == null) {
            return false;
        }
        for (int i = 0; i < 3; i++) {
            if (a[i] != b[i]) {
                return a[i] > b[i];
            }
        }
        return false;
    }

    private static int[] parts(String version) {
        Matcher matcher = VERSION.matcher(version == null ? "" : version);
        if (!matcher.find()) {
            return null;
        }
        return new int[]{
                Integer.parseInt(matcher.group(1)),
                Integer.parseInt(matcher.group(2)),
                Integer.parseInt(matcher.group(3)),
        };
    }

    private static String readableError(Exception e) {
        String message = e.getMessage();
        if (message == null || message.trim().isEmpty()) {
            message = e.getClass().getSimpleName();
        }
        return message;
    }

    private static String readAll(InputStream stream) throws Exception {
        if (stream == null) {
            return "";
        }
        StringBuilder out = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                out.append(line).append('\n');
            }
        }
        return out.toString();
    }

    private static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
