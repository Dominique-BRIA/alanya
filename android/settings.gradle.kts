pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localPropertiesFile = file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { properties.load(it) }
        }
        properties.getProperty("flutter.sdk")
            ?: System.getenv("FLUTTER_ROOT")
            ?: System.getenv("FCI_FLUTTER_SDK")
            ?: "/Users/builder/programs/flutter"
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// Versions relevées sur les avertissements de `flutter build`, qui réclamait au
// moins Gradle 8.14, AGP 8.11.1 et Kotlin 2.2.20. Ce sont exactement ces
// minimums qui sont posés ici, et pas les dernières versions disponibles :
// chaque cran supplémentaire ajoute du risque sans lever d'avertissement de
// plus.
//
// ⚠️ CHAQUE VERSION A ÉTÉ VÉRIFIÉE COMME TÉLÉCHARGEABLE avant d'être écrite.
// La tentative précédente avait échoué sur un `FileNotFoundException` en
// demandant « gradle-8.14.0 », qui n'existe pas : Gradle nomme cette version
// « 8.14 » tout court. Une version plausible n'est pas une version publiée.
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // Plugin Google Services requis pour Firebase (notifications push FCM)
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
