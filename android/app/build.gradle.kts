// android/app/build.gradle.kts

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")         // umjesto "kotlin-android"
    id("com.google.gms.google-services")       // Firebase
    id("dev.flutter.flutter-gradle-plugin")    // Flutter plugin (mora nakon Android/Kotlin)
}

android {
    namespace = "com.example.flutter_fms"      // <-- promijeni po potrebi
    compileSdk = 34

    // OVO TI NE TREBA osim ako baš moraš fiksirati NDK zbog nekog plugina:
    // ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.example.flutter_fms"   // <-- promijeni po potrebi
        minSdk = 21
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Stavi svoj release keystore ako ga imaš:
            // signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // po želji
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
}
