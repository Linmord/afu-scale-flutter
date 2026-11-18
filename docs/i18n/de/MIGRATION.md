# Daten aus der alten RN-Version migrieren

Die Flutter-Version und die alte React-Native-Version lassen sich **parallel installieren** (unterschiedliche Paketnamen). Nach der ersten Installation die alten Datensätze mit den folgenden Schritten übernehmen.

## Wo die Daten der alten Version liegen

Die alte RN-Version speichert in AsyncStorage (im Kern eine SQLite-Tabelle `RKStorage`):

```bash
# Datenverzeichnis ansehen (dafür wird ein debuggable Build oder root benötigt)
adb shell "run-as com.aiyue.afuscale ls databases/"
# exportieren
adb exec-out run-as com.aiyue.afuscale cat databases/RKStorage > afu_rn.db
# Tabellenstruktur: CREATE TABLE kv_data(key TEXT, value TEXT)
sqlite3 afu_rn.db "SELECT key, value FROM kv_data" > rn_export.json
```

## Programmatisch importieren

Liegt das JSON vor (etwa `{"afu_user_profiles":"[...]", "afu_records":"[...]", ...}`):

```dart
import 'data/migration.dart';
final count = await migrateFromJson(rnData);
```

## Zuordnungstabelle der Schlüssel

| Schlüssel der alten RN-Version | Schlüssel der neuen Flutter-Version | Erläuterung |
| --- | --- | --- |
| `afu_user_profiles` | `afu_profiles` | Mitgliedsprofile |
| `afu_records` | `afu_records` | Messdatensätze (mit Körperzusammensetzung / profile) |
| `afu_goal_weights` | `afu_goals` | Zielgewicht |
| `afu_display_unit` | `afu_display_unit` | Anzeigeeinheit |
| `afu_pending_history` | `afu_pending` | noch zuzuordnender Verlauf |
| `afu_bound_devices` | `afu_devices` | gekoppelte Geräte |

Die Migration schreibt nur Einträge, deren **Zielschlüssel leer** ist, überschreibt keine vorhandenen Daten und lässt sich gefahrlos wiederholen.

## received.jsonl auf der Rechnerseite

Die Datei `server/received.jsonl` auf der Empfängerseite ist eine eigenständige Sicherung; die Struktur jeder Zeile ist mit `MeasurementRecord` kompatibel. Man kann sie von Hand in ein `afu_records`-Array umwandeln und dann wie oben beschrieben importieren.

## Überprüfung

Nach der Migration die Datenseite öffnen: die Zahl der Mitglieder und der Datensätze sollte mit der alten Version übereinstimmen. Zeigt ein Datensatz „diesmal keine Körperimpedanz gemessen“, hatte der ursprüngliche Datensatz von Anfang an keine Impedanz (auch die alte Version konnte daraus keine Körperzusammensetzung berechnen); es ist kein Migrationsverlust.