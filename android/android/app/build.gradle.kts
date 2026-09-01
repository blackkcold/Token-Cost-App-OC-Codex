import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing credentials from the local cache directory
// (~/.config/token-cost/android-release/, 0700/0600). This is the single
// on-disk store seeded once from 1Password by script/bootstrap_android_release.sh;
// builds read it directly with zero 1Password / keychain / popup access.
val signCacheDir = System.getProperty("user.home") + "/.config/token-cost/android-release"
val secretsFile = File(signCacheDir, "secrets.properties")
val jksFile = File(signCacheDir, "balance-monitor-release.jks")
val keystoreProperties = Properties()
val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (secretsFile.exists() && jksFile.exists()) {
    secretsFile.inputStream().use { keystoreProperties.load(it) }
    keystoreProperties["storeFile"] = jksFile.absolutePath
}

android {
    namespace = "com.yanghaoran.balance_monitor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.yanghaoran.balance_monitor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (secretsFile.exists() && jksFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (secretsFile.exists() && jksFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else if (releaseBuildRequested) {
                throw GradleException("Release signing configuration is required")
            }
            // 启用 R8 代码压缩 + 资源收缩，剔除未用 Dart/Java 代码与资源，显著减小包体积。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // 按 ABI 拆分 APK：GitHub 分发时每个架构只打包一份原生库（mobile_scanner/MLKit），
    // 相比 universal 单包大幅减小体积。arm64-v8a 覆盖现代设备，armeabi-v7a 覆盖旧设备。
    // 注意：AAB（Play Store bundle）自身会按 ABI 分发，因此构建 bundle 时禁用 splits，
    // 避免与 AAB 打包冲突（见 https://issuetracker.google.com/402800800）。
    splits {
        abi {
            isEnable = gradle.startParameter.taskNames.any { it.contains("assemble") }
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = true
        }
    }
}

dependencies {
    // Flutter 引擎的可选 deferred-components 引用了 Play Core API。
    // 启用 R8 后缺少这些类会导致 minify 失败，因此显式声明依赖。
    implementation("com.google.android.play:core:1.10.3")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
