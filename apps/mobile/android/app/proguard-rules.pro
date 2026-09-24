# Release builds are shrunk by R8, which removes code it cannot see being used.
# ML Kit and the Firebase component system it runs on find their registrars by
# reflection, so R8 strips their constructors and the detector plugin then fails
# to register — in RELEASE builds only. Debug builds and unit tests never see it;
# the self-test on a release APK did ("Could not instantiate ...Registrar").
-keep class com.google.mlkit.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.firebase.components.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_object_detection.** { *; }

# ARCore reaches parts of itself through JNI and reflection too
# (DeviceProbe.kt, the self-test's AR check).
-keep class com.google.ar.core.** { *; }
-dontwarn com.google.ar.core.**
