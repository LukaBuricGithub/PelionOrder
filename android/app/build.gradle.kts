import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (never in git) holds the passwords
// and the path to the upload keystore. Without that file the release build
// falls back to the debug key, so `flutter run --release` still works.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    // Read as UTF-8 (Properties.load defaults to ISO-8859-1, which mangles a
    // password containing č, ć, š, ž, đ …).
    if (f.exists()) f.reader(Charsets.UTF_8).use { load(it) }
}

// Trimmed: a trailing space in key.properties would otherwise be part of the
// password, and the build would fail with "password was incorrect".
fun keyProp(name: String): String? =
    keystoreProperties.getProperty(name)?.trim()?.takeIf { it.isNotEmpty() }

val hasUploadKey = keyProp("storeFile") != null

android {
    namespace = "hr.pelion.order"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Identifies the app on Google Play for ever — it can never change.
        applicationId = "hr.pelion.order"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                keyAlias = keyProp("keyAlias")
                keyPassword = keyProp("keyPassword")
                storeFile = file(keyProp("storeFile")!!)
                storePassword = keyProp("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
