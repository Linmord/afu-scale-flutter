# Protokoll der Körperanalysewaage AFU-WL-TZ-A1 · Verständliche Fassung

> **Für wen das geschrieben ist**: Leute mit Grundwissen zu Netzwerken (die wissen, was IP, Port und Binärdaten sind), die aber noch nie ein Bluetooth-Protokoll angefasst haben.
> Nach diesem Artikel solltest du in der Lage sein, selbst ein Programm zu schreiben, das sich mit dieser Waage verbindet und Gewicht und Körperfett ausliest.
>
> **Was hier steht**: die Protokollimplementierung, die in `afu-flutter` **wirklich läuft** – keine idealisierte Lehrbuchversion.
> Hinter jeder Aussage steht die Quelle der Belege:
> `[HCI]` = Bluetooth-Mitschnitt der offiziellen Ant-App · `[WT]` = WeighTrace-Dokumentation ·
> `[VA]` = Quellcode von vitaloop-app · `[AF]` = AntAF-Dokumentation · `[Praxis]` = von uns selbst auf echter Hardware verifiziert.
>
> Zugehöriger Code: `lib/core/protocol.dart` (Frame-Aufbau und -Auswertung) · `lib/ble/scale_ble.dart` (Verbindung und Befehlssequenz)

---

## 0. Was wir hier tun – in einem Satz

Diese Waage ist im Kern eine **sprechende digitale Waage**. Zwischen ihr und dem Smartphone läuft Folgendes ab:

1. Die Waage „ruft“ ständig ihren Namen und ihre Identität in die Luft hinaus (wie ein Laden, der ein Schild aufhängt)
2. Das Smartphone empfängt das Schild, verbindet sich und bekommt zwei „Briefkästen“: einen zum Senden, einen zum Empfangen
3. Das Smartphone steckt in fester Reihenfolge 8 einheitlich formatierte kleine Notizzettel hinein (**Handshake**)
4. Die Waage beginnt, Datenpakete in den Empfangskasten zu werfen; das Smartphone zerlegt sie Byte für Byte und berechnet Gewicht und Körperfett

Klingt einfach, aber **jede Ebene hat ihre Fallstricke** – übliche Protokolldokumente schreiben nur, „wie es sein sollte“,
dieser Artikel schreibt auch auf, „wie es in der Praxis schiefgeht“.

---

## 1. Zuerst ein paar Begriffe

In Bluetooth gibt es einen Haufen Fachbegriffe, die beim ersten Kontakt verwirren. Nehmen wir als Analogie einen **Paketschließfach-Automaten**:

| Begriff | Analogie: der Paketautomat | Eigentliche Bedeutung |
| --- | --- | --- |
| **Advertising (Werbung)** | das Mietangebot, das am Fach klebt | Ein Gerät kann ohne Verbindung dauernd hinausrufen „ich bin hier, ich heiße so“ |
| **Scan** | der Hausmeister, der mit dem Plan die Angebote abgeht | Das Smartphone verbindet sich nicht, es „hört“ nur, wer in der Luft ruft |
| **GATT** | das komplette Regelwerk des Automaten | der Standardregelsatz, nach dem Bluetooth Low Energy (BLE) Daten überträgt |
| **Dienst (Service)** | ein einzelnes Fach, etwa „Fach 3“ | eine Gruppe von Funktionen, mit einer UUID nummeriert |
| **Charakteristik** | ein kleines Ablagefach in einem Fach | der Ort, an dem Daten wirklich abgelegt und geholt werden, mit eigener UUID |
| **Write (Schreiben)** | du wirfst ein Paket hinein | Smartphone → Gerät: Daten senden |
| **Benachrichtigung (Notify)** | das Fach meldet sich aktiv, wenn es voll ist | Gerät → Smartphone: Daten unaufgefordert senden (ohne dass das Smartphone fragt) |
| **UUID** | die Nummer des Fachs, z. B. `0000ffb0-...` | eine 128 Bit (16 Byte) lange Nummer, die einen Dienst bzw. ein Ablagefach kennzeichnet |
| **MAC-Adresse** | die Ausweisnummer | die eindeutige Hardwareadresse eines Bluetooth-Geräts, z. B. `AA:BB:CC:DD:EE:FF` |
| **Byte-Reihenfolge (Big-Endian / Little-Endian)** | ob die Zahl 1234 als „erst 1 oder erst 4“ geschrieben wird | ob beim Zusammensetzen mehrerer Bytes zu einer Zahl das höchstwertige Byte vorn oder hinten steht |

**Warum man die Byte-Reihenfolge kennen muss**: später wirst du sehen, dass die Waage dasselbe Gewicht in zwei Pakettypen einmal **Big-Endian** und einmal **Little-Endian** ablegt;
dreht man das um, kommen absurde Zahlen heraus (aus 55,75 kg werden dann z. B. 14 Tonnen).

---

## 2. Schritt eins: sie in der Luft finden (Scan)

### 2.1 Was die Waage alles „ruft“

Das Advertising der Waage trägt Folgendes (wir haben es mit nRF Connect und den Systemlogs gegengeprüft):

| Inhalt | Wert |
| --- | --- |
| Advertising-Name | `AFU-WL-TZ-A1` |
| Dienst-UUID | `0xFFB0`, `0x1530` |
| Herstellerdaten | Hersteller-ID `0x27AC` |
| **ServiceData** | `0x27AC` + **echte MAC (6 Bytes, umgekehrte Reihenfolge) + 01** |
| Advertising-Intervall | 999 Millisekunden |

**Hier gibt es einen kontraintuitiven Punkt**: die Bluetooth-Adresse, die im Advertising auftaucht (RemoteID),
ist **nicht unbedingt die echte MAC der Waage**. Der echte Wert steckt in den ServiceData – und zwar **rückwärts abgelegt**.

```
ServiceData-Rohbytes:   FF EE DD CC BB AA 01
                        └─MAC (6B) rev.─┘ └(fest 01)
Rückwärts gelesen:      AA:BB:CC:DD:EE:FF   ← erst das ist die echte MAC
```

> Beim ersten Parsing haben wir das „rückwärts“ übersehen; die MAC war dadurch um ein Byte verschoben und eine Verbindung kam partout nicht zustande. [WT/Praxis]

### 2.2 Woran das Smartphone sie erkennt

Es genügt, wenn **eines der drei Kriterien** zutrifft:

1. Der Advertising-Name enthält `AFU-WL`
2. Die UUID in den ServiceData ist `0x27AC`
3. Die Dienstliste des Advertisings enthält `0xFFB0`

### 2.3 Zwei Fallstricke, die man kennen muss

**Fallstrick eins: UUID nicht als Vorfilter benutzen**

Viele Anleitungen zeigen `startScan([ffb0-UUID])`, also nur Geräte mit diesem Dienst scannen – bei dieser Waage **fällt sie dabei durch**.
Auf MIUI finden wir so auch nach 4 Minuten nichts; umgestellt auf „alles scannen und im Callback selbst filtern“ gibt es das Ergebnis in 1 Sekunde. [Praxis]

**Fallstrick zwei: das Flag `neverForLocation` nicht setzen**

Wenn man ab Android 12 die Berechtigung für den Bluetooth-Scan anfordert und dabei das Flag „dieser Scan dient nicht der Standortermittlung“ mitgibt,
filtert das System bestimmte Arten von Advertising **stillschweigend heraus** (das Advertising dieser Waage wird genau als Beacon eingestuft).
Das Symptom: alle Berechtigungen erteilt, Bluetooth eingeschaltet – und es wird trotzdem nichts gefunden.

In logcat steht dann: `Skipping data matching denylist`. Nimmt man das Flag weg, ist alles in Ordnung. [Praxis]

---

## 3. Schritt zwei: verbinden und zwei „Briefkästen“ abholen

Für die Verbindung wird die in Schritt 2 ermittelte **echte MAC** benutzt. Nach dem Verbinden siehst du einen Dienst:

```
Dienst 0000ffb0-0000-1000-8000-00805f9b34fb
  ├── Charakteristik FFB1  ← hierher „schreibt“ das Smartphone Befehle
  └── Charakteristik FFB2  ← hierher „sendet“ die Waage Daten (Benachrichtigung muss zuerst abonniert werden)
```

### 3.1 In den Briefkasten FFB1: nur „Einschreiben“ möglich

Für BLE-Writes gibt es zwei Modi:

| Modus | Umgangssprachlich erklärt | Unterstützt diese Waage das? |
| --- | --- | --- |
| **WRITE** (mit Antwort) | Einschreiben: du erfährst, dass es angekommen ist | ✅ dieser muss benutzt werden |
| WRITE_NO_RESPONSE (ohne Antwort) | einen Zettel unter der Tür durchschieben, egal ob er ankommt | ❌ **100 % Fehler** |

> Hier bleibt man am leichtesten hängen: manche BLE-Bibliotheken benutzen standardmäßig den Modus „ohne Antwort“ (bessere Performance),
> bei dieser Waage wirft jeder einzelne Write eine Exception. Wir haben es mit 8 Writes geprüft – alle fehlgeschlagen. [Praxis]

### 3.2 Der Empfangskasten FFB2: zuerst muss „abonniert“ werden

Das Smartphone kann nicht einfach warten, bis die Waage Daten sendet, sondern muss zuerst einmal `setNotifyValue(true)` aufrufen (abonnieren).
Nach dem Abonnieren wird bei jedem Paket der Waage die „Callback-Funktion“ des Smartphones einmal aufgerufen, als Argument kommen 20 Bytes.

```dart
// Vorgehen mit flutter_blue_plus
await char.setNotifyValue(true);
char.onValueReceived.listen((data) {
  // data ist eine Uint8List der Länge 20
});
```

### 3.3 Geräteinformationen, die man nebenbei lesen kann

Die Waage stellt zusätzlich den Standardinformationsdienst `0x180A` (Device Information) bereit; daraus lässt sich lesen:

| Feld | Wert |
| --- | --- |
| Hersteller | ICOMON |
| Modell | FG2313UWB-D |
| Firmware-Version | 1.2.3 |
| Software-Version | 1.3.0 |

⚠️ **Nicht die Akkustand-Charakteristik `0x2A19` lesen** – diese Waage hat diesen Standarddienst überhaupt nicht;
was man dort liest, ist Müll (etwa 77 %). Der echte Akkustand steckt an einer anderen Stelle im Datenpaket (siehe §6.3). [Praxis]
---

## 4. Schritt drei: das Format des „Umschlags“ verstehen

Alle Nachrichten zwischen Smartphone und Waage sind **fest 20 Byte** – kein Byte mehr, kein Byte weniger.
Man kann sich das als genormten Umschlag vorstellen, auf dem ein paar feste Felder aufgedruckt sind:

```
Byteposition:  [0]  [1]   [2] [3] [4] ... [17]   [18]   [19]
          ┌────┬───────┬────────────────────────┬──────────────┬───────────┐
Inhalt:   │ AC │  Typ  │        Nutzlast        │     Ende     │ Prüfsumme │
          │    │       │       (16 Bytes)       │   (Befehl)   │           │
          └────┴───────┴────────────────────────┴──────────────┴───────────┘
```

| Position | Bezeichnung | Erläuterung |
| --- | --- | --- |
| `[0]` | Startkennung | fest `0xAC`, entspricht dem Stempel „Luftpost“ auf dem Umschlag |
| `[1]` | Gerätetyp | das Smartphone sendet `0x27`, die Waage antwortet mit `0x29` (beide melden ihre eigene „Identität“) |
| `[2..17]` | Nutzlast | 16 Byte, hier stehen die eigentlichen Befehle und Daten |
| `[18]` | Ende | Befehlsnummer, hilft zu unterscheiden, um welchen Befehl es geht |
| `[19]` | Prüfsumme | verhindert, dass Daten auf dem Übertragungsweg verfälscht werden |

### 4.1 Was eine Prüfsumme ist

Stell dir vor, du schickst einen Brief und schreibst auf die Klebekante des Umschlags eine Zahl: **„die Summe der Striche aller enthaltenen Zeichen“**.
Der Empfänger öffnet den Brief und zählt neu; passt es nicht zusammen, wurde der Brief unterwegs beschädigt.

Die Regel lautet hier:

```
Prüfsumme = (alle Bytes 2 bis 18 aufsummiert) & 0xFF
```

**Was bedeutet `& 0xFF`?**

Ein Byte kann höchstens 255 speichern. Die Summe kann weit über 255 liegen (etwa 2000).
`& 0xFF` heißt nichts anderes als „**nur die letzten 8 Binärstellen behalten**“, also „Rest bei Division durch 256“.

```
Beispiel: die Summe ergibt 2000
2000 = binär 11111010000   (11 Bit)
nur die letzten 8 Bit → 11010000 = 208
also wird als Prüfsumme 208 geschrieben (0xD0)
```

> ⚠️ Achtung, der Bereich ist `[2..18]` – **das Ende `[18]` gehört dazu, das Feld selbst `[19]` nicht**.
> Im Netz behaupten manche Dokumente, es werde „nur über die Nutzlast“ summiert; wer das so macht, scheitert dauerhaft. [Praxis, Byte für Byte geprüft]

### 4.2 Mehr als 16 Byte Nutzlast werden abgeschnitten

In der Frame-Aufbau-Funktion gibt es eine Kürzung: Feld 2 bis 17 sind 16 Plätze, alles darüber wird verworfen.
Die **Nutzlast eines einzelnen Befehls umfasst also höchstens 16 Byte**; passt es nicht hinein, muss aufgeteilt werden.

---

## 5. Schritt vier: 8 Befehle in fester Reihenfolge senden (Handshake)

Nach dem Verbinden **darf man nicht direkt nach Daten fragen**, zuerst muss man sich „anmelden“. Die Waage will erst wissen, wer du bist, bevor sie arbeitet.

Die Reihenfolge ist fest, zwischen den Befehlen liegen **400 Millisekunden** (sendet man zu schnell, kommt die Gegenseite nicht mit und Pakete gehen verloren).

| # | Befehl | Wirkung | Nutzlast (16 Bytes) |
| --- | --- | --- | --- |
| 1 | `08` Zeitabgleich | sagt der Waage „wie spät es ist“ | `08` + Unix-Sekunden (4 Bytes) + Zeitzone |
| 2 | `01` Benutzer | sagt der Waage „wer ich bin“ | `01 00 01` + Größe + Gewicht (2 Bytes ×100) + Alter + Geschlecht |
| 3 | `02` Slots | überschreibt die in der Waage gespeicherte Benutzerkonfiguration | zwei Gruppen zu je 7 Bytes (Slot 1 / Slot 2) |
| 4 | `D0` vollständiger Handshake | meldet alle Informationen auf einmal erneut | Zeit + Zeitzone + Einheit + Slot + Größe + Gewicht + Alter + Geschlecht + Ziel + `03 00` |
| 5 | `06` Abfrage | fragt die Konfiguration ab | `06` |
| 6 | `04 D6` | erhöht die Frequenz der Echtzeitpakete | `04 D6` |
| 7 | `04 D8` | fordert die Verlaufsdatensätze an (erstes Mal) | `04 D8` |
| 8 | `04 D8` | fordert die Verlaufsdatensätze an (zweites Mal) | `04 D8` |

### 5.1 Ein paar Details, bei denen man sich leicht verrechnet

**① Wie die Zeitzone berechnet wird**

```
utcQuarters = (UTC-Offset in Minuten ÷ 15) & 0xFF
```

Warum in 15-Minuten-Schritten? Weil es auf der Welt Zeitzonen mit Verschiebungen wie UTC+5:30 oder UTC+5:45 gibt, also halbe bzw. viertel Stunden.
Mit 15 Minuten als kleinster Einheit lassen sich alle Zeitzonen gerade noch darstellen. China ist UTC+8 → 480 Minuten → 480÷15 = **32**.

**② Für das Geschlecht gibt es nur zwei Werte**

```
männlich = 1    weiblich = 2
```

⚠️ Das ist nicht das in der Programmierung übliche „0/1“, sondern **1 und 2**. Ein Fehler hier führt zur falschen Körperfettformel, und das Ergebnis weicht um den Faktor zwei ab.

**③ Das Gewicht wird mit 100 multipliziert gespeichert**

Das Gewicht belegt 2 Bytes (maximal 65535), die Einheit ist „Hundertstel Kilogramm“.
55.75 kg wird also als `5575` = hexadezimal `0x16 0b` gespeichert.

**④ Die Größe wird nur als ganze Zahl gespeichert**

Die Größe belegt nur 1 Byte (maximal 255 cm), aus 165.4 cm wird daher **165**.

**⑤ Woher diese Werte kommen**

```
Gewicht = Gewicht aus dem Mitgliedsprofil → letzter Messdatensatz → gibt es nichts, 60 kg als Rückfallwert
Zielgewicht = vom Nutzer eingestellt → nicht gesetzt: „Referenzgewicht × 0.75“
```

### 5.2 Die Besonderheit des dritten Befehls `02`

Die offizielle Ant-App sendet diesen Befehl **nur beim „Gerät entkoppeln“**; seine Aufgabe ist es, die in der Waage gespeicherten Benutzerslots zu löschen.

Wir senden ihn **bei jeder Verbindung** – weil wir Waagen mit Resten alter Konfiguration angetroffen haben (die Größe hing bei 111 cm fest und ließ sich partout nicht ändern);
ein erneutes Senden überschreibt sie. Das ist ein experimentelles Vorgehen, die Nebenwirkungen stehen in §8. [HCI]

---

## 6. Schritt fünf: die Antworten der Waage lesen

Die Pakete der Waage sind ebenfalls 20 Byte; `[0]` ist `0xAC`, aber `[1]` ist jetzt `0x29`.
Welcher Pakettyp vorliegt, steckt in `[2]`:

| Wert von `[2]` | Pakettyp | Wann er auftritt |
| --- | --- | --- |
| `0x00` | Echtzeitpaket | während der Messung, alle 100~150 ms eines |
| `0x80` | Stabilitätspaket | das Gewicht hat sich stabilisiert |
| `0x02` | **Sperrpaket** | Messung abgeschlossen, mit finaler Impedanz (am wichtigsten) |
| `0x01` | Verlaufspaket | nach dem Verbinden schiebt die Waage nicht synchronisierte alte Datensätze nach |
| `0x06` | Konfigurationsblock | Antwort auf die `06`-Abfrage, 5 Pakete hintereinander |

### 6.1 Wie das Gewicht aus 3 Bytes berechnet wird

Das ist die Stelle, die man im ganzen Text am dringendsten verstehen muss. Zuerst die Formel des Echtzeitpakets (**Little-Endian-Schreibweise**):

```
Gewicht (g) = ((d[3] - 0x68) × 65536 + d[4] × 256 + d[5]) ÷ 1000
```

**Warum mit 65536 und 256 multipliziert wird**

Weil ein Byte nur 0~255 speichern kann und ein paar hundert Kilogramm (in Gramm einige hunderttausend) nicht hineinpassen.
Deshalb werden **drei Bytes zu einer „großen Zahl“ zusammengesetzt**:

```
Stell dir die drei Bytes als drei Drehknöpfe vor:
  Knopf 1 (d[3]): pro Raster = +65536
  Knopf 2 (d[4]): pro Raster = +256
  Knopf 3 (d[5]): pro Raster = +1

Das ist wie im Dezimalsystem: Hunderter ×100, Zehner ×10, Einer ×1
nur dass diese drei „Stellen“ zur Basis 256 zählen, die Gewichte also 65536 / 256 / 1 sind
```

**Wozu dient `- 0x68`?**

Der werksseitige „Nullpunkt“ der Waage ist nicht 0, sondern `0x68` (dezimal 104). Das entspricht einer alten Personenwaage, deren Zeiger von Anfang an nicht auf Null steht:
dieser Versatz muss erst abgezogen werden.

**`÷ 1000`**: Weil das berechnete Ergebnis in Gramm vorliegt und in Kilogramm umgerechnet werden muss.

### 6.2 Warum das Gewicht im Sperrpaket eine andere Position und Schreibweise hat

Im Sperrpaket steht das Gewicht in **`d[10..12]`** (nicht in `d[3..5]`), und die Formel lautet jetzt:

```
Gewicht (g) = ((d[10]<<16 | d[11]<<8 | d[12]) - 0x680000) ÷ 1000
```

**Was sind `<<16` und `|`?**

`<<16` heißt „16 Stellen nach links schieben“, also **× 65536**; `|` heißt „die drei Teile zusammenfügen“.
Dieser Ausdruck ist im Kern **derselbe Algorithmus** wie oben, nur in einer „programmierigeren“ Schreibweise:

```
Schreibweise A (Grundschule)   Schreibweise B (Bitoperationen)
d[10] × 65536                 d[10] << 16
d[11] × 256                   d[11] << 8
d[12] × 1                     d[12]
alle drei addieren            alle drei mit | zusammenfügen
```

⚠️ Aber **der Versatz ist ein anderer**: hier `0x680000` (nicht `0x68`).
Weil die Zahl insgesamt um den Faktor 65536 vergrößert wurde, muss der Versatz mitwachsen.

**Vollständiges Beispiel** (ein Paket, das wir auf echter Hardware mitgeschnitten haben):

```
Rohpaket: ac 29 02 00 01 ae 01 83 01 80 68 d9 c6 ...
                                        └──┬──┘
                                   drei Gewichtsbytes

d[10]=0x68  d[11]=0xD9  d[12]=0xC6
zusammengesetzt: 0x68d9c6 = 6,871,494
Versatz abziehen: 6,871,494 - 0x680000(6,815,744) = 55,750
durch 1000 teilen: 55,750 ÷ 1000 = 55.75

→ Gewicht 55.75 kg ✅

Impedanz im selben Paket:
Impedanz1 = (d[4]<<8 | d[5]) = (0x01<<8 | 0xae) = 256 + 174 = 430 Ω
Impedanz2 = (d[6]<<8 | d[7]) = (0x01<<8 | 0x83) = 256 + 131 = 387 Ω
```

### 6.3 Wo der Akkustand steckt

**Es gibt keinen Standarddienst für die Batterie** (schon in §3.3 erwähnt). Der echte Akkustand steht in den **unteren 7 Bit** von `d[11]` im Echtzeitpaket:

```
Akkustand = d[11] & 0x7F
```

`& 0x7F` = „nur die unteren 7 Bit behalten“ (das höchste Bit gilt als Statusflag und zählt nicht zum Akkustand).

⚠️ **Zwei Fallen**:
1. Während der Messung kann `d[11]` zu `0x64` (=100) werden; das ist das Statusflag „Messung abgeschlossen“ und **nicht der Akkustand**, es muss ausgeschlossen werden
2. Der Akkustand dieser Waage liegt dauerhaft bei etwa **10 %** (Modalwert über 915 Paketmitschnitte) – sie ist nicht defekt

### 6.4 Verlaufspaket (`0x01`)

Sobald die Verbindung steht, schiebt die Waage automatisch alle alten, „noch nicht synchronisierten“ Datensätze nach; jeder davon umfasst ebenfalls 20 Bytes:

```
Zeit      = d[3..6]   (Unix-Zeitstempel, 4 Bytes, Big-Endian)
Gewicht   = ((d[8]<<16 | d[9]<<8 | d[10]) - 0x680000) / 1000
Impedanz1 = (d[11]<<8 | d[12])
Impedanz2 = (d[13]<<8 | d[14])
```

**Auslösebedingung** (das ist entscheidend):

```
Nachdem „08 Zeitabgleich + 01 Benutzer + D0 vollständiger Handshake“ geschrieben wurde, schiebt die Waage automatisch alle nicht synchronisierten Datensätze nach,
04D8 ist dafür nicht erforderlich (wer es sendet, ist auf der sichereren Seite).
```

Nachdem sie fertig ist, markiert die Waage diese Datensätze intern als „synchronisiert“ und **schiebt sie danach nicht mehr nach**, bis eine neue Messung entsteht.
Sind in der Waage von Anfang an keine Datensätze vorhanden, bleibt es nach dem Verbinden völlig still – das ist normal und kein Defekt.

⚠️ **Derselbe Zeitstempel kann dreimal ankommen** (Bluetooth stellt Pakete mehrfach zu); es muss dedupliziert werden.
Unser Vorgehen: aus `Zeitstempel_Gewicht` einen eindeutigen Key bilden und darüber entscheiden.

### 6.5 Wie man erkennt, in welchem Messschritt man gerade ist

```
0x02 empfangen                         → fertig (finale Impedanz liegt vor)
0x00 oder 0x80 empfangen, d[11] >= 100 → Impedanzmessung läuft
alles andere                           → Wiegevorgang läuft
```

**Der wichtigste Satz zur Impedanz**:

> Die Impedanz hängt ausschließlich von den **physikalischen Bedingungen** ab. Ein Wert entsteht nur, wenn beide Füße barfuß auf den vier Elektrodenflächen stehen und so einen Körperstromkreis bilden;
> ein Fuß, Socken oder zu trockene Fußsohlen ergeben zwangsläufig eine Impedanz von **0** – kein Befehl kann daran etwas ändern. [A/B-Vergleich, Praxis]
>
> Die im Netz verbreitete Behauptung, `04 D6` schalte die Impedanzmessung ein, ist **falsch** – der Befehl sorgt nur für mehr Echtzeitpakete (26→77 Stück).
> Die eigentlichen Impedanzwerte stehen ausschließlich in den Bytes 4~8 des `0x02`-Sperrpakets.
---

## 7. Wie eine vollständige Messung von Anfang bis Ende aussieht

```
Zeitachse
│
├─ Der Nutzer steigt auf die Waage, das Display leuchtet auf
│
├─ Waage: im Advertising ruft sie „ich bin AFU-WL-TZ-A1“    —— alle 999ms, ohne Pause
│
├─ Smartphone: scannt sie → verbindet über die MAC → abonniert FFB2
│
├─ Smartphone: sendet 8 Befehle in fester Reihenfolge (je 400ms Abstand)    —— ca. 3.2 Sekunden
│    08 Zeitabgleich → 01 Benutzer → 02 Slots → D0 Handshake
│    → 06 Abfrage → 04D6 → 04D8 → 04D8
│
├─ Waage: beginnt 0x00 Echtzeitpakete zu senden (alle 100~150ms)    —— die Zahl springt
├─ Waage: Gewicht stabil → sendet 0x80 Stabilitätspaket
├─ Waage: wechselt in die Impedanzmessung → d[11] >= 100
├─ Waage: Messung fertig → sendet 0x02 Sperrpaket im Kreis (ca. 6 Sekunden) —— mit finaler Impedanz
│
├─ Smartphone: wertet das Sperrpaket aus → berechnet Gewicht + Körperfett → speichert in die Datenbank
│
├─ Waage: gibt es noch nicht synchronisierte alte Datensätze → sendet 0x01 Verlaufspakete
│         markiert sie danach intern als „synchronisiert“
│
└─ Ende (die Waage geht nach einer Weile von selbst in den Ruhezustand)
```

**Warum das Sperrpaket 6 Sekunden lang wiederholt gesendet wird**? Weil Bluetooth Pakete verlieren kann; mehrfaches Senden stellt sicher, dass das Smartphone sie auf jeden Fall erhält.
Ein einziges empfangenes Paket genügt, danach kann gestoppt werden.

---

## 8. Fallstricke, in die wir tatsächlich getappt sind

Dieser Abschnitt ist der wertvollste Teil des Dokuments – **keines der vier Reverse-Engineering-Dokumente im Netz erwähnt das**.

### Fallstrick 1 · Ein Write geht nur im „Einschreiben“-Modus

`FFB1` unterstützt nur Writes mit Antwort. Im Modus ohne Antwort wird **zu 100 % eine Exception geworfen**.
(vitaloop nutzt Kotlin, wo standardmäßig mit Antwort geschrieben wird – deshalb lief es dort; manche JS-/Dart-Bibliotheken schreiben standardmäßig ohne Antwort.)

### Fallstrick 2 · Die „denylist“ von Android 12 schluckt Advertising still

Trägt die Scan-Berechtigung das Flag `neverForLocation`, stuft das System das Advertising dieser Waage als Beacon ein und filtert es heraus.
Alle Berechtigungen erteilt, Bluetooth eingeschaltet, und trotzdem wird nichts gefunden; in logcat steht nur eine Zeile: `Skipping data matching denylist`.

### Fallstrick 3 · Auf MIUI unterscheiden sich Bluetooth-Bibliotheken um den Faktor 400

Gleiches Smartphone, gleiche Waage:

| Bibliothek | Dauer des Scans |
| --- | --- |
| `flutter_blue_plus` | **unter 1 Sekunde** |
| `react-native-ble-plx` | **etwa 7 Minuten** |

Das ist ein Unterschied in der **Kapselungsschicht der Bibliotheken** und hat nichts mit Berechtigungen zu tun. Das war auch der unmittelbare Grund, warum wir am Ende von RN auf Flutter umgeschrieben haben.

### Fallstrick 4 · Ein Scan-Filter per UUID lässt die Waage durchfallen

`startScan([ffb0-UUID])` liefert auf MIUI auch nach 4 Minuten kein Ergebnis; vollständiger Scan plus eigene Filterung im Callback liefern es in Sekunden.

### Fallstrick 5 · Direkt nach dem Verbinden meldet der Status einen „Scheinabbruch“

Im Moment des GATT-Aufbaus meldet der Verbindungsstatus kurz fälschlich `disconnected`.
Hängt man direkt einen Timer „bei Trennung neu verbinden“ daran, wird der **Handshake zweimal** durchgeführt – die Waage wertet das als neue Synchronisierungssitzung und schiebt den Verlauf erneut nach.

Die Lösung: vor dem Wiederverbinden erneut `isConnected` prüfen und eine Nebenläufigkeitssperre „Verbindung wird gerade aufgebaut“ ergänzen.

### Fallstrick 6 · Die Schwelle für „hat sich das Gewicht geändert“ darf nicht zu groß sein

Wir wollten das neueste Gewicht ins Mitgliedsprofil zurückschreiben und mussten dafür entscheiden, „ob sich der Wert geändert hat“.

| Schwelle | Folge |
| --- | --- |
| 1 kg | ein Plus von 0.1kg gilt als „unverändert“, es wird nie aktualisiert |
| 0.05 kg | Fließkomma-Genauigkeit: 55.85 − 55.80 ergibt 0.0499…, wird also weiterhin abgewiesen |
| **0.001 kg** | ✅ schließlich übernommen |

### Fallstrick 7 · Für Männer und Frauen gelten völlig verschiedene Körperfettformeln

```
männlich = Deurenberg-Formel: 1.10×BMI + 0.23×Alter − 11.22   (Impedanz spielt keine Rolle!)
weiblich = Segal-Formel: braucht die Impedanz, beide Impedanzwerte werden zu (i1+i2)×0.675 zusammengefasst
```

**Noch etwas, das man wissen sollte**: der auf dem Display der Waage angezeigte Körperfettanteil und der in der App berechnete **weichen um einige Zehntel Prozentpunkte voneinander ab**.
Denn die Waage nutzt einen proprietären Herstelleralgorithmus (nicht offengelegt), die App dagegen die oben genannten Formeln aus öffentlich zugänglichen Fachartikeln.

Beim **BMI stimmen beide immer überein** (der BMI hängt nur von Gewicht und Größe ab, dort gibt es keinen algorithmischen Spielraum).

Setzt man das falsche Geschlecht ein, weicht das Ergebnis fast um den Faktor zwei ab. Ein Beispiel (55.75kg / 163cm / 24 Jahre / Impedanz 430+387):

| verwendete Formel | berechneter Körperfettanteil |
| --- | --- |
| Männerformel | 17.4% |
| Frauenformel | 22.2% |

### Fallstrick 8 · In der Waage steckt „die Benutzerkonfiguration vom letzten Mal“

Die Waage behält den zuletzt geschriebenen Benutzerslot. Ist das Profil in der App geändert, in der Waage aber noch alt,
zeigt das Waagendisplay einen deutlich falschen Körperfettwert. Das ist der Grund, warum wir bei jeder Verbindung `02` senden und überschreiben.

### Fallstrick 9 · Der Akkustand ist nicht 77 %, sondern 10 %

| Quelle | Anzeige | echt oder falsch |
| --- | --- | --- |
| Standarddienst für Batterie `0x2A19` | 77% | ❌ Müllwert (diesen Dienst gibt es überhaupt nicht) |
| Echtzeitpaket `d[11] & 0x7F` | 10% | ✅ echter Wert (Modalwert über 915 Paketmitschnitte) |

### Fallstrick 10 · Die Waage kennt keine „Datensätze löschen“-Funktion

Wir haben alle 29 offiziellen Schreibbefehle durchgesehen: **es gibt keinen einzigen Lösch- oder Leerungsbefehl**.

Das bedeutet: sobald die Waage einen Datensatz als „synchronisiert“ markiert hat, bekommt ihn keine App mehr.
**Was die App nicht speichert, ist endgültig verloren**. Also während der Verbindung auf keinen Fall den Prozess abwürgen.

---

## 9. Abweichungen gegenüber den vier Reverse-Engineering-Dokumenten im Netz

Wir haben fünf Open-Source-Projekte herangezogen, aber es gibt nicht wenige Stellen, an denen **bloßes Nachbauen schiefgeht**.
Dieser Abschnitt listet die Abweichungen zwischen unseren Messergebnissen und den Aussagen der Dokumente, damit Nachfolgende weniger Umwege brauchen.

### 9.1 Aussagen der Dokumente vs. Messergebnisse

| # | Was das Dokument sagt | Was die Messung ergibt | Beleg |
| --- | --- | --- | --- |
| 1 | [AF] das Gewicht sei ein vollständiges 32-Bit-Feld, mit `& 0x3FFFF` gestaffelt | Echtzeit- und Stabilitätspaket nutzen `((d[3]-0x68)×65536+d[4]×256+d[5])/1000`; **im Sperrpaket steht das Gewicht in d[10:13]**, die Positionen sind also unterschiedlich | 55.75kg über die gesamte Kette geprüft |
| 2 | [AF] im Ruhezustand sende die Waage nicht, sie müsse erst durch Betreten aufgeweckt werden | Diese Waage **sendet auch ohne leuchtendes Display** (999ms); nRF findet sie in 2 Sekunden, der Prüfstand in 84ms | nRF + Kommunikationsprotokoll |
| 3 | [AF] das Profilpaket werde alle 15 Sekunden neu gesendet, ein Heartbeat sei nötig | **Ein Heartbeat ist nicht erforderlich**; auch ohne ihn kommt die Impedanz stabil | ohne Heartbeat im Test unauffällig |
| 4 | [VA] beim Handshake weight/target mit 0 füllen | **Echte Werte** sind besser, dann stimmt der Slot in der Waage mit dem Profil überein | Messprotokoll |
| 5 | [VA] ein einziger `D0`-Handshake genüge | Ohne den `01`-Benutzerbefehl **wird die Impedanz nicht ausgelöst**; die vollständige 8er-Sequenz ist am stabilsten | Vorher-nachher-Vergleich |
| 6 | [WT] die Payload der ServiceData trage das Präfix `AC27` | Payload = **MAC, 6 Bytes (umgekehrte Reihenfolge) + 01**, ohne Präfix | Rohbytes geprüft |
| 7 | [WT] der `D6`-Befehl sei die Quelle der Impedanz | `D6` erzeugt nur mehr Echtzeitpakete (26→77 Stück), **die finale Impedanz steht im `0x02`-Paket d[4:8]** | A/B-Vergleich |
| 8 | [WT/HCI] Prüfsumme = Summe der Nutzlast | genau **`sum(frame[2..18]) & 0xFF`** (**einschließlich Ende [18]**) | Byte für Byte geprüft |

### 9.2 Was in keinem der vier Dokumente steht und wir selbst gefunden haben

1. `FFB1` **unterstützt nur Writes mit Antwort** (siehe Fallstrick 1)
2. `neverForLocation` unter Android 12 führt dazu, dass Advertising von der denylist gefiltert wird (Fallstrick 2)
3. Auf MIUI unterscheiden sich zwei Bluetooth-Bibliotheken um den Faktor 400 (Fallstrick 3)
4. UUID-Vorfilterung lässt die Waage durchfallen (Fallstrick 4)
5. Statusflattern im Moment des Verbindens führt zum doppelten Handshake (Fallstrick 5)
6. Die Schwelle für das Zurückschreiben ins Profil muss bis auf 0.001kg klein sein (Fallstrick 6)
7. Die BIA-Formeln für Männer und Frauen sind völlig verschieden (Fallstrick 7)
8. Die tatsächliche Semantik des `02`-Befehls ist „zwei Benutzerslots schreiben, je 7 Bytes“
9. Der echte Akkustand liegt in den unteren 7 Bit von `d[11]`, und diese Waage hat keinen `0x2A19`-Dienst (Fallstrick 9)
10. Die Markierung „synchronisiert“ gilt für **jede** App, und weil es keinen Löschbefehl gibt, bedeutet Nichtspeichern endgültigen Verlust (Fallstrick 10)

### 9.3 Bewusste Unterschiede zur offiziellen Ant-App

| So macht es die offizielle App | So machen wir es | Warum |
| --- | --- | --- |
| `02` nur beim Entkoppeln senden | bei jeder Verbindung senden (experimentell) | überschreibt Reste alter Benutzerkonfiguration in der Waage (hing einmal bei 111cm fest) |
| Profilpaket alle 15 Sekunden neu senden (Heartbeat) | nicht senden | laut Messung nicht erforderlich, spart Strom |
| `04D8` einmal senden | zweimal senden | zur Sicherheit; keine Nebenwirkungen beobachtet |
| iOS-Client | Android / Flutter | andere Scan-Strategie (siehe Fallstrick 3 und 4) |

### 9.4 Noch nicht verifizierte Fragen

- [ ] langfristige Nebenwirkungen davon, `02` bei jeder Verbindung zu senden (sollte sich zeigen, dass der Verlauf immer wieder neu nachgeschoben wird, zurück auf „nur beim Entkoppeln“)
- [ ] ob `deviceType` `0x29` bei manchen Firmware-Versionen zwingend ist (vitaloop funktioniert mit 0x29 ebenfalls)
- [ ] ob die Abweichung von 0.4 Prozentpunkten zum Waagendisplay über das Gewicht hinweg konstant ist
- [ ] ob ein 15-Sekunden-Heartbeat bei sehr langen Verbindungen (>10 Minuten) nötig ist

---

## 10. Wie man selbst debuggt

### 10.1 Das Kommunikationsprotokoll in der App öffnen

Der Einstieg ins Log ist standardmäßig versteckt (ein Easter Egg):

> **Einstellungen → Über → 7-mal hintereinander auf die Versionsnummer tippen**

Nach dem Freischalten erscheint oben rechts auf der Messseite die Schaltfläche „Kommunikation N“; dort sind die Rohbytes jedes Sende- und Empfangsvorgangs zu sehen.

### 10.2 Die Logdatei wird automatisch geschrieben

Während der Verbindung wird alle 3 Sekunden geschrieben (beim Trennen zusätzlich einmal erzwungen):

```
/storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

```bash
adb pull /storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

Format: `Zeit Richtung (→ gesendet / ← empfangen) 20 Rohbytes [Befehlsname oder Pakettyp]`

### 10.3 Stichwörter auf Systemebene

| Symptom | Stichwort in logcat |
| --- | --- |
| Scan wird vom System gefiltert | `Skipping data matching denylist` |
| Fortschrittspunkte beim Scan | `SCAN_STEP` |
| Write schlägt fehl | `PlatformException` + `not supported` |

### 10.4 Mit nRF Connect gegenprüfen

Wenn das selbst geschriebene Programm sich seltsam verhält, zuerst einmal mit **nRF Connect** (dem gängigen BLE-Debug-Werkzeug auf dem Smartphone) manuell verbinden
und prüfen, ob Daten normal ankommen. Klappt es auch mit nRF nicht, liegt ein physikalisches bzw. Umgebungsproblem vor (Display nicht aufgeweckt, zu weit weg, Akku zu schwach).

---

## 11. Referenzen

Dieses Protokoll ist nicht aus der Luft gegriffen; herangezogen wurden vor allem diese öffentlichen Reverse-Engineering-Ergebnisse:

| Projekt | Sprache/Plattform | Beitrag |
| --- | --- | --- |
| [Fatpandac/AFUScale](https://github.com/Fatpandac/AFUScale) | iOS / Swift | die früheste Protokoll-Rückentwicklung, Grundlage der Befehlssequenz |
| [Mzdyl/ant-afu-welland-scale](https://github.com/Mzdyl/ant-afu-welland-scale) | Python | Frame-Format und Gewichtskodierung |
| [monkey-wenjun/vitaloop-app](https://github.com/monkey-wenjun/vitaloop-app) | Android / Kotlin | Einzel-Handshake-Modus, Verwendung von `deviceType` |
| [Xuan-lprk/WeighTrace](https://github.com/Xuan-lprk/WeighTrace) | Dokumentation | Struktur der Advertising-ServiceData, Scan-Strategie |
| [ZeroOneCN/AntAF](https://github.com/ZeroOneCN/AntAF) | Dokumentation | Erläuterung der 32-Bit-Gewichtskodierung, Heartbeat des Profilpakets |

Zusätzlich dienten HCI-Mitschnitte des eigenen Geräts (`ant_cleanup.log`, `unbind_official.log`) als Belegquelle für den `02`-Befehl.

---

## Anhang: ein Spickzettel für alle, die es selbst implementieren wollen

```
1. Scan: vollständig scannen, im Callback nach „Name enthält AFU-WL / ServiceData ist 27AC / Dienste enthalten FFB0“ filtern
2. MAC holen: die 6 Bytes in den ServiceData, umgekehrte Reihenfolge
3. verbinden → Dienst FFB0 holen
4. Benachrichtigung von FFB2 abonnieren (setNotifyValue(true))
5. 8 Befehle nach FFB1 schreiben, je 400ms Abstand, alle im Modus „mit Antwort“
6. auf die Callbacks von FFB2 hören, anhand [2] den Pakettyp bestimmen
7. 0x02-Paket: Gewicht in d[10:13], Impedanz in d[4:8], beide erst Versatz abziehen, dann durch 1000 teilen
8. sobald 0x02 ankommt, ist man fertig – in die Datenbank speichern
```

**Die drei Stellen, an denen es am leichtesten schiefgeht**: der Write-Modus (Antwort ist Pflicht), der Prüfsummenbereich (einschließlich [18]) und der Gewichtsversatz (`0x68` vs `0x680000`).