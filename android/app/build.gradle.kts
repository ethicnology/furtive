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

    // Only on aarch64 Linux hosts. Flutter injects a dummy CMakeLists whose sole
    // purpose is to make AGP download the NDK (it needs it to strip debug
    // symbols). CMake then runs its compiler sanity check with the NDK's
    // x86_64 clang++, which an arm64 host cannot execute — Rosetta reports
    // "Failed to map AOT header: 22" and every APK build fails, debug included.
    // No NDK ships an aarch64-linux toolchain.
    //
    // Declaring our own CMake project makes Flutter skip its injection
    // (forceNdkDownload returns early when cmake.path is already set), and ours
    // sets CMAKE_CXX_COMPILER_WORKS so the check never runs. Nothing is compiled
    // either way.
    //
    // Gated on the host so x86_64 machines — CI, and the container that produces
    // release artifacts — keep Flutter's stock behaviour untouched. That matters:
    // skipping the NDK download there could change symbol stripping and break
    // `make verify-reproducible`.
    val isArm64LinuxHost =
        System.getProperty("os.name") == "Linux" &&
            System.getProperty("os.arch") == "aarch64"
    if (isArm64LinuxHost) {
        externalNativeBuild {
            cmake {
                path = file("src/main/cpp/CMakeLists.txt")
            }
        }
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

    // maplibre_android declares `org.maplibre.gl:android-sdk-opengl:13.0.+`.
    // A Gradle dynamic version is resolved when you build, not when you commit,
    // and `+` does not exclude pre-releases: today it lands on 13.0.3-pre0. Two
    // builds of the same commit on different days can therefore produce
    // different APKs, which is precisely what `make verify-reproducible` exists
    // to rule out — and it would NOT catch it, because it builds twice in one
    // session and resolves the same version both times. A third party verifying
    // months later would get a different hash.
    //
    // Pinned to the highest STABLE release inside the range upstream declares.
    // Revisit deliberately, together with a fresh verify-reproducible run, and
    // re-check after any `flutter pub upgrade` that moves maplibre_android.
    resolutionStrategy.force("org.maplibre.gl:android-sdk-opengl:13.0.2")
}
