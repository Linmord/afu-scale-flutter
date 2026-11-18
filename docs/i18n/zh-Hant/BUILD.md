# 建置與安裝

## 環境需求

| 項 | 版本 |
| --- | --- |
| Flutter SDK | 3.50.x（Dart 3.14）|
| JDK | 17 |
| Android SDK | 跟隨 Flutter 預設（Platform 35 已驗證）|

依賴全部來自 pub.dev，無需私有來源。

## ⚠️ 兩個必踩的坑

### 1. 專案路徑不能含中文

Gradle 對非 ASCII 專案路徑直接拒絕：

```
Your project path contains non-ASCII characters. This will most likely cause
the build to fail on Windows.
```

原始碼可以放在中文目錄，但**建置必須在 ASCII 路徑的副本上進行**。本專案本機流程：

```bash
# 原始碼在 D:\AI work\杂活\afu-flutter，複製到 D:\afuflutter 再建置
cp -r "D:/AI work/杂活/afu-flutter/lib/"* /d/afuflutter/lib/
```

### 2. Kotlin 增量編譯快取會鎖死（Windows）

報錯：

```
Could not close incremental caches in .../kotlin/compileReleaseKotlin/cacheable/...
```

在 `android/gradle.properties` 追加：

```properties
kotlin.incremental=false
kotlin.compiler.execution.strategy=in-process
```

## 建置

```bash
export PATH="/path/to/flutter/bin:$PATH"
export ANDROID_HOME="/path/to/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="/path/to/jdk-17"

cd afu-scale-flutter
flutter pub get
flutter build apk --release
```

產物：`build/app/outputs/flutter-apk/app-release.apk`

## 無線安裝（adb）

```bash
ADB=adb
# 埠號隨無線偵錯開關變化，可用 mdns 查目前值
"$ADB" mdns services | grep 192.168
"$ADB" connect <手機IP>:<埠號>
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
```

首次安裝後補授權限（否則掃描無結果）：

```bash
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_SCAN
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_CONNECT
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.ACCESS_FINE_LOCATION
```

## CI

`.github/workflows/build.yml`：推送到 `main` 或手動觸發時，在 Ubuntu 上建置 release APK 並上傳為 artifact。

## 偵錯模式（彩蛋）

偵錯入口預設隱藏：

> **設定 → 關於 → 連點版本號 7 次**

解鎖後出現「偵錯日誌」與測量頁右上角的通訊按鈕。通訊日誌每 3 秒自動落盤：

```bash
adb pull /storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

格式：`时间 →/← 原始 20 字节 [命令名]`，排查協議問題的第一手材料。
