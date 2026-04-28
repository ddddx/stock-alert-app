import java.util.Properties
import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesCandidates = listOf(
    rootProject.file("key.properties"),
    file("key.properties"),
)
val keystorePropertiesFile = keystorePropertiesCandidates.firstOrNull { it.exists() }

if (keystorePropertiesFile != null) {
    keystorePropertiesFile!!.inputStream().use(keystoreProperties::load)
}

val releaseStoreFile = keystorePropertiesFile
    ?.let { propertiesFile ->
        keystoreProperties
            .getProperty("storeFile")
            ?.takeIf { it.isNotBlank() }
            ?.let { configuredPath ->
                val candidate = File(configuredPath)
                if (candidate.isAbsolute) candidate else propertiesFile.parentFile.resolve(configuredPath)
            }
    }
val hasReleaseSigning =
    releaseStoreFile?.exists() == true &&
        !keystoreProperties.getProperty("storePassword").isNullOrBlank() &&
        !keystoreProperties.getProperty("keyAlias").isNullOrBlank() &&
        !keystoreProperties.getProperty("keyPassword").isNullOrBlank()
val allowDebugReleaseSigning = providers
    .gradleProperty("ALLOW_DEBUG_RELEASE_SIGNING")
    .map { it.equals("true", ignoreCase = true) }
    .orElse(false)
    .get()

if (!hasReleaseSigning && !allowDebugReleaseSigning) {
    throw GradleException(
        "Release signing is required. Configure key.properties or pass -PALLOW_DEBUG_RELEASE_SIGNING=true for internal-only local builds.",
    )
}

android {
    namespace = "com.stockpulse.radar"
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
        applicationId = "com.stockpulse.radar"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
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
