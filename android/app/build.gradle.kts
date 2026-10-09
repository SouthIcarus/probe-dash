plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google's public TEST AdMob app ID (spec v3 AD-3). dev and beta always use
// it; prod uses it unless release.yml passes the real ID in env ADMOB_APP_ID
// (from the play-release environment only, spec OPS-2).
val testAdmobAppId = "ca-app-pub-3940256099942544~3347511713"

fun envOrNull(name: String): String? = System.getenv(name)?.takeIf { it.isNotBlank() }

// Upload-key signing for beta/prod (environments.md §4.1). The keystore is
// decoded by CI into $RUNNER_TEMP, never into the repo. With no key (local
// builds, PRs, dry runs without the throwaway key) beta/prod fall back to
// the debug key; Play rejects that (F6) and release.yml refuses it (ENV-5).
val uploadKeystorePath = envOrNull("UPLOAD_KEYSTORE_PATH")

android {
    namespace = "com.southicarus.probe_dash"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Locked Play app ID (ENV-D1). Do not change.
        applicationId = "com.southicarus.probe_dash"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // google_mobile_ads needs Android 7.0+
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobAppId"] = testAdmobAppId
    }

    signingConfigs {
        uploadKeystorePath?.let { path ->
            create("upload") {
                storeFile = file(path)
                storePassword = envOrNull("UPLOAD_KEYSTORE_PASSWORD")
                keyAlias = envOrNull("UPLOAD_KEY_ALIAS")
                keyPassword = envOrNull("UPLOAD_KEY_PASSWORD")
            }
        }
    }
    val playSigning = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")

    // Three environments (spec v3 OPS-1, ENV-D1). The Play app ID
    // com.southicarus.probe_dash is LOCKED: it is permanent after the first
    // Play upload. dev gets its own ".dev" ID so it installs next to the Play
    // app and never shares its save or signature (ENV-7).
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["admobAppId"] = testAdmobAppId
            // Always the (CI-cached) debug key, so dev-N APKs update in place.
            signingConfig = signingConfigs.getByName("debug")
        }
        create("beta") {
            dimension = "env"
            manifestPlaceholders["admobAppId"] = testAdmobAppId // ENV-D2
            signingConfig = playSigning
        }
        create("prod") {
            dimension = "env"
            manifestPlaceholders["admobAppId"] = envOrNull("ADMOB_APP_ID") ?: testAdmobAppId
            signingConfig = playSigning
        }
    }

    buildTypes {
        release {
            // No signingConfig here on purpose: a build type's signing config
            // overrides the flavor's, and each flavor picks its own above.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
