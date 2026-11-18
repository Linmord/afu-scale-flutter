# Koontaminen ja asennus

## Ympäristövaatimukset

| Kohta | Versio |
| --- | --- |
| Flutter SDK | 3.50.x (Dart 3.14) |
| JDK | 17 |
| Android SDK | Flutterin oletus (Platform 35 vahvistettu) |

Riippuvuudet tulevat kaikki pub.devistä, yksityistä lähdettä ei tarvita.

## ⚠️ Kaksi pakollista sudenkuoppaa

### 1. Projektin polku ei saa sisältää kiinankielisiä merkkejä

Gradle hylkää ei-ASCII-projektipolut suoraan:

```
Your project path contains non-ASCII characters. This will most likely cause
the build to fail on Windows.
```

Lähdekoodi voi olla kiinankielisessä hakemistossa, mutta **koontaminen pitää tehdä ASCII-polun kopiossa**. Tämän projektin paikallinen kulku:

```bash
# lähdekoodi on hakemistossa D:\AI work\杂活\afu-flutter, kopioidaan hakemistoon D:\afuflutter ja koontaan siellä
cp -r "D:/AI work/杂活/afu-flutter/lib/"* /d/afuflutter/lib/
```

### 2. Kotlinin inkrementaalinen käännösvälimuisti juuttuu (Windows)

Virheilmoitus:

```
Could not close incremental caches in .../kotlin/compileReleaseKotlin/cacheable/...
```

Lisää tiedostoon `android/gradle.properties`:

```properties
kotlin.incremental=false
kotlin.compiler.execution.strategy=in-process
```

## Koontaminen

```bash
export PATH="/path/to/flutter/bin:$PATH"
export ANDROID_HOME="/path/to/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="/path/to/jdk-17"

cd afu-scale-flutter
flutter pub get
flutter build apk --release
```

Tuotos: `build/app/outputs/flutter-apk/app-release.apk`

## Langaton asennus (adb)

```bash
ADB=adb
# portti vaihtuu langattoman vianetsinnän kytkimen mukaan, nykyisen arvon voi hakea mdns:llä
"$ADB" mdns services | grep 192.168
"$ADB" connect <puhelimen IP>:<portti>
"$ADB" install -r build/app/outputs/flutter-apk/app-release.apk
```

Ensimmäisen asennuksen jälkeen lisää puuttuvat luvat (muuten skannaus ei tuota tulosta):

```bash
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_SCAN
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.BLUETOOTH_CONNECT
"$ADB" shell pm grant com.aiyue.afu_scale android.permission.ACCESS_FINE_LOCATION
```

## CI

`.github/workflows/build.yml`: push `main`-haaraan tai manuaalinen laukaisu koontaa Ubuntulla release-APK:n ja lataa sen artifactiksi.

## Debug-tila (easter egg)

Debug-sisäänkäynti on oletuksena piilotettu:

> **Asetukset → Tietoja → napauta versionumeroa 7 kertaa**

Avauksen jälkeen ilmestyvät "Virheenkorjausloki" ja mittaussivun oikean yläkulman viestintäpainike. Viestintäloki tallentuu automaattisesti 3 sekunnin välein:

```bash
adb pull /storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

Muoto: `aika →/← raaka 20 tavua [komennon nimi]`, ensikäden materiaalia protokollaongelmien selvittämiseen.
