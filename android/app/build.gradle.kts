plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val androidMinSdk = (project.properties["android.minSdk"] as String).toInt()
val androidCompileSdk = (project.properties["android.compileSdk"] as String).toInt()
val androidTargetSdk = (project.properties["android.targetSdk"] as String).toInt()
val androidNdkVersion = project.properties["android.ndkVersion"] as String
val androidJvmTarget = JavaVersion.toVersion(project.properties["android.jvmTarget"] as String)

android {
    namespace = "com.ethicnology.furtive"
    compileSdk = androidCompileSdk
    ndkVersion = androidNdkVersion

    compileOptions {
        sourceCompatibility = androidJvmTarget
        targetCompatibility = androidJvmTarget
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = androidJvmTarget.toString()
    }

    defaultConfig {
        applicationId = "com.ethicnology.furtive"
        minSdk = androidMinSdk
        targetSdk = androidTargetSdk
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Both deliberately off, and this is the only unexplained choice
            // that used to be in this file.
            //
            // R8 is deterministic, so minification would not by itself break
            // `make verify-reproducible`. It is off because it buys nothing this
            // project wants and costs something it does: obfuscation is not a
            // security property for a FOSS app whose source anyone can read, and
            // an unminified APK is far easier for a third party to audit against
            // this repository — which is the whole point of the reproducible
            // build. The cost is a larger APK, accepted knowingly.
            isShrinkResources = false
            isMinifyEnabled = false
            // Release artifacts are produced UNSIGNED and signed out-of-band
            // with apksigner/zipalign. Keystores never enter this repository —
            // do not add a key.properties or wire signing in here. See README.
            signingConfig = null
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

configurations.all {
    exclude(group = "com.google.android.gms")
}
