plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.slopcafe.slopcafe_ui"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.slopcafe.slopcafe_ui"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The public web host whose /d/ and /s/ links this build claims as
        // Android App Links, substituted into the VIEW intent-filter in
        // AndroidManifest.xml. Adopters running the platform on their own
        // domain change it here.
        //
        // Keep this identical to `kDeepLinkHost` in lib/core/deep_link.dart —
        // the manifest decides whether the app is *offered* the tap and the
        // Dart constant decides whether it *accepts* it, so a mismatch is an
        // app that opens to nothing. test/deep_link_test.dart reads this line
        // back and fails on drift.
        //
        // Changing the host also means publishing a new assetlinks.json under
        // it; without one, Android hands the link to a browser instead. See
        // docs/deep-links.md.
        manifestPlaceholders["deepLinkHost"] = "slopcafe.com"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
