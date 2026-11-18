# ビルドとインストール

## 環境要件

| 項目 | バージョン |
| --- | --- |
| Flutter SDK | 3.50.x（Dart 3.14）|
| JDK | 17 |
| Android SDK | Flutter の既定に従う（Platform 35 で検証済み）|

依存はすべて pub.dev から取得し、プライベートリポジトリは不要。

## ⚠️ 必ず踏む 2 つの落とし穴

### 1. プロジェクトのパスに中国語を含められない

Gradle は非 ASCII のプロジェクトパスをそのまま拒否する：

```
Your project path contains non-ASCII characters. This will most likely cause
the build to fail on Windows.
```

ソースは中国語のディレクトリに置いてよいが、**ビルドは ASCII パスのコピー上で行う必要がある**。本プロジェクトのローカル手順：

```bash
# ソースは D:\AI work\杂活\afu-flutter にあり、D:\afuflutter へコピーしてからビルドする
cp -r "D:/AI work/杂活/afu-flutter/lib/"* /d/afuflutter/lib/
```

### 2. Kotlin のインクリメンタルビルドキャッシュがロックする（Windows）

エラー：

```
Could not close incremental caches in .../kotlin/compileReleaseKotlin/cacheable/...
```

`android/gradle.properties` に次を追記する：

```properties
kotlin.incremental=false
kotlin.compiler.execution.strategy=in-process
```

## ビルド

```bash
export PATH="/path/to/flutter/bin:$PATH"
export ANDROID_HOME="/path/to/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="/path/to/jdk-17"

cd afu-scale-flutter
flutter pub get
flutter build apk --release
```

成果物：`build/app/outputs/flutter-apk/app-release.apk`

## ワイヤレスインストール（adb）

```bash
ADB=adb
# ポートはワイヤレスデバッグのオン／オフで変わる。mdns で現在値を調べられる
"$ADB" mdns services | grep 192.168
"$ADB" connect <スマホのIP>:<ポート>
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
```

初回インストール後に権限を付与する（付与しないとスキャンで何も出ない）：

```bash
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_SCAN
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_CONNECT
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.ACCESS_FINE_LOCATION
```

## CI

`.github/workflows/build.yml`：`main` へのプッシュまたは手動実行のとき、Ubuntu 上で release APK をビルドして artifact としてアップロードする。

## デバッグモード（イースターエッグ）

デバッグの入口は既定で隠されている：

> **設定 → バージョン情報 → バージョン番号を 7 回連打**

解錠すると「デバッグログ」と、測定ページ右上の通信ボタンが現れる。通信ログは 3 秒ごとに自動でファイルへ書き出される：

```bash
adb pull /storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

形式：`時刻 →/← 生 20 バイト [コマンド名]`。プロトコル問題の切り分けに使える一次資料。
