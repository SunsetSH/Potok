import java.util.zip.ZipFile

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.potok.potok"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.potok.potok"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// sqlite3 3.x is delivered through Dart Native Assets. Flutter 3.44 can emit a
// correct native_assets.json while leaving its Android jniLibs directory empty,
// especially after switching between `flutter test`, Windows and Android
// builds. In that state the APK starts without libsqlite3.so and Drift fails
// before the first frame. Copy the exact hook output for every requested ABI
// into Flutter's release jniLibs input and make a broken release impossible to
// publish. A compact android-arm64 build still receives arm64-v8a only.
val prepareReleaseSqliteNativeAssets by tasks.registering {
    dependsOn("compileFlutterBuildRelease")
    doLast {
        val requestedArchitectures = (findProperty("target-platform") as String?)
            ?.split(',')
            ?.mapNotNull {
                when (it.trim()) {
                    "android-arm" -> "arm" to "armeabi-v7a"
                    "android-arm64" -> "arm64" to "arm64-v8a"
                    "android-x64" -> "x64" to "x86_64"
                    else -> null
                }
            }
            .orEmpty()
        check(requestedArchitectures.isNotEmpty()) {
            "Android release did not declare a supported target-platform"
        }
        val hookRuns = project.file("../../.dart_tool/hooks_runner/sqlite3")
            .listFiles()
            .orEmpty()
            .filter { it.isDirectory }
            .mapNotNull { run ->
                val input = run.resolve("input.json")
                val output = run.resolve("output.json")
                if (!input.isFile || !output.isFile) return@mapNotNull null
                val inputText = input.readText()
                if (!Regex("\"target_os\"\\s*:\\s*\"android\"").containsMatchIn(inputText)) {
                    return@mapNotNull null
                }
                Triple(inputText, output, output.lastModified())
            }
            .sortedByDescending { (_, _, modified) -> modified }

        requestedArchitectures.forEach { (architecture, abi) ->
            val output = hookRuns.firstOrNull { (input, _, _) ->
                Regex("\"target_architecture\"\\s*:\\s*\"$architecture\"")
                    .containsMatchIn(input)
            }?.second ?: error(
                "sqlite3 Native Assets hook did not produce an Android $architecture output",
            )
            val encodedPath = Regex("\"file\"\\s*:\\s*\"([^\"]*libsqlite3\\.so)\"")
                .find(output.readText())
                ?.groupValues
                ?.get(1)
                ?: error("sqlite3 $architecture hook output does not contain libsqlite3.so")
            val decodedPath = encodedPath.replace("\\\\", "\\")
            var source = file(decodedPath)
            if (!source.isFile) {
                val marker = decodedPath.replace('\\', '/').indexOf(".dart_tool/")
                if (marker >= 0) {
                    source = project.file("../..").resolve(
                        decodedPath.replace('\\', '/').substring(marker),
                    )
                }
            }
            check(source.isFile && source.length() > 1_000_000) {
                "sqlite3 $architecture native library is missing or truncated: $source"
            }

            val destination = layout.buildDirectory.file(
                "intermediates/flutter/release/native_assets/jniLibs/lib/$abi/libsqlite3.so",
            ).get().asFile
            destination.parentFile.mkdirs()
            source.copyTo(destination, overwrite = true)
            check(destination.length() == source.length()) {
                "sqlite3 $architecture native library was not copied completely"
            }
        }
    }
}

// Flutter 3.44 registers its native-assets directory through the generated
// copyJniLibsFlutterRelease source. SQLite must exist before that task snapshots
// the directory; wiring it only to AGP's later merge task is already too late.
tasks.matching { it.name == "copyJniLibsFlutterRelease" }.configureEach {
    dependsOn(prepareReleaseSqliteNativeAssets)
}

tasks.matching { it.name == "assembleRelease" }.configureEach {
    doLast {
        val apks = project.fileTree(layout.buildDirectory.dir("outputs/apk/release")) {
            include("*.apk")
        }.files
        var checkedApplicationAbi = false
        apks.forEach { apk ->
            ZipFile(apk).use { zip ->
                listOf("armeabi-v7a", "arm64-v8a", "x86_64").forEach { abi ->
                    if (zip.getEntry("lib/$abi/libapp.so") != null) {
                        checkedApplicationAbi = true
                        check(zip.getEntry("lib/$abi/libsqlite3.so") != null) {
                            "Refusing broken release: ${apk.name} has no $abi/libsqlite3.so"
                        }
                    }
                }
            }
        }
        check(checkedApplicationAbi) { "Release produced no APK containing a supported application ABI" }
    }
}
