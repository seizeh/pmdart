import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services") // FCM(google-services.json 적용)
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리즈 서명(Play 업로드 키) — android/key.properties 는 커밋 금지(.gitignore).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// 키가 없는데 릴리스를 만들려 하면 **실패시킨다.**
//
// 종전에는 debug 키로 조용히 폴백했다. 그러면 키가 없는 머신에서도
// `flutter build appbundle --release` 가 **성공**하고 debug 서명된 산출물이 나온다.
// Play 업로드는 거절하지만 직접 배포용 APK 라면 설치까지 되고, 나중에 정식 키로
// 서명한 버전으로 **업그레이드가 막힌다**(서명 불일치 — 재설치 외에 방법이 없다).
// 잘못 서명된 산출물은 되돌릴 수 없고, 산출물만 봐서는 그 사실이 드러나지 않는다.
//
// ⚠️ 이 검사를 buildTypes.release 블록 안에 두면 안 된다 — 그 블록은 **설정 시점**에
// 실행되므로 키가 없는 머신에서 debug 빌드·`flutter run` 까지 막아 버린다.
// 릴리스 태스크가 실제로 실행 그래프에 있을 때만 본다.
gradle.taskGraph.whenReady {
    val releasing = allTasks.any {
        (it.name.startsWith("assemble") || it.name.startsWith("bundle")) &&
            it.name.contains("Release")
    }
    if (releasing && keystoreProperties.isEmpty()) {
        throw GradleException(
            "release 서명 키가 없습니다 — android/key.properties 를 만들어 주세요.\n" +
                "  필요 항목: storeFile / storePassword / keyAlias / keyPassword\n" +
                "  (debug 키 폴백은 제거했습니다: debug 서명 산출물은 Play 에 올릴 수 없고,\n" +
                "   직접 설치되면 정식 키 버전으로 업그레이드가 막힙니다.)\n" +
                "  릴리스가 목적이 아니라면 --debug 또는 --profile 로 빌드하세요."
        )
    }
}

android {
    namespace = "com.seizeh.pawmate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications(포그라운드 OS 알림)가 java.time 등
        // 최신 API 를 구형 안드로이드에서 쓰기 위해 요구.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.seizeh.pawmate"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_naver_map 1.4.x 는 minSdk 23 이상 필요
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 키가 없으면 서명 설정을 비운다(= 미서명 산출물). debug 키로 폴백하지
            // 않는 게 요점이다 — 위 taskGraph 검사가 릴리스 태스크를 먼저 막지만,
            // 그걸 우회하더라도 debug 서명본이 나가는 일은 없어야 한다.
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
