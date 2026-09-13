# TensorFlow Lite Keep Rules
-dontwarn org.tensorflow.lite.**
-keep class org.tensorflow.lite.** { *; }

# Google ML Kit Keep Rules
-dontwarn com.google.mlkit.**
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }

# Flutter & Firebase Keep Rules
-dontwarn io.flutter.**
-keep class io.flutter.** { *; }
-keep class com.google.firebase.** { *; }

-ignorewarnings
