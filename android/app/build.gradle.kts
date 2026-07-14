plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    // Plugin Firebase Google Services (pour les notifications push FCM)
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.sewachat"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        applicationId = "com.example.sewachat"
        minSdk = 21
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // FIX taille APK :
            //  - isMinifyEnabled = true → active R8, retire le code Kotlin/Java
            //    mort (Firebase, WebRTC, plugins non utilisés). Gain ~15-25 Mo.
            //  - isShrinkResources = true → retire les ressources natives (.so,
            //    drawables, strings) inutilisées. Gain ~5-10 Mo.
            //  Ensemble = APK ~50-60 Mo au lieu de ~100 Mo.
            //  Combiné avec --split-per-abi (codemagic.yaml) = ~25-35 Mo par ABI.
            isMinifyEnabled = true
            isShrinkResources = true
            // Règles proguard/R8 : la version par défaut de Flutter suffit pour
            // toutes les libs standards. On ajoute nos règles perso si besoin.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Requis par flutter_local_notifications (core library desugaring)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
