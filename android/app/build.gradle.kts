// Import explicite : dans un script Gradle Kotlin, `java` désigne l'extension
// Gradle du même nom, pas le paquet Java. Écrire `java.util.Properties` ne
// compile donc pas.
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    // Plugin Firebase Google Services (pour les notifications push FCM)
    id("com.google.gms.google-services")
}

// Clé de signature de la version publiée.
//
// ⚠️ POURQUOI CE FICHIER EXISTE. Le bloc `release` signait avec la clé DEBUG.
// Or cette clé est générée automatiquement par le SDK Android sur chaque
// machine, et un runner CI est détruit après le build : il en fabrique une
// NOUVELLE à chaque fois. Chaque APK portait donc une signature différente, et
// Android refuse d'installer une mise à jour dont la signature ne correspond
// pas à celle installée — d'où l'obligation de désinstaller avant chaque essai.
//
// Le fichier n'est pas versionné (il contient un mot de passe). Sans lui, le
// build retombe sur la clé debug : rien ne casse, on retrouve simplement
// l'ancien comportement.
val fichierCle = rootProject.file("key.properties")
val proprietesCle = Properties().apply {
    if (fichierCle.exists()) fichierCle.inputStream().use { load(it) }
}
val signatureDisponible = proprietesCle.getProperty("storeFile") != null

android {
    namespace = "com.alanya237.work"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    signingConfigs {
        if (signatureDisponible) {
            create("release") {
                storeFile = file(proprietesCle.getProperty("storeFile"))
                storePassword = proprietesCle.getProperty("storePassword")
                keyAlias = proprietesCle.getProperty("keyAlias")
                keyPassword = proprietesCle.getProperty("keyPassword")
            }
        }
    }

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
        applicationId = "com.alanya237.work"
        // 21 (Android 5.0) et NON flutter.minSdkVersion, qui vaut 24 sur
        // Flutter 3.44. Le public d'Alanya comprend beaucoup d'appareils
        // anciens : passer à 24 exclurait Android 5.0, 5.1 et 6.0 sans rien
        // apporter en échange. Choix délibéré, à ne pas « corriger ».
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        // Numéro de build de la CI quand il existe, celui du pubspec sinon.
        //
        // `flutter.versionCode` vaut le « +1 » de `version: 0.1.0+1` : il ne
        // change JAMAIS d'un build à l'autre. Android voit alors toujours la
        // même version et n'a aucune raison de proposer une mise à jour. Le
        // numéro de build, lui, s'incrémente tout seul à chaque exécution.
        versionCode = (System.getenv("BUILD_NUMBER")            // Codemagic
                ?: System.getenv("PROJECT_BUILD_NUMBER")        // Codemagic (autre nom)
                ?: System.getenv("GITHUB_RUN_NUMBER"))          // GitHub Actions
            ?.toIntOrNull()
            ?: flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Clé stable si elle est fournie, clé debug sinon. Le repli garde
            // le build fonctionnel sans configuration, au prix du conflit
            // d'installation décrit plus haut.
            signingConfig = if (signatureDisponible) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

    // ⚠️ MÊME ARTEFACT ET MÊME VERSION que ceux de `flutter_webrtc`
    // (android/build.gradle : io.github.webrtc-sdk:android:125.6422.03).
    //
    // POURQUOI LE REDÉCLARER. `AppelEnregistreur.kt` enregistre les appels en
    // branchant un `org.webrtc.AudioTrackSink` sur les pistes audio. Or
    // `flutter_webrtc` déclare le SDK WebRTC en `implementation` : ses classes
    // `org.webrtc.*` ne sont donc PAS exposées transitivement à ce module, et le
    // code ne compilerait pas. On rajoute la dépendance ici — Gradle résout une
    // seule et même copie (versions identiques), sans conflit de classes.
    // Les classes du greffon lui-même (`com.cloudwebrtc.webrtc.*`) restent
    // visibles sans rien ajouter : ce sont ses classes propres, pas une
    // dépendance transitive.
    implementation("io.github.webrtc-sdk:android:125.6422.03")
}
