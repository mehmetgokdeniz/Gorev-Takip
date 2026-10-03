# ============================================================
#  R8 / PROGUARD KURALLARI
# ============================================================
#
#  Flutter eklentilerinin reflection ve native kodla baglantili
#  kisimlari korunur. Aksi halde release build'de plugin'ler
#  calisma zamani hata verir.
# ============================================================

# Flutter Framework
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.firebase.**$* { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Firestore / DTO alanlari reflection ile okunabilir.
-keepclassmembers class * {
    @com.google.firebase.firestore.IgnoreExtraProperties <fields>;
}
-keep class com.google.firestore.** { *; }
-keepclassmembers class * {
    @androidx.annotation.NonNull <fields>;
}

# Geolocator
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# Image Picker
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**

# Local Auth (biyometrik)
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**

# URL Launcher
-keep class androidx.browser.customtabs.** { *; }
-dontwarn androidx.browser.customtabs.**

# Ortak AndroidX / Kotlin
-keep class androidx.** { *; }
-dontwarn androidx.**
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# Vertex: R8 uyarilarini bastirir
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn javax.annotation.concurrent.**
-dontwarn org.codehaus.mojo.animal_sniffer.**

# Enum degerlerini koru (isimler loglarda/analizde kullaniliyor)
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Line number ve kaynak dosya bilgisini koru (crash raporlari icin),
# ancak dosya adini gizle.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile