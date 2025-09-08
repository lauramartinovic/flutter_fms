## -----------------------------
## General settings / keep attrs
## -----------------------------
-keepattributes *Annotation*, Signature, EnclosingMethod, InnerClasses, Exceptions, SourceFile, LineNumberTable

# Keep Flutter entrypoints and embedding
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# Keep your main Activity (adjust package if yours differs)
-keep class com.example.flutter_fms.MainActivity { *; }

## -----------------------------
## Kotlin / Coroutines / Stdlib
## -----------------------------
-dontwarn kotlin.**
-dontwarn kotlinx.coroutines.**
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }

## -----------------------------
## AndroidX / CameraX / Lifecycle
## -----------------------------
-keep class androidx.** { *; }
-dontwarn androidx.**
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

## -----------------------------
## Google Play Services / Firebase
## -----------------------------
# GMS core
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Firebase (Auth/Firestore/Storage/Core)
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Firestore model annotations and serializers
-keepclassmembers class * {
    @com.google.firebase.firestore.PropertyName <methods>;
    @com.google.firebase.firestore.IgnoreExtraProperties <fields>;
}
-keepattributes RuntimeVisibleAnnotations, RuntimeInvisibleAnnotations

## -----------------------------
## ML Kit (Pose Detection)
## -----------------------------
# Keep all ML Kit public APIs and internal classes that R8 might strip
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**

# Vision commons (sometimes referenced indirectly)
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.android.gms.vision.**

## -----------------------------
## Networking stacks used by Firebase
## -----------------------------
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

## -----------------------------
## JSON libs (if present)
## -----------------------------
# Gson (often used by Firebase tooling/other libs)
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
-keep class * extends com.google.gson.TypeAdapter { *; }
-keep class * implements com.google.gson.TypeAdapterFactory { *; }
-keep class * implements com.google.gson.JsonSerializer { *; }
-keep class * implements com.google.gson.JsonDeserializer { *; }

## -----------------------------
## Glide (not strictly needed unless you add it)
## -----------------------------
#-keep class com.bumptech.glide.** { *; }
#-dontwarn com.bumptech.glide.**

## -----------------------------
## Keep native method signatures (if any)
## -----------------------------
-keepclasseswithmembernames class * {
    native <methods>;
}

## -----------------------------
## (Optional) Be a bit more aggressive keeping your app pkg
## -----------------------------
# If you have any Java/Kotlin code that relies on reflection, keep it:
# -keep class com.example.flutter_fms.** { *; }

## -----------------------------
## Diagnostics (optional)
## -----------------------------
#-printusage build/outputs/mapping/usage.txt
#-whyareyoukeeping class com.google.mlkit.**
