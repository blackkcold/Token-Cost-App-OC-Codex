# R8/ProGuard 保留规则 —— 防止代码压缩误删 Flutter 引擎与原生插件类。
# 这些类通过反射 / JNI / 插件注册表在运行时被调用，R8 无法静态分析到，必须显式保留。

# Flutter 引擎与嵌入层（通过反射与 JNI 调用）。
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.StatelessWidget { *; }
-keep class io.flutter.StatefulWidget { *; }

# Flutter 插件注册（GeneratedPluginRegistrant 通过反射加载）。
-keep class io.flutter.plugin.common.PluginRegistry { *; }
-keep class io.flutter.plugin.common.MethodChannel { *; }
-keep class io.flutter.plugin.common.EventChannel { *; }
-keep class io.flutter.plugin.common.BasicMessageChannel { *; }
-keep class io.flutter.plugin.common.StandardMessageCodec { *; }
-keep class io.flutter.plugin.common.StandardMethodCodec { *; }

# flutter_secure_storage 插件（Android Keystore / SharedPreferences 加密）。
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# mobile_scanner 插件（Google MLKit 扫码，通过 JNI/反射调用）。
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.common.** { *; }

# 保留所有带 @Keep 注解的类（插件可能使用）。
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep <methods>;
    @androidx.annotation.Keep <fields>;
}

# 保留原生方法（JNI）。
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保留枚举（R8 可能误删 valueOf/values）。
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
