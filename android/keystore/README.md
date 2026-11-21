# Android signing key

`magpie-release.jks` is the project's public, reproducible signing key for the
direct-download APKs. It is intentionally committed so every build produced by
GitHub Actions and by contributors has the same signature, and an update can be
installed over the previous version.

- alias: `magpie`
- store/key password: `magpieandroid`
- certificate: RSA 4096, valid for 12000 days

This key is **not** suitable for Google Play: anyone can read it and sign an
APK with the same application ID. For a store build, generate your own key and
set `MAGPIE_KEYSTORE_PASSWORD`, `MAGPIE_KEY_ALIAS` and `MAGPIE_KEY_PASSWORD`;
`android/app/build.gradle.kts` reads those environment variables first.
