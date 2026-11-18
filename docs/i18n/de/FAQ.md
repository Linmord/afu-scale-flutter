# Häufige Fragen

## Warum ändert sich der BMI beim Umschalten des Geschlechts nicht?

Weil **die Definition des BMI kein Geschlecht kennt**:

```
BMI = Gewicht (kg) ÷ Größe (m)²
```

Das ist die Standarddefinition der WHO und hängt nur von Gewicht und Größe ab. **Ändert sich die Größe, ändert sich der BMI**, beim Geschlecht nicht.

Was sich tatsächlich mit dem Geschlecht ändert, ist die Körperzusammensetzung:

| Kennwert | Männer | Frauen |
| --- | --- | --- |
| Körperfettanteil | Deurenberg: `1.10×BMI + 0.23×Alter − 11.22` (die Impedanz spielt keine Rolle) | Segal: benötigt die Impedanz, zusammengefasst über `(i1+i2)×0.675` |
| Körperwasseranteil | fettfreie Masse × 0.7185 | fettfreie Masse × 0.8475 |
| Protein | Gewicht × 0.163 | Gewicht × 0.05 |
| Skelettmuskelanteil | Muskelmasse × 0.548 | Muskelmasse × 0.651 |
| Unterhautfett | Körperfett × 0.7165 | Körperfett × 0.72 |

Derselbe Datensatz (55.75kg / 163cm / 24 Jahre / Impedanz 430+387): Männer **17.4%**, Frauen **22.2%**, also 4.8 Prozentpunkte Unterschied.

## Geschlecht oder Größe geändert, die Kennwerte im Verlauf bleiben gleich?

Frühere Versionen hatten zwei Mängel (inzwischen behoben):

1. der BMI nutzte die **im Datensatz gespeicherte alte Größe**, nicht die des aktuellen Profils
2. Datensätze ohne Impedanz wurden beim Neuberechnen einfach übersprungen, das Profil blieb unverändert

Stand heute: gehört ein Datensatz zum aktuell gewählten Mitglied, wird er durchgehend nach dem **neuesten Profil** in Echtzeit berechnet; Änderungen an Größe, Geschlecht oder Alter wirken sofort.

## Die Impedanz bleibt 0 / es erscheint „diesmal keine Körperimpedanz gemessen“

Die Impedanz hängt **allein von den physikalischen Bedingungen** ab und lässt sich nicht per Befehl einschalten:

- **beide Füße barfuß** müssen gleichzeitig auf den vier Elektrodenflächen stehen
- ein Fuß, Socken oder zu trockene Fußsohlen → zwangsläufig 0
- auch bei zu niedrigem Akkustand (etwa 10%) kann es scheitern

Der Befehl `04 d6` erhöht nur die Frequenz der Echtzeitpakete und ist **kein Impedanzschalter** (durch A/B-Vergleich in der Praxis bestätigt).

## Ist eine Akkustandanzeige von etwa 10% normal?

Ja. Der echte Akkustand steckt in den unteren 7 Bit von `data[11]` des Echtzeitpakets; im Standby ist der gemessene Modalwert genau **10%**.

Achtung: diese Waage hat **keinen** Standard-Batteriedienst `0x2A19`; liest man diese Charakteristik, erhält man Müll (etwa 77%), und diese App übernimmt solche Werte nicht.

## Gibt es bei jedem Wiegen einen „Verlaufsdatensatz“?

Das ist ein **normaler Mechanismus**: jedes Wiegen erzeugt einen neuen Datensatz, und bei der nächsten Verbindung schiebt die Waage die „nicht synchronisierten“ Datensätze nach.

- nach dem Nachschieben markiert die Waage sie intern als synchronisiert und schiebt sie nicht erneut nach
- mehrfach zugestellte gleiche Datensätze werden anhand `Zeit_Gewicht` dedupliziert und nicht doppelt gespeichert
- **die Waage kennt keinen Löschbefehl** (alle 29 offiziellen Schreibbefehle wurden geprüft), also während der Verbindung nicht den Prozess abbrechen: was nicht gespeichert wird, ist endgültig verloren

## Die Waage wird nicht gefunden / der Scan ist sehr langsam

Der Reihe nach prüfen:

1. **sanft auftreten zum Aufwecken**: im Ruhezustand sendet die Waage nicht; erst wenn das Display nach dem Aufwecken leuchtet, sendet sie durchgehend
2. **Berechtigungen prüfen**: ab Android 12+ werden „Geräte in der Nähe“ + „Standort“ benötigt; per `adb shell pm grant` lassen sie sich nachträglich erteilen
3. **keine UUID-Vorfilterung**: auf MIUI fällt die Waage bei Filterung über die Dienst-UUID messbar durch; dieses Projekt scannt vollständig und filtert im Callback
4. **`neverForLocation` nicht setzen**: dieses Flag führt dazu, dass Android 12+ das Beacon-Advertising dieser Waage herausfiltert (in logcat als `Skipping data matching denylist` sichtbar)

## Nach dem Umbenennen sind die Daten „verschwunden“

Im Datensatz steht der **Name des Mitglieds** (`record.unit`); wird beim Umbenennen nicht synchronisiert, bleiben alte Datensätze unter dem alten Namen hängen.

- neue Versionen synchronisieren beim Umbenennen automatisch (`renameRecordOwner`)
- bereits kaputt benannte Daten lassen sich über **Einstellungen → Mitgliederverwaltung → Zugehörigkeit der Datensätze reparieren** wiederherstellen: dort werden die alten Namen mit den **zurückgebliebenen Profilen (Geschlecht/Größe/Alter)** und der Anzahl aufgelistet; ein Zielmitglied auswählen genügt, um sie zuzuordnen

## Die Verbindung bricht sofort nach dem Verbinden ab / verbindet sich immer wieder neu

Frühere Versionen meldeten im Moment des Verbindungsaufbaus einmal fälschlich `disconnected`, was ein Wiederverbinden auslöste → derselbe Sitzungshandshake lief zweimal → die Waage behandelte das als neue Synchronisierungssitzung und schob den Verlauf erneut nach.

Inzwischen behoben: vor dem Wiederverbinden wird `isConnected` erneut geprüft, zusätzlich gibt es eine Nebenläufigkeitssperre `_connecting`.

## Zwei gleichnamige AFU-Apps auf dem Smartphone

Die alte RN-Version hat den Paketnamen `com.aiyue.afuscale`, die Flutter-Version `com.aiyue.afu_scale`; auf dem Startbildschirm heißen beide AFU.

Öffnet man die App und sieht unten die zwei Tabs „Daten / Einstellungen“, handelt es sich um die Flutter-Version.