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
    namespace = "com.example.furtive"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.furtive"
        minSdk = androidMinSdk
        targetSdk = androidTargetSdk
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            isShrinkResources = false
            isMinifyEnabled = false
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
