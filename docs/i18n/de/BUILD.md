# Build und Installation

## Umgebungsanforderungen

| Punkt | Version |
| --- | --- |
| Flutter SDK | 3.50.x (Dart 3.14) |
| JDK | 17 |
| Android SDK | wie der Standard von Flutter (Platform 35 ist verifiziert) |

Alle Abhängigkeiten stammen von pub.dev, eine private Quelle ist nicht nötig.

## ⚠️ Zwei Fallstricke, in die man zwangsläufig tappt

### 1. Der Projektpfad darf keine chinesischen Zeichen enthalten

Gradle lehnt einen nicht-ASCII-Projektpfad rundheraus ab:

```
Your project path contains non-ASCII characters. This will most likely cause
the build to fail on Windows.
```

Der Quellcode darf in einem chinesischen Verzeichnis liegen, **gebaut werden muss aber auf einer Kopie unter einem ASCII-Pfad**. Der Ablauf auf dem Rechner dieses Projekts:

```bash
# der Quellcode liegt in D:\AI work\杂活\afu-flutter, zuerst nach D:\afuflutter kopieren, dann bauen
cp -r "D:/AI work/杂活/afu-flutter/lib/"* /d/afuflutter/lib/
```

### 2. Der inkrementelle Kotlin-Kompiliercache blockiert (Windows)

Fehlermeldung:

```
Could not close incremental caches in .../kotlin/compileReleaseKotlin/cacheable/...
```

In `android/gradle.properties` ergänzen:

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

Ergebnis: `build/app/outputs/flutter-apk/app-release.apk`

## Drahtlose Installation (adb)

```bash
ADB=adb
# der Port ändert sich mit dem Schalter für drahtloses Debugging; der aktuelle Wert lässt sich per mdns ermitteln
"$ADB" mdns services | grep 192.168
"$ADB" connect <Handy-IP>:<Port>
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
```

Nach der ersten Installation die Berechtigungen nachträglich erteilen (sonst liefert der Scan nichts):

```bash
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_SCAN
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_CONNECT
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.ACCESS_FINE_LOCATION
```

## CI

`.github/workflows/build.yml`: bei einem Push auf `main` oder bei manuellem Auslösen wird auf Ubuntu ein Release-APK gebaut und als Artifact hochgeladen.

## Debug-Modus (Easter Egg)

Der Debug-Einstieg ist standardmäßig versteckt:

> **Einstellungen → Über → 7-mal hintereinander auf die Versionsnummer tippen**

Nach dem Freischalten erscheinen „Debug-Log“ und die Kommunikationsschaltfläche oben rechts auf der Messseite. Das Kommunikationsprotokoll wird alle 3 Sekunden automatisch geschrieben:

```bash
adb pull /storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

Format: `Zeit →/← 20 Rohbytes [Befehlsname]`; das ist das Rohmaterial für die Fehlersuche im Protokoll.