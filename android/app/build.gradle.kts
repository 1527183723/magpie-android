import java.util.Properties

plugins {
    id("com.android.application")
}

val versionProps = Properties().apply {
    rootProject.file("version.properties").inputStream().use { load(it) }
}
val abiList = (providers.gradleProperty("abis").orNull ?: "arm64-v8a,x86_64")
    .split(",").map { it.trim() }.filter { it.isNotEmpty() }

android {
    namespace = "com.magpie.android"
    compileSdk = 37
    // Android 17 QPR2: platform/android-37.2
    compileSdkMinor = 2

    defaultConfig {
        applicationId = "com.magpie.android"
        minSdk = 36
        targetSdk = 37
        versionCode = versionProps.getProperty("versionCode").toInt()
        versionName = versionProps.getProperty("versionName")
        // The Go gateway is built by scripts/build-magpie-android.sh into
        // src/main/jniLibs/<abi>/libmagpie.so; Gradle only packages it. The
        // NDK is used by that script and not by this build.
        ndk {
            abiFilters += abiList
        }
    }

    signingConfigs {
        create("release") {
            // The public project key makes every CI build installable over
            // the previous release. Override it with environment variables
            // for a private/store build.
            storeFile = rootProject.file("keystore/magpie-release.jks")
            storePassword = System.getenv("MAGPIE_KEYSTORE_PASSWORD") ?: "magpieandroid"
            keyAlias = System.getenv("MAGPIE_KEY_ALIAS") ?: "magpie"
            keyPassword = System.getenv("MAGPIE_KEY_PASSWORD") ?: "magpieandroid"
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs {
            // The gateway is exec'd from the app's native library directory,
            // so the libraries must be extracted onto disk.
            useLegacyPackaging = true
            // Bun is carried the same way (jniLibs/<abi>/libmagpiebun.so) and
            // is exec'd from there too: AGP must not strip it.
            keepDebugSymbols += "**/libmagpiebun.so"
        }
    }

    androidResources {
        // No need to compress the big binary further; keeps extraction quick.
        noCompress += "so"
    }
}
