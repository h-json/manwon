plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hjson.tenk_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.hjson.tenk_app"
        // 카카오 SDK 요구사항: minSdk 21 이상. flutter.minSdkVersion이 21이면 그대로 두고, 더 낮으면 21로 명시.
        minSdk = maxOf(flutter.minSdkVersion, 21)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 카카오 SDK URL scheme `kakao{NATIVE_APP_KEY}`에 주입됨 (AndroidManifest.xml 참조).
        // 키 갱신 시 이 값 + iOS Info.plist + lib/config/kakao_config.dart 세 곳 모두 교체.
        manifestPlaceholders["kakaoNativeAppKey"] = "589078d3c7daa590c71d9a6e77080b18"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
