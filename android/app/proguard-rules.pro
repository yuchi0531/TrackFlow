# Flutter - keep all
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Workmanager - callback dispatcher must survive
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class androidx.work.** { *; }

# Drift / SQLite - native code and generated classes
-keep class com.trackflow.trackflow.** { *; }
-keep class drift.** { *; }
-keep class sqlite3.** { *; }
-keep class org.sqlite.** { *; }

# Riverpod
-keep class riverpod.** { *; }

# Dart FFI / native
-keep class dart.** { *; }
-keep class io.flutter.embedding.** { *; }

# General keep rules for reflection
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions

# Don't obfuscate
-dontobfuscate

# Keep all @Keep annotated classes
-keep @androidx.annotation.Keep class * { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
