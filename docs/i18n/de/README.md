# AFU

<p align="center">
  <a href="../../../README.md">简体中文</a> &middot; <a href="../zh-Hant/README.md">繁體中文</a> &middot; <a href="../ja/README.md">日本語</a> &middot; <b>Deutsch</b> &middot; <a href="../fi/README.md">Suomi</a> &middot; <a href="../en/README.md">English</a>
</p>


**AFU-WL-TZ-A1** (Ant Afu × Welland ICOMON) – Android-Client für die Körperanalysewaage · Flutter-Neuimplementierung  
Lokal zuerst · kein Benutzerkonto · keine Cloud-Synchronisierung · 5 Sprachen · helles und dunkles Theme

<p align="center">
  <img src="../../screenshots/home.jpg" width="200" alt="Datenansicht">
  &nbsp;&nbsp;
  <img src="../../screenshots/sett.jpeg" width="200" alt="Funktionsübersicht">
  &nbsp;&nbsp;
  <img src="../../screenshots/proto.jpeg" width="200" alt="Kommunikationsprotokoll">
</p>

<p align="center"><sub>Datenansicht · Funktionsübersicht · Kommunikationsprotokoll (sichtbar im Debug-Modus)</sub></p>

## Funktionen

- **Scan in unter 1 Sekunde**: gleiches Smartphone, gleiche Waage – die alte React-Native-Version brauchte 7 Minuten
- **Ringförmiges Dashboard**: Wiegen → Impedanz → Fertig, dreistufige Animation
- **Mehrere Mitglieder**: Profilverwaltung, Namensänderung synchronisiert den Verlauf, Reparatur verwaister Datensätze
- **Daten**: Filter nach 72H / 7d / 30day / benutzerdefiniertem Zeitraum, Trenddiagramm, Massen-Push · Verschieben · Löschen
- **LAN-Synchronisierung**: HTTP-Push an einen selbst betriebenen Empfänger
- **Algorithmus vollständig offengelegt**: BIA-Formeln und jeder einzelne Koeffizient erläutert, Originalformeln aus der Fachliteratur und im Messversuch kalibrierte Werte werden unterschieden
- 5 Sprachen · helles und dunkles Theme · kg / lb / Jin

## Dokumentation

| Dokument | Inhalt |
| --- | --- |
| [Protokoll · verständliche Fassung](PROTOCOL.md) | Von „wie findet man die Waage“ bis „wie werden Bytes zu einem Gewicht“, inklusive 10 Fallstricke aus der Praxis |
| [Protokoll · Spezifikation](PROTOCOL_SPEC.md) | Technische Spezifikation für Implementierer: feldgenaue Definitionen, Zustandsautomat, Testvektoren, Konsistenzliste |
| [Körperzusammensetzungs-Algorithmus](ALGORITHM.md) | Wie Körperfettanteil, Körperwasseranteil, Muskelmasse und Skelettmuskulatur berechnet werden, mit Formeln und Quellenangaben zu den Koeffizienten |
| [Build und Installation](BUILD.md) | Umgebungsanforderungen, zwei unvermeidbare Fallstricke, drahtlose Installation |
| [Datenmigration](MIGRATION.md) | Verlaufsdatensätze aus der alten RN-Version importieren |
| [Häufige Fragen](FAQ.md) | Warum BMI sich nicht mit dem Geschlecht ändert, Impedanz gleich 0, Akkustand, Verlaufsmechanik |

## Schnellstart

```bash
git clone https://github.com/Linmord/afu-scale-flutter.git
cd afu-scale-flutter
flutter pub get
flutter build apk --release
```

> ⚠️ Der Projektpfad darf **keine chinesischen Zeichen enthalten**, sonst bricht Gradle mit einem Fehler ab. Siehe [Build-Dokumentation](BUILD.md).

Jeder Push auf `main` baut automatisch ein APK ([`.github/workflows/build.yml`](../../../.github/workflows/build.yml)); das Ergebnis liegt unter Actions in den Artifacts.

## Alte Version

Die React-Native-Version wird **nicht mehr gepflegt** → [Linmord/afu-scale-app](https://github.com/Linmord/afu-scale-app)

## Haftungsausschluss

Inoffizieller Client, der in keiner Verbindung zu Ant Afu / Welland (ICOMON) steht. Das Protokoll wurde durch öffentliche Paketmitschnitte und Reverse Engineering hergeleitet und kann mit einem Firmware-Update ungültig werden.
Die Körperzusammensetzung ist ein per BIA-Formel geschätzter Wert, dient nur als persönlicher Trendhinweis und ist keine medizinische Diagnosegrundlage.