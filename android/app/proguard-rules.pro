# ============================================================================
# Règles ProGuard/R8 pour Alanya (mode release avec minification)
# ============================================================================
# Objectif : autoriser R8 à supprimer le code mort SANS casser les libs qui
# utilisent de la réflexion / du code natif JNI. Sans ces règles, l'app crash
# au démarrage sur des NoClassDefFoundError / ClassNotFoundException.

# --- Flutter --------------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# --- WebRTC ---------------------------------------------------------------
# libwebrtc utilise du JNI intensif. Toute méthode/champ appelé depuis C++
# doit être conservé sinon crash au premier appel.
-keep class org.webrtc.** { *; }
-keep interface org.webrtc.** { *; }
-dontwarn org.webrtc.**

# --- Firebase (Core, Messaging) -------------------------------------------
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# GSON est utilisé par media_store_plus (et souvent par Firebase).
# Sans ça, les modèles JSON perdent leurs annotations @SerializedName.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.TypeAdapterFactory

# --- Codecs audio/vidéo (audioplayers, video_player, record) --------------
-keep class androidx.media3.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn androidx.media3.**
-dontwarn com.google.android.exoplayer2.**

# --- PdfiumAndroid (flutter_pdfview) --------------------------------------
-keep class com.shockwave.** { *; }
-dontwarn com.shockwave.**

# --- SQLite / sqflite -----------------------------------------------------
-keep class io.flutter.plugins.sqflite.** { *; }

# --- Kotlin coroutines ----------------------------------------------------
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembernames class kotlinx.** { volatile <fields>; }

# --- Divers plugins Flutter ---------------------------------------------
-keep class androidx.lifecycle.DefaultLifecycleObserver
-keep class androidx.core.app.CoreComponentFactory { *; }

# Désactive les warnings sur du code Java "manquant" (souvent optionnel).
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
-dontwarn org.jetbrains.annotations.**

# Conserver les stack traces lisibles en release (facilite le débug crash).
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
