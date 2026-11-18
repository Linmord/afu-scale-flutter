# 构建与安装

## 环境要求

| 项 | 版本 |
| --- | --- |
| Flutter SDK | 3.50.x（Dart 3.14）|
| JDK | 17 |
| Android SDK | 跟随 Flutter 默认（Platform 35 已验证）|

依赖全部来自 pub.dev，无需私有源。

## ⚠️ 两个必踩的坑

### 1. 项目路径不能含中文

Gradle 对非 ASCII 项目路径直接拒绝：

```
Your project path contains non-ASCII characters. This will most likely cause
the build to fail on Windows.
```

源码可以放在中文目录，但**构建必须在 ASCII 路径的副本上进行**。本项目本机流程：

```bash
# 源码在 D:\AI work\杂活\afu-flutter，复制到 D:\afuflutter 再构建
cp -r "D:/AI work/杂活/afu-flutter/lib/"* /d/afuflutter/lib/
```

### 2. Kotlin 增量编译缓存会锁死（Windows）

报错：

```
Could not close incremental caches in .../kotlin/compileReleaseKotlin/cacheable/...
```

在 `android/gradle.properties` 追加：

```properties
kotlin.incremental=false
kotlin.compiler.execution.strategy=in-process
```

## 构建

```bash
export PATH="/path/to/flutter/bin:$PATH"
export ANDROID_HOME="/path/to/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="/path/to/jdk-17"

cd afu-scale-flutter
flutter pub get
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

## 无线安装（adb）

```bash
ADB=adb
# 端口随无线调试开关变化，可用 mdns 查当前值
"$ADB" mdns services | grep 192.168
"$ADB" connect <手机IP>:<端口>
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
```

首次安装后补授权限（否则扫描无结果）：

```bash
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_SCAN
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_CONNECT
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.ACCESS_FINE_LOCATION
```

## CI

`.github/workflows/build.yml`：推送到 `main` 或手动触发时，在 Ubuntu 上构建 release APK 并上传为 artifact。

## 调试模式（彩蛋）

调试入口默认隐藏：

> **设置 → 关于 → 连点版本号 7 次**

解锁后出现「调试日志」与测量页右上角的通讯按钮。通讯日志每 3 秒自动落盘：

```bash
adb pull /storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

格式：`时间 →/← 原始 20 字节 [命令名]`，排查协议问题的一手材料。
