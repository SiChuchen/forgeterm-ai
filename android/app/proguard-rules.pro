# ProGuard 规则 — ForgeTerm AI
# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# dartssh2
-keep class com.jcraft.** { *; }

# Hive
-keep class ** extends com.google.crypto.tink.** { *; }

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Flutter embedding 会包含 deferred components 的可选 Play Core 引用；
# 当前应用未启用 Play Feature Delivery，按 AGP 生成规则屏蔽缺失告警即可。
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# 保留注解
-keepattributes *Annotation*
