# Algorithmus der Körperzusammensetzung · Offene Dokumentation

> **Warum das offengelegt wird**: bei einer Zahl wie dem Körperfettanteil gilt: sagt man dem Nutzer nicht, wie sie berechnet wird,
> dann kann er sie nur „glauben“ – und so sollten Gesundheitsdaten nicht funktionieren.
>
> Dieses Dokument legt **jede einzelne Formelzeile** aus `lib/core/bodycomp.dart` offen dar
> und kennzeichnet ausdrücklich, was die **Originalformel aus einer öffentlichen Veröffentlichung** ist und was ein von uns **aus Messungen rückgerechneter Kalibrierkoeffizient**.
>
> **Fazit in einem Satz**: Diese Waage **misst kein Fett direkt**. Sie misst einen **Widerstand**,
> und der Fettanteil wird daraus (bzw. aus Größe, Gewicht und Alter) **geschätzt**.

---

## 1. Zuerst das Prinzip: warum man aus einem Widerstand auf Fett schließen kann

### 1.1 Der Körper leitet unterschiedlich gut

| Gewebe | Wassergehalt | Leitfähigkeit |
| --- | --- | --- |
| Muskeln, Blut, innere Organe | hoch (etwa 70~75%) | **gut** (enthält Elektrolyte, wie Salzwasser) |
| Fett | niedrig (etwa 10~20%) | **schlecht** (wie Kunststoff) |
| Knochen | niedrig | schlecht |

Also: **bei gleichem Gewicht hat ein Mensch mit mehr Fett einen größeren Widerstand**. Das ist die gesamte Grundlage der BIA (bioelektrische Impedanzanalyse).

### 1.2 Wie die Waage misst

```
       Zwei Füße, unter jedem Fuß zwei Elektrodenflächen (insgesamt 4)

linker Fuß vorn     ─┐              ┌─ rechter Fuß vorn
                     │  ╭────────╮  │
                     │  │ Waage  │  │
                     │  ╰────────╯  │
linker Fuß hinten   ─┘              └─ rechter Fuß hinten

Strompfad: die Elektrode des einen Fußes gibt einen extrem schwachen Wechselstrom ab (<1mA, nicht spürbar)
          → über Unterschenkel, Oberschenkel, Becken → zurück über die Elektrode des anderen Fußes
          → dazwischen wird der Spannungsabfall gemessen → über das Ohmsche Gesetz ergibt sich die Impedanz (Ω)
```

**Entscheidend**: Nur wenn **beide Füße barfuß gleichzeitig** auf den vier Elektroden stehen, schließt sich der Stromkreis.
Ein Fuß, Socken oder zu trockene Fußsohlen → die gemessene Impedanz ist **0**, und dann lässt sich kein Körperfettanteil berechnen.

> Das lässt sich nicht per Software steuern. Jede Behauptung, „ein bestimmter Befehl schalte die Impedanz ein“, ist falsch –
> wir haben das in einem kontrollierten A/B-Versuch geprüft (siehe [Protokolldokument](PROTOCOL.md), Fallstrick 7).

### 1.3 Die Rohdaten, die diese Waage liefert

Im Sperrpaket am Ende der Messung liefert die Waage **zwei ADC-Werte** (aufzufassen als Rohwerte zweier Messkanäle, links und rechts):

```
Impedanz1 = (d[4] << 8 | d[5])   ← Einheit Ohm
Impedanz2 = (d[6] << 8 | d[7])
```

Der normale Bereich liegt bei etwa **100 ~ 1500 Ω**. Werte außerhalb dieses Bereichs gelten grundsätzlich als ungültig.

---

## 2. Schritt eins: die beiden Impedanzwerte zu einem zusammenfassen

Die Formeln aus der Fachliteratur akzeptieren nur **einen** Impedanzwert, die Waage liefert aber zwei. Unser Vorgehen:

```
Zusammengefasste Impedanz R = (Impedanz1 + Impedanz2) × 0.675
```

### Woher die 0.675 stammt

⚠️ **Dieser Koeffizient steht in keiner Veröffentlichung; wir haben ihn aus Messungen rückgerechnet**.

Vorgehen: Wir haben den Körperfettanteil genommen, den die offizielle Ant-Health-App im selben Moment anzeigte, und rückgerechnet, welches R die Formel zum Passen bringt.
Nach dem Fitten über mehrere Datensätze zeigte sich, dass etwa 0.675 stabil trifft (zum Beispiel 55.75kg + Impedanz [430, 387] → die offizielle App zeigt 22.2%).

**Warum es zwei ADC-Werte gibt**: vermutlich arbeitet ein Kanal mit 50kHz und der andere mit einer weiteren Frequenz (bei Multifrequenz-BIA üblich);
die Zusammenfassung beider Kanäle dient üblicherweise dazu, den Einfluss des Übergangswiderstands an den Kontaktflächen zu kompensieren. Der Hersteller hat das aber nicht offengelegt, unsere Deutung ist reine Vermutung.

### Prüfung auf Gültigkeit

```
Nur wenn die zusammengefasste Impedanz R zwischen 100 ~ 1500 Ω liegt, gilt sie als gültig
```

---

## 3. BMI (der einzige Kennwert ohne Schätzung)

```
BMI = Gewicht (kg) ÷ Größe (m)²
```

Beispiel: 55.75kg, 163cm → 55.75 ÷ 1.63² = **21.0**

**Der BMI enthält kein Geschlecht und kein Alter**. Das ist die Definition der Weltgesundheitsorganisation (WHO);
jede Software sollte denselben BMI liefern (solange Gewicht und Größe gleich sind).

Also: dass sich der BMI beim Umschalten des Geschlechts nicht ändert, ist **korrektes Verhalten** und kein Bug.

---

## 4. Körperfettanteil bei Männern: die Deurenberg-Formel (ohne Impedanz)

```
Körperfettanteil (%) = 1.10 × BMI + 0.23 × Alter − 11.22
```

**Quelle**: die 1991 von Deurenberg et al. veröffentlichte, um ethnische Korrektur ergänzte Formel (Fassung für die japanische Bevölkerung).
Das ist die **Originalformel aus einer öffentlichen Veröffentlichung**; wir setzen nur feste Koeffizienten ein und haben nichts verändert.

**Achtung: die Männerformel enthält keine Impedanz**. Das heißt, es genügen Größe, Gewicht und Alter;
selbst wenn die Elektroden keinen guten Kontakt haben und die Impedanz 0 ist, lässt sich der Körperfettanteil für Männer berechnen.

**Gegenprüfung in der Praxis**: Stichprobe Mann, 79.8kg → berechnet 25.4%, deckungsgleich mit der Anzeige der offiziellen App.

Modellkennung: `deurenberg_jp_male`

---

## 5. Körperfettanteil bei Frauen: die Segal-Formel (Impedanz zwingend erforderlich)

Für Frauen gilt eine andere Formel, die die Impedanz benötigt.

### 5.1 Zuerst die „fettfreie Masse“ (FFM, Fat-Free Mass)

```
FFM = Gewicht − Masse des Fetts    ← also die Summe aus Muskeln, Knochen, Wasser und inneren Organen
```

Die Segal-Formel liefert nicht direkt den Körperfettanteil, sondern schätzt zuerst die FFM und rechnet dann mit `100 × (Gewicht − FFM) ÷ Gewicht` zurück.

### 5.2 Zwei Zweige: zuerst 3C versuchen, sonst 3D

**Zweig A (3C-Gleichung, für Menschen mit Körperfett < 30%)**

```
FFM_A = 10.43485
      + 0.00064602 × Größe² (cm²)
      − 0.01397   × R (zusammengefasste Impedanz)
      + 0.42087   × Gewicht (kg)
```

Zuerst wird mit A gerechnet und daraus der Körperfettanteil zurückgerechnet; **liegt das Ergebnis < 30%, wird dieser Wert verwendet**.

**Zweig B (3D-Gleichung, für Menschen mit Körperfett ≥ 30%)**

```
FFM_B = 9.37938
      + 0.00091186 × Größe² (cm²)
      − 0.01466   × R
      + 0.29990   × Gewicht
      − 0.07012   × Alter
```

> Warum zwei Abschnitte? Weil die Segal-Formel von Haus aus zwei Regressionsgeraden sind, die für unterschiedliche Grade der Körperfülle gefittet wurden;
> bei kräftigeren Menschen unterschätzt die A-Gleichung die FFM systematisch. Das Zusammensetzen beider Abschnitte ist genau die Absicht der Veröffentlichung.

**Quelle**: die 1988 von Segal et al. in der *American Journal of Clinical Nutrition* veröffentlichte Formel.
Die Koeffizienten der Originalgleichung sind öffentlich, wir übernehmen sie unverändert.

**Achtung, Einheit der Größe**: In der Formel wird die Größe in **cm** eingesetzt, quadriert ergibt das cm² (etwa 163² = 26569).
Nicht m². Ein Fehler an dieser Stelle bedeutet einen Faktor 10000.

### 5.3 Klemmen auf Plausibilität

```
Die FFM wird auf 35% ~ 97% des Gewichts begrenzt
```

Das verhindert absurde Ergebnisse bei extremen Eingaben (zum Beispiel Impedanz 100Ω bei 30kg Gewicht).

**Gegenprüfung in der Praxis**: 55.75kg + Impedanz [430, 387] → zusammengefasste R = 551Ω → ergibt 22.2%, deckungsgleich mit der offiziellen App.

Modellkennung: `segal_3c_female_lt30` / `segal_3d_female_ge30`

### 5.4 Rückfalllösung für Frauen ohne Impedanz

```
Körperfettanteil (%) = 1.10 × BMI + 0.23 × Alter − 5.4
```

Das ist die **Frauenfassung** der Deurenberg-Formel (die Männerfassung endet auf −11.22, die Frauenfassung auf −5.4).
Vergleicht man mit der Männerformel, ergibt sich bei gleichem BMI und gleichem Alter für Frauen ein um **5.82 Prozentpunkte** höherer Wert –
was den physiologischen Tatsachen entspricht (der normale Körperfettanteil von Frauen liegt von Natur aus höher als der von Männern).

Modellkennung: `deurenberg_jp_female`

---

## 6. Abschließendes Klemmen

```
Körperfettanteil bei Männern auf 3% ~ 60% begrenzt
Körperfettanteil bei Frauen auf 8% ~ 60% begrenzt
```

Die Untergrenzen unterscheiden sich, weil ein Körperfettanteil unter 3% bei Männern physiologisch nahezu unmöglich ist (die Grenze im Wettkampf-Bodybuilding liegt bei etwa 4~5%),
während unter 8% bei Frauen das Hormonsystem beeinträchtigt wird. Über 60% ist im Grunde ein Messfehler.
---

## 7. Die übrigen Kennwerte: alle aus dem Körperfettanteil „abgeleitet“

⚠️ **Zuerst eine klare Feststellung**: Diese Waage misst nur zwei Größen, **Gewicht** und **Impedanz**.
Alle folgenden Kennwerte werden aus dem im vorigen Schritt berechneten Körperfettanteil **abgeleitet** und nicht eigens gemessen.

Für die Beurteilung ihrer Verlässlichkeit gilt daher diese Reihenfolge:

```
Verlässlichkeit: Gewicht (direkt gemessen) > BMI (reine Mathematik) > Körperfettanteil (Formelschätzung) > übrige Kennwerte (Ableitung zweiten Grades)
```

### 7.1 Fettmasse / fettfreie Masse

```
Fettmasse (kg)        = Gewicht × Körperfettanteil%
Fettfreie Masse (kg)  = Gewicht − Fettmasse
```

Reine Arithmetik, ohne zusätzliche Annahmen.

### 7.2 Knochenmasse: fester Prozentsatz

```
Knochenmasse% = männlich 4.5%   /   weiblich 4.0%
Knochenmasse (kg) = Gewicht × Knochenmasse%
```

⚠️ **Das ist eine fest eingetragene Konstante, kein Messwert**. Die echte Knochendichte lässt sich nur mit DEXA (Röntgen) messen;
die „Knochenmasse“ jeder Heim-Körperanalysewaage ist ein Schätzwert anhand von Bevölkerungsmittelwerten.
Unsere Werte stammen aus der Rückrechnung der Anzeigen der offiziellen App.

### 7.3 Muskelmasse: über eine Subtraktion zurückgerechnet

```
Muskelanteil% = 100 − Körperfett% − Knochenmasse%      (Ergebnis auf 20% ~ 95% begrenzt)
Muskelmasse (kg) = Gewicht × Muskelanteil%
```

Die Logik lautet „alles außer Fett und Knochen zählt als Muskel“.
Streng genommen enthält dieses „Übrige“ auch innere Organe, Wasser und Bindegewebe, aber die Hersteller ordnen es üblicherweise so zu.

### 7.4 Körperwasseranteil: fettfreie Masse × Koeffizient

```
Wasseranteil% = (100 − Körperfett%) × Koeffizient
Koeffizient: männlich 0.7185   /   weiblich 0.8475
(Ergebnis auf 25% ~ 80% begrenzt)
```

Physiologische Grundlage: fettfreies Gewebe (Muskeln, innere Organe) enthält etwa 73% Wasser, Fettgewebe etwa 10~20%.

⚠️ Der Frauenkoeffizient 0.8475 liegt deutlich über den üblichen 0.73; er ist das Ergebnis der Rückrechnung aus der offiziellen App.
Möglicherweise steckt dahinter ein eigenes Korrekturmodell des Herstellers; wir halten uns an die gemessenen Werte.

### 7.5 Protein: direkt als Anteil am Gewicht

```
Proteinmasse (kg) = Gewicht × Koeffizient
Koeffizient: männlich 0.163   /   weiblich 0.05
```

⚠️ **Hier gibt es einen Punkt, der benannt werden muss**:

| Quelle | Proteinanteil bei Männern | Proteinanteil bei Frauen |
| --- | --- | --- |
| physiologisches Grundwissen | etwa 16~18% | etwa 16~18% |
| unsere Implementierung | 0.163 (plausibel) | **0.05 (deutlich zu niedrig)** |

Der Wert 0.05 für Frauen ist aus den Anzeigen der offiziellen App zurückgerechnet,
**physiologisch ist diese Zahl kaum haltbar** – sie führt dazu, dass eine Frau mit 55.75kg nur 2.8kg Protein angezeigt bekommt,
während der tatsächliche Wert bei etwa 9kg liegen dürfte.

Wir behalten ihn bei, um „mit der offiziellen App übereinzustimmen“; wer physiologische Plausibilität höher gewichtet,
kann diesen Koeffizienten auf etwa 0.16 ändern. **Diesen Kennwert bitte mit Vorsicht zitieren.**

### 7.6 Skelettmuskelanteil: Muskelmasse × Koeffizient

```
Skelettmuskel% = Muskelanteil% × Koeffizient
Koeffizient: männlich 0.548   /   weiblich 0.651
(Ergebnis auf 10% ~ 70% begrenzt)
```

„Skelettmuskulatur“ ist der Teil der Muskulatur, der an den Knochen ansetzt (im Unterschied zum Herzmuskel und zur glatten Muskulatur).
Sie macht üblicherweise 55~65% der gesamten Muskulatur aus; die unterschiedlichen Koeffizienten für Männer und Frauen stammen aus der Rückrechnung von Messwerten.

### 7.7 Unterhautfett: Körperfett × Koeffizient

```
Unterhautfett% = Körperfett% × Koeffizient
Koeffizient: männlich 0.7165   /   weiblich 0.72
(Ergebnis auf 1% ~ Körperfett% begrenzt)
```

Das Körperfett teilt sich in „Unterhautfett“ (die Schicht, die man greifen kann) und „viszerales Fett“ (das die Organe umhüllt).
Der Koeffizient besagt, dass etwa 72% des Fetts unter der Haut liegen.

---

## 8. Der vollständige Rechenweg (Pseudocode)

```
Eingabe: Gewicht W (kg), Größe H (cm), Alter A, Geschlecht, Impedanz [i1, i2]

① BMI = W ÷ (H/100)²

② zusammengefasste Impedanz R = (i1 + i2) × 0.675
   liegt R nicht im Bereich 100~1500 → gilt als keine gültige Impedanz

③ Körperfettanteil bf berechnen:
   falls Geschlecht=männlich:
       bf = 1.10×BMI + 0.23×A − 11.22          ← Impedanz nicht nötig
   sonst (weiblich):
       falls R gültig:
           FFM_A = 10.43485 + 0.00064602×H² − 0.01397×R + 0.42087×W
           falls 100×(W−FFM_A)/W < 30  →  bf = 100×(W−FFM_A)/W
           sonst:
               FFM_B = 9.37938 + 0.00091186×H² − 0.01466×R + 0.29990×W − 0.07012×A
               bf = 100×(W−FFM_B)/W
           dabei wird die FFM auf W×0.35 ~ W×0.97 geklemmt
       sonst (keine Impedanz):
           bf = 1.10×BMI + 0.23×A − 5.4       ← Rückfallformel für Frauen

④ bf klemmen: männlich 3~60, weiblich 8~60

⑤ Ableitungen:
   Fettmasse         = W × bf/100
   fettfreie Masse   = W − Fettmasse
   Knochenmasse%     = männlich 4.5 / weiblich 4.0
   Muskelanteil%     = 100 − bf − Knochenmasse% (begrenzt 20~95)
   Wasseranteil%     = (100−bf) × (männlich 0.7185 / weiblich 0.8475) (begrenzt 25~80)
   Proteinmasse      = W × (männlich 0.163 / weiblich 0.05)
   Skelettmuskel%    = Muskelanteil% × (männlich 0.548 / weiblich 0.651) (begrenzt 10~70)
   Unterhautfett%    = bf × (männlich 0.7165 / weiblich 0.72) (begrenzt 1~bf)

⑥ alle Ausgaben auf 1 Nachkommastelle
```

Zugehöriger Code: `lib/core/bodycomp.dart` (76 Zeilen, keine externen Abhängigkeiten, eigenständig testbar)

---

---

## 8.5 Ausgabe in der Praxis: dieselben Daten, für Männer und für Frauen gerechnet

Mit dem Datensatz `55.75kg / 163cm / 24 Jahre / Impedanz 430+387` läuft der vollständige Algorithmus:

| Kennwert | Männerformel | Frauenformel | Differenz | Erläuterung |
| --- | --- | --- | --- | --- |
| BMI | **21.0** | **21.0** | **gleich** | reine Mathematik, ohne Geschlecht |
| Körperfettanteil | 17.4% | 22.2% | +4.8 pp | Männer und Frauen nutzen unterschiedliche Formeln |
| Körperwasseranteil | 59.4% | 65.9% | +6.5 pp | bei Frauen hat fettfreies Gewebe einen höheren Wasserköffizienten |
| Skelettmuskelanteil | 42.8% | 48.0% | +5.2 pp | Koeffizient 0.548 vs 0.651 |
| Unterhautfett | 12.5% | 16.0% | +3.5 pp | folgt dem Körperfettanteil nach oben |
| Proteinmasse | **9.1 kg** | **2.8 kg** | Differenz 6.3 kg | ⚠️ der bekannte Zweifelsfall um den Frauenkoeffizienten 0.05 (siehe §7.5) |

Modellkennung: männlich `deurenberg_jp_male` · weiblich `segal_3c_female_lt30` (zusammengefasste Impedanz 551.5Ω)

> Diese Tabelle soll vor allem zwei Dinge zeigen:
> 1. **der BMI ist völlig identisch** – dass er sich beim Umschalten des Geschlechts nicht ändert, ist so gewollt
> 2. **die Zeile zum Protein ist eine Anomalie** – ein Faktor 3 zwischen Männern und Frauen ist nicht plausibel; das ist ein Altlast-Problem der rückgerechneten Koeffizienten

## 9. Übersicht der Formelquellen

| Formel | Quelle | öffentliche Originalgleichung |
| --- | --- | --- |
| BMI | WHO-Definition | ✅ Originalgleichung |
| Körperfett Männer, Deurenberg | Deurenberg et al. 1991 (Korrektur für die japanische Bevölkerung) | ✅ Originalgleichung |
| Körperfett Frauen, Segal 3C/3D | Segal et al. 1988, *AJCN* | ✅ Originalgleichung |
| Rückfalllösung Frauen, Deurenberg | Frauenparameter-Fassung der obigen Männerformel | ✅ Originalgleichung |
| **zusammengefasste Impedanz × 0.675** | von uns aus der offiziellen App rückgerechnet | ❌ **Kalibrierkoeffizient** |
| **Wasserköffizient 0.7185 / 0.8475** | ebendaher | ❌ **Kalibrierkoeffizient** |
| **Proteinkoeffizient 0.163 / 0.05** | ebendaher (Frauenwert fraglich) | ❌ **Kalibrierkoeffizient** |
| **Skelettmuskelkoeffizient 0.548 / 0.651** | ebendaher | ❌ **Kalibrierkoeffizient** |
| **Unterhautfettkoeffizient 0.7165 / 0.72** | ebendaher | ❌ **Kalibrierkoeffizient** |
| **Knochenmasse 4.5% / 4.0%** | ebendaher | ❌ **feste Konstante** |

> Zur Ehrlichkeit: die mit ❌ markierten Teile der obigen Tabelle **haben keine Grundlage in der Fachliteratur**; sie wurden aus den Anzeigen der offiziellen App rückgerechnet.
> Sie bringen diese App nah an die offiziellen Ergebnisse, sind aber nicht die physiologische Wahrheit.

---

## 10. Die Grenzen dieses Algorithmus (wichtig)

### 10.1 Zur Anzeige der Waage bleiben einige Zehntel Prozentpunkte Unterschied

Das Display der Waage nutzt einen **proprietären Algorithmus** des Herstellers (nicht offengelegt). Wir nutzen öffentliche Formeln plus Kalibrierkoeffizienten,
deshalb weichen beide Seiten um etwa **0.3~0.5 Prozentpunkte** voneinander ab.

**Beim BMI stimmen beide immer überein** (reine Mathematik, hier gibt es keinen Spielraum für Algorithmusunterschiede).

### 10.2 Die Impedanz hängt stark vom Wasserhaushalt ab

Derselbe Körper kann je nach Zustand eine um einige zehn Ohm abweichende Impedanz haben, was 2~5 Prozentpunkte beim Körperfettanteil entspricht:

| Situation | Impedanz | abgelesener Körperfettanteil |
| --- | --- | --- |
| morgens direkt nach dem Aufstehen (leicht dehydriert) | eher hoch | eher hoch |
| direkt nach dem Trinken / nach dem Sport (verstärkte Durchblutung) | eher niedrig | eher niedrig |
| direkt nach dem Duschen (feuchte Haut) | eher niedrig | eher niedrig |
| im Winter bei trockenen Fußsohlen | eher hoch | eher hoch |

**Richtige Anwendung**: immer im gleichen Zustand messen (zum Beispiel jeden Morgen nach dem Aufstehen, nach dem Wasserlassen, vor dem Trinken)
und den **Trend** betrachten, nicht den Einzelwert.

### 10.3 Personengruppen, für die das Verfahren nicht geeignet ist

- Schwangere (besondere Verteilung der Körperflüssigkeit)
- Sportler / Bodybuilder (bei sehr niedrigem Körperfett ist die Extrapolation der Formeln ungenau)
- Menschen mit Ödemen, Aszites oder an der Dialyse (abnormer Flüssigkeitshaushalt)
- Kinder und Jugendliche (die Formeln gelten nicht für die Wachstumsphase)
- Menschen mit Herzschrittmacher (Risiko durch den schwachen Strom, **unter keinen Umständen verwenden**)

### 10.4 Kein Medizinprodukt

Alle Zahlen sind **Schätzwerte**, dienen nur als persönlicher Trendhinweis und dürfen weder für Diagnose noch Therapie oder irgendeine medizinische Entscheidung herangezogen werden.
Für eine genaue Körperzusammensetzung ist DEXA (Dual-Energy-Röntgenabsorptiometrie) oder MRT erforderlich.

---

## 11. Literaturverzeichnis

1. **Segal KR, et al.** "Lean body mass estimation by bioelectrical impedance analysis:
   a four-site validation study." *Am J Clin Nutr.* 1988;47(1):7-14.
2. **Deurenberg P, et al.** "Body mass index as a measure of body fatness:
   age- and sex-specific prediction formulas." *Br J Nutr.* 1991;65(2):105-114.
3. **Deurenberg-Yap M, et al.** "The paradox of low body mass index and high body fat
   percentage among Chinese, Malays and Indians in Singapore." *Int J Obes.* 2000.
4. World Health Organization. "BMI classification."

> Die Kalibrierkoeffizienten (0.675 / 0.7185 / 0.8475 / 0.163 / 0.05 / 0.548 / 0.651 / 0.7165 / 0.72)
> haben keine Quelle in der Fachliteratur; sie stammen aus der Rückrechnung der Anzeigen der offiziellen Ant-Health-App im Rahmen dieses Projekts
> und sind in den Messnotizen des [Protokolldokuments](PROTOCOL.md) festgehalten.