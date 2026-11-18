# Build and install

## Environment requirements

| Item | Version |
| --- | --- |
| Flutter SDK | 3.50.x (Dart 3.14) |
| JDK | 17 |
| Android SDK | follow the Flutter default (Platform 35 verified) |

All dependencies come from pub.dev; no private repository is needed.

## ⚠️ Two pitfalls you are bound to hit

### 1. The project path must not contain Chinese characters

Gradle rejects a non-ASCII project path outright:

```
Your project path contains non-ASCII characters. This will most likely cause
the build to fail on Windows.
```

The source can live in a Chinese-named directory, but **the build must run on a copy at an ASCII path**. This project's local flow:

```bash
# source is at D:\AI work\杂活\afu-flutter, copy to D:\afuflutter and build there
cp -r "D:/AI work/杂活/afu-flutter/lib/"* /d/afuflutter/lib/
```

### 2. The Kotlin incremental compilation cache deadlocks (Windows)

The error:

```
Could not close incremental caches in .../kotlin/compileReleaseKotlin/cacheable/...
```

Append to `android/gradle.properties`:

```properties
kotlin.incremental=false
kotlin.compiler.execution.strategy=in-process
```

## Build

```bash
export PATH="/path/to/flutter/bin:$PATH"
export ANDROID_HOME="/path/to/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="/path/to/jdk-17"

cd afu-scale-flutter
flutter pub get
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## Wireless install (adb)

```bash
ADB=adb
# the port changes with the wireless debugging toggle; use mdns to look up the current value
"$ADB" mdns services | grep 192.168
"$ADB" connect <phone IP>:<port>
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
```

After the first install, grant the extra permissions (otherwise scanning finds nothing):

```bash
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_SCAN
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_CONNECT
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.ACCESS_FINE_LOCATION
```

## CI

`.github/workflows/build.yml`: on a push to `main` or a manual trigger, build the release APK on Ubuntu and upload it as an artifact.

## Debug mode (easter egg)

The debug entry point is hidden by default:

> **Settings → About → tap the version number 7 times**

Once unlocked, the "debug log" and the comm button in the top right of the measurement page appear. The communication log is written to disk automatically every 3 seconds:

```bash
adb pull /storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

Format: `时间 →/← 原始 20 字节 [命令名]`, first-hand material for troubleshooting protocol problems.
