plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 고정 업로드 키. CI가 KEYSTORE_PATH/KEYSTORE_PASSWORD 환경변수로 주입한다.
// 같은 키로 서명해야 폰에서 덮어쓰기 업데이트가 되고, Play 업로드 키와도 일치한다.
val ciKeystorePath: String? = System.getenv("KEYSTORE_PATH")

android {
    namespace = "com.example.ttareungi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications가 java.time을 써서 데스가링 필수
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.sooya8922.ttareungi"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (ciKeystorePath != null) {
            create("upload") {
                storeFile = file(ciKeystorePath)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = "upload"
                keyPassword = System.getenv("KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // CI: 고정 upload 키 / 로컬(키 없음): debug 키 폴백
            signingConfig = if (ciKeystorePath != null) signingConfigs.getByName("upload")
                            else signingConfigs.getByName("debug")
            // R8이 flutter_local_notifications 내부(GSON TypeToken)를 지워 시작 크래시를
            // 내는 알려진 문제가 있어 축소는 끈다.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
