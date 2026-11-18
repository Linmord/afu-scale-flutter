# AFU-WL-TZ-A1 -kehonkoostumusvaa'an protokolla · kansantajuinen versio

> **Kenelle**: henkilöille, joilla on perustiedot verkoista (tietää mitä IP, portti ja binääri ovat), mutta jotka eivät ole koskeneet Bluetooth-protokolliin.
> Tämän luettuasi sinun pitäisi pystyä kirjoittamaan itse ohjelma, joka yhdistää tähän vaa'aan ja lukee painon ja kehon rasvaprosentin.
>
> **Mitä tässä on**: `afu-flutter`:ssa **oikeasti ajossa oleva** protokollatoteutus, ei idealisoitu oppikirjaversio.
> Jokaisen johtopäätöksen perässä on lähdemerkintä:
> `[HCI]` = virallisen Ant-sovelluksen Bluetooth-kaappaus · `[WT]` = WeighTrace-dokumentaatio ·
> `[VA]` = vitaloop-app-lähdekoodi · `[AF]` = AntAF-dokumentaatio · `[mitattu]` = itse oikealla laitteella vahvistettu.
>
> Vastaava koodi: `lib/core/protocol.dart` (kehyksen kokoaminen ja jäsennys) · `lib/ble/scale_ble.dart` (yhteys ja komentosekvenssi)

---

## 0. Yhdellä lauseella: mitä me oikein teemme

Tämä vaaka on pohjimmiltaan **puhuva sähkövaaka**. Sen ja puhelimen välillä:

1. Vaaka "lähettää" jatkuvasti ilmaan omaa nimeään ja identiteettiään (kuin liikkeen ripustama kyltti)
2. Puhelin vastaanottaa kyltin ja yhdistää siihen, saa kaksi "postilaatikkoa": yhden lähettämiseen, yhden vastaanottamiseen
3. Puhelin työntää niihin kiinteässä järjestyksessä 8 samanmuotoista pientä lappua (**kättely**)
4. Vaaka alkaa pudottaa datapaketteja vastaanottolaatikkoon, puhelin purkaa ne tavu tavulta ja laskee painon ja kehon rasvaprosentin

Kuulostaa yksinkertaiselta, mutta **jokaisessa kerroksessa on sudenkuoppia** — tavalliset protokolladokumentit kirjoittavat vain "miten pitäisi tehdä",
tämä dokumentti kirjoittaa myös "miten käytännössä menee pieleen".

---

## 1. Tutustutaan ensin muutamaan termiin

Bluetoothissa on paljon termejä, ensi katsomalla menee sekaisin. Käytetään **pakettilokerikon** vertausta:

| Termi | Pakettilokerikkovertaus | Todellinen merkitys |
| --- | --- | --- |
| **Mainonta (Advertising)** | lokeroon liimattu vuokrailmoitus | laite voi ilman yhteyttä huutaa jatkuvasti "olen täällä, nimeni on ..." |
| **Skannaus (Scan)** | isännöitsijä käy kartan kanssa katsomassa ilmoituksia | puhelin ei yhdistä, vain "kuuntelee" kuka ilmassa huutaa |
| **GATT** | pakettilokerikon koko sääntöjärjestelmä | Bluetooth Low Energyn (BLE) standardisääntökokoelma datansiirtoon |
| **Palvelu (Service)** | yksi lokero, esim. "lokero 3" | joukko toimintoja, numeroitu UUID:llä |
| **Ominaisuus (Characteristic)** | lokeron pieni säle | paikka, jossa dataa todella säilötään/haetaan, myös omalla UUID:llä |
| **Kirjoitus (Write)** | sinä työnnät paketin sisään | puhelin → laite, datan lähetys |
| **Ilmoitus (Notify)** | lokero täyttyy ja työntää itse ilmoituksen | laite → puhelin, laite lähettää oma-aloitteisesti (puhelimen ei tarvitse kysyä) |
| **UUID** | lokeron numero, esim. `0000ffb0-...` | 128-bittinen (16 tavua) numero, joka yksilöi palvelun/säleen |
| **MAC-osoite** | henkilötunnus | Bluetooth-laitteen yksilöllinen laiteosoite, esim. `B0:82:AB:07:76:24` |
| **Tavujärjestys (big-endian / little-endian)** | luku 1234 on "kirjoitetaanko 1 ensin vai 4 ensin" | kun useasta tavusta kootaan yksi luku, onko suurin tavu ensin vai viimeisenä |

**Miksi tavujärjestys pitää tuntea**: myöhemmin huomaat, että sama paino esiintyy vaa'alla kahdessa eri paketissa, toisessa **big-endianina** ja toisessa **little-endianina**,
väärin päin laskettuna syntyy järjettömiä lukuja (esim. 55,75 kg luetaan 14 tonniksi).

---

## 2. Ensimmäinen askel: löydä se ilmasta (skannaus)

### 2.1 Mitä vaaka "huutaa"

Vaa'an mainonnassa on nämä asiat (vahvistimme nRF Connectillä ja järjestelmälokeilla):

| Sisältö | Arvo |
| --- | --- |
| Mainonnan nimi | `AFU-WL-TZ-A1` |
| Palvelun UUID | `0xFFB0`, `0x1530` |
| Valmistajadata | valmistaja-ID `0x27AC` |
| **ServiceData** | `0x27AC` + **todellinen MAC (6 tavua, käänteisenä) + 01** |
| Mainontaväli | 999 millisekuntia |

**Tässä on epäintuitiivinen kohta**: mainonnassa näkyvä Bluetooth-osoite (RemoteID)
**ei välttämättä ole vaa'an todellinen MAC**. Todellinen arvo on piilossa ServiceDatassa, ja se on **käänteisessä järjestyksessä**.

```
                          └─── 6 tavua ───┘ └┘  ← käänteisenä lukeva MAC + kiinteä 01
                          └─── 6 tavua käänteisenä ───┘ └(kiinteä 01)
kääntäen luettuna:        B0:82:AB:07:76:24   ← tämä on todellinen MAC
```

> Ensimmäisellä jäsennyksellä emme huomanneet "käänteisyyttä", joten MAC oli yhden tavun verran pielessä eikä yhteys onnistunut millään. [WT/mitattu]

### 2.2 Miten puhelin tunnistaa sen

Kolme ehtoa, **mikä tahansa yksi riittää**:

1. Mainonnan nimessä on `AFU-WL`
2. ServiceDatan UUID on `0x27AC`
3. Mainonnan palvelulistassa on `0xFFB0`

### 2.3 Kaksi pakollista sudenkuoppaa

**Sudenkuoppa 1: älä käytä UUID:ia esisuodattimena**

Monet oppaat neuvovat `startScan([ffb0:n UUID])`, skannaamaan vain laitteet joilla tämä palvelu on — tällä vaa'alla se **jää löytymättä**.
MIUI:ssa näin mitattuna ei löytynyt 4 minuutissa; vaihtamalla "skannaa kaikki + suodata itse callbackissa" tulos tuli 1 sekunnissa. [mitattu]

**Sudenkuoppa 2: älä lisää `neverForLocation`-lippua**

Android 12:n jälkeen Bluetooth-skannauslupaa pyydettäessä, jos mukana on "tätä skannausta ei käytetä paikannukseen" -lippu,
järjestelmä **suodattaa hiljaisesti** tietyntyyppiset mainonnat (tämän vaa'an mainonta tulkitaan juuri beaconiksi).
Oire: luvat on myönnetty, Bluetooth on päällä, mutta skannaus ei löydä mitään.

logcatissa näkyy: `Skipping data matching denylist`. Lipun poistaminen riittää. [mitattu]

---

## 3. Toinen askel: yhdistä ja hae kaksi "postilaatikkoa"

Yhdistämiseen käytetään vaiheessa 2 selvitettyä **todellista MACia**. Yhdistämisen jälkeen näkyy yksi palvelu:

```
palvelu 0000ffb0-0000-1000-8000-00805f9b34fb
  ├── ominaisuus FFB1  ← puhelin "kirjoittaa" komennot tänne
  └── ominaisuus FFB2  ← vaaka "lähettää" datan tänne (ilmoitus pitää tilata ensin)
```

### 3.1 Kirjoita laatikkoon FFB1: vain "kirjattu kirje" kelpaa

BLE-kirjoituksessa on kaksi tilaa:

| Tila | Kansantajuinen selitys | Tukeeko tämä vaaka |
| --- | --- | --- |
| **WRITE** (vastauksella) | kirjattu kirje, kertoo "vastaanotettu" | ✅ tätä on pakko käyttää |
| WRITE_NO_RESPONSE (ilman vastausta) | lappu ovenraosta, ei väliä vastaanotettiinko | ❌ **100 % virhe** |

> Tähän jäädään helpoimmin jumiin: eräät BLE-kirjastot käyttävät oletuksena "ilman vastausta" -tilaa (parempi suorituskyky),
> tällä vaa'alla se heittää joka kerta poikkeuksen. Vahvistimme 8 kirjoituksella, kaikki epäonnistuivat. [mitattu]

### 3.2 Vastaanottolaatikko FFB2: "tilaus" ensin

Puhelin ei voi jäädä odottamaan, että vaaka lähettää dataa; sen on ensin kutsuttava kerran `setNotifyValue(true)` (tilaus).
Tilauksen jälkeen joka kerta kun vaaka lähettää yhden viestin, puhelimen "callback-funktiota" kutsutaan kerran, parametrina 20 tavua.

```dart
// flutter_blue_plus:n tapa
await char.setNotifyValue(true);
char.onValueReceived.listen((data) {
  // data on Uint8List, pituus 20
});
```

### 3.3 Samalla luettavissa olevat laitetiedot

Vaaka paljastaa myös standardin tietopalvelun `0x180A` (Device Information), josta voi lukea:

| Kenttä | Arvo |
| --- | --- |
| Valmistaja | ICOMON |
| Malli | FG2313UWB-D |
| Laiteohjelmistoversio | 1.2.3 |
| Ohjelmistoversio | 1.3.0 |

⚠️ **Älä lue akun ominaisuutta `0x2A19`** — tässä vaa'assa ei ole sitä standardipalvelua lainkaan,
luettu arvo on roskaa (esim. 77 %), todellinen varaus on datapaketin toisessa kohdassa (ks. §6.3). [mitattu]
---

## 4. Kolmas askel: ymmärrä "kirjekuoren" muoto

Kaikki viestit puhelimen ja vaa'an välillä ovat **kiinteästi 20 tavua**, ei tavuakaan enempää tai vähempää.
Voit ajatella sitä vakiokirjekuorena, johon on painettu kiinteät lokerot:

```
tavupaikka: │ [0] │ [1]  │       [2..17]        │   [18]   │   [19]    │
            ┌─────┬──────┬──────────────────────┬──────────┬───────────┐
sisältö:    │ AC  │tyyppi│        runko         │  häntä   │ tarkistus │
            │     │      │      (16 tavua)      │(komento) │   summa   │
            └─────┴──────┴──────────────────────┴──────────┴───────────┘
```

| Sijainti | Nimi | Selitys |
| --- | --- | --- |
| `[0]` | aloitusmerkki | kiinteä `0xAC`, vastaa kirjekuoren "airmail"-leimaa |
| `[1]` | laitetyyppi | puhelin lähettää `0x27`, vaaka vastaa `0x29` (kumpikin ilmoittaa oman "identiteettinsä") |
| `[2..17]` | runko | 16 tavua, varsinainen komento ja data ovat täällä |
| `[18]` | häntä | komennon numero, auttaa erottamaan mikä komento on kyseessä |
| `[19]` | tarkistussumma | estää datan turmeltumisen siirron aikana |

### 4.1 Mikä tarkistussumma on

Kuvittele lähettäväsi kirjeen ja kirjoittavasi kuoren sulkimeen luvun: **"kaikkien sisällä olevien merkkien viivojen summa"**.
Vastaanottaja avaa kirjeen ja laskee uudelleen; jos ei täsmää, kirje vioittui matkalla.

Sääntö on:

```
tarkistussumma = (tavut 2–18 kaikki yhteenlaskettuina) & 0xFF
```

**Mitä `& 0xFF` tarkoittaa**?

Yksi tavu voi tallentaa enintään 255. Summa voi ylittää 255 reilusti (esim. 2000),
`& 0xFF` tarkoittaa "**pidetään vain viimeiset 8 bittiä**", eli sama kuin "jakojäännös 256:lla".

```
esimerkki: summa 2000
2000 = binäärinä 11111010000   (11 bittiä)
vain 8 viimeistä → 11010000 = 208
joten tarkistussummaksi tulee 208 (0xD0)
```

> ⚠️ Huomaa, että väli on `[2..18]` — **sisältää hännän `[18]`, ei sisällä itseään `[19]`**.
> Joissain verkkodokumenteissa sanotaan "summataan vain runko", sitä noudattamalla epäonnistuu aina. [mitattu, tavu tavulta]

### 4.2 Yli 16 tavun runko katkaistaan

Kehyksen kokoamisfunktiossa on katkaisu: paikat 2–17 ovat yhteensä 16, ylimenevä hylätään.
Joten **yhden komennon runko on enintään 16 tavua**, jos ei mahdu, se pitää pilkkoa paketeiksi.

---

## 5. Neljäs askel: lähetä 8 komentoa järjestyksessä (kättely)

Yhdistämisen jälkeen **ei voi kysyä dataa suoraan**, ensin pitää "ilmoittautua". Vaa'an pitää ensin tuntea kuka olet, ennen kuin se tekee työtä.

Järjestys on kiinteä, jokaisen väli **400 millisekuntia** (liian nopeasti vastapuoli ei ehdi käsitellä ja pudottaa).

| # | Komento | Tehtävä | Runko (16 tavua) |
| --- | --- | --- | --- |
| 1 | `08` aikasynkronointi | kertoo vaa'alle "paljonko kello on" | `08` + Unix-sekunnit (4 tavua) + aikavyöhyke |
| 2 | `01` käyttäjä | kertoo vaa'alle "kuka olen" | `01 00 01` + pituus + paino (2 tavua ×100) + ikä + sukupuoli |
| 3 | `02` paikka | ylikirjoittaa vaa'assa olevan käyttäjäasetuksen | kaksi 7 tavun ryhmää (paikka 1 / paikka 2) |
| 4 | `D0` täysi kättely | ilmoittaa kaikki tiedot kerralla uudelleen | aika + aikavyöhyke + yksikkö + paikka + pituus + paino + ikä + sukupuoli + tavoite + `03 00` |
| 5 | `06` kysely | kysyy asetukset | `06` |
| 6 | `04 D6` | nostaa reaaliaikapakettien tahtia | `04 D6` |
| 7 | `04 D8` | pyytää historiatietueet (ensimmäinen kerta) | `04 D8` |
| 8 | `04 D8` | pyytää historiatietueet (toinen kerta) | `04 D8` |

### 5.1 Muutamia helposti väärin meneviä yksityiskohtia

**① Miten aikavyöhyke lasketaan**

```
utcQuarters = (UTC-poikkeama minuutteina ÷ 15) & 0xFF
```

Miksi 15 minuuttia? Koska maailmassa on aikavyöhykkeitä kuten UTC+5:30 ja UTC+5:45, puolen tunnin tai vartin poikkeamia,
15 minuuttia pienimpänä yksikkönä riittää kaikkien aikavyöhykkeiden esittämiseen. Kiina on UTC+8 → 480 minuuttia → 480÷15 = **32**.

**② Sukupuolella on vain kaksi arvoa**

```
mies = 1    nainen = 2
```

⚠️ Tämä ei ole ohjelmoinnissa tavallinen "0/1", vaan **1 ja 2**. Väärin kirjoitettuna kehon rasvakaava valitaan väärin ja tulos heittää kaksinkertaiseksi.

**③ Paino tallennetaan kerrottuna 100:lla**

Paino käyttää 2 tavua (enintään 65535), yksikkö on "sadasosakilo".
Joten 55,75 kg tallentuu muotoon `5575` = heksadesimaalina `0x16 0b`.

**④ Pituus tallennetaan vain kokonaislukuna**

Pituus vie vain 1 tavun (enintään 255 cm), joten 168,6 cm muuttuu **168**:ksi.

**⑤ Mistä nämä arvot tulevat**

```
paino = jäsenprofiilin paino → viimeisin mittaus → jos ei kumpaakaan, varalla 60 kg
tavoitepaino = käyttäjän asettama → jos ei asetettu, "viitepaino × 0,75"
```

### 5.2 Komennon `02` erikoisuus

Virallinen Ant-sovellus lähettää tämän komennon **vain "laitteen irrotuksessa"**, ja sen tehtävä on tyhjentää vaa'assa oleva käyttäjäpaikka.

Me muutimme sen lähetettäväksi **joka yhteydellä** — koska kohtasimme vaa'assa jäänteitä vanhasta asetuksesta (pituus jumissa 111 cm:ssä, ei korjaantunut millään),
uudelleenlähetys ylikirjoittaa sen. Kokeellinen käytäntö, sivuvaikutukset ks. §8. [HCI]

---

## 6. Viides askel: ymmärrä mitä vaaka vastaa

Vaa'an lähettämä paketti on myös 20 tavua, `[0]` on `0xAC` mutta `[1]` vaihtuu `0x29`:ksi.
Todellinen "mikä paketti tämä on" on piilossa `[2]`:ssa:

| `[2]`:n arvo | Paketin tyyppi | Milloin esiintyy |
| --- | --- | --- |
| `0x00` | reaaliaikapaketti | mittauksen aikana, 100–150 ms välein |
| `0x80` | vakaa paketti | paino on vakiintunut |
| `0x02` | **lukittu paketti** | mittaus valmis, sisältää lopullisen impedanssin (tärkein) |
| `0x01` | historiapaketti | yhteyden jälkeen vaaka työntää synkronoimattomat vanhat tietueet |
| `0x06` | asetuskortti | vastaus `06`-kyselyyn, työntää 5 pakettia peräkkäin |

### 6.1 Miten paino lasketaan 3 tavusta

Tämä on koko dokumentin tärkein ymmärrettävä kohta. Ensin reaaliaikapaketin kaava (**little-endian-tyylinen kirjoitus**):

```
paino(g) = ((d[3] - 0x68) × 65536 + d[4] × 256 + d[5]) ÷ 1000
```

**Miksi kerrotaan 65536:lla ja 256:lla?**

Koska yksi tavu tallentaa vain 0–255, ei riitä satoihin kilogrammoihin (grammoina satojatuhansia).
Siksi **kolme tavua yhdistetään yhdeksi "suureksi luvuksi"**:

```
ajattele kolmea tavua kolmena nupikkona:
  1. nuppi (d[3]): joka pykälä = +65536
  2. nuppi (d[4]): joka pykälä = +256
  3. nuppi (d[5]): joka pykälä = +1

kuin kymmenjärjestelmässä: sadat ×100, kymmenet ×10, ykköset ×1
paitsi että nämä "paikat" ovat 256-kantaisia, joten painot ovat 65536 / 256 / 1
```

**Mitä `- 0x68` tekee?**

Vaa'an tehdas"nollakohta" ei ole 0 vaan `0x68` (desimaalina 104). Vastaa vanhanmallista henkilövaakaa, jonka viisari ei ollut alunperinkään kohdallaan nollassa,
tämä poikkeama pitää vähentää ensin.

**`÷ 1000`**: koska laskettu yksikkö on gramma, muunnetaan kilogrammoiksi.

### 6.2 Miksi lukitun paketin paino vaihtoi paikkaa ja kirjoitustapaa

Lukitun paketin paino on **`d[10..12]`** (ei `d[3..5]`), ja kaava muuttui:

```
paino(g) = ((d[10]<<16 | d[11]<<8 | d[12]) - 0x680000) ÷ 1000
```

**Mitä `<<16` ja `|` ovat?**

`<<16` on "siirto vasemmalle 16 bittiä", sama kuin **× 65536**; `|` on "kolmen osan yhdistäminen".
Joten tämä kaava on pohjimmiltaan **sama algoritmi** kuin yllä, vain "ohjelmoijamaisemmin" kirjoitettuna:

```
tapa A (koululaisversio)     tapa B (bittioperaatioversio)
d[10] × 65536                d[10] << 16
d[11] × 256                  d[11] << 8
d[12] × 1                    d[12]
kolme yhteenlaskettuna       kolme yhdistettynä |:llä
```

⚠️ Mutta **poikkeama on eri**: tässä se on `0x680000` (ei `0x68`).
Koska luku on kokonaisuutena 65536 kertaa suurempi, myös poikkeama skaalautuu.

**Täydellinen esimerkki** (tämä on yksi oikealta laitteelta kaapattu):

```
raakapaketti: ac 29 02 00 01 ae 01 83 01 80 68 d9 c6 ...
                                            └──┬───┘
                                            painon kolme tavua

d[10]=0x68  d[11]=0xD9  d[12]=0xC6
yhdistettynä: 0x68d9c6 = 6 871 494
miinus poikkeama: 6 871 494 - 0x680000(6 815 744) = 55 750
jaettuna 1000:lla: 55 750 ÷ 1000 = 55,75

→ paino 55,75 kg ✅

saman paketin impedanssi:
impedanssi1 = (d[4]<<8 | d[5]) = (0x01<<8 | 0xae) = 256 + 174 = 430 Ω
impedanssi2 = (d[6]<<8 | d[7]) = (0x01<<8 | 0x83) = 256 + 131 = 387 Ω
```

### 6.3 Missä varaus on piilossa

**Ei standardia akkupalvelua** (§3.3 kertoi). Todellinen varaus on reaaliaikapaketin `d[11]`:n **7 alemmassa bitissä**:

```
varaus = d[11] & 0x7F
```

`& 0x7F` = "pidetään vain 7 alinta bittiä" (korkein bitti on lippu, ei lasketa varaukseen).

⚠️ **Kaksi ansaa**:
1. Mittauksen aikana `d[11]` muuttuu `0x64`:ksi (=100), se on "mittaus valmis" -tilalippu, **ei varaus**, se pitää sulkea pois
2. Tämän vaa'an varaus näyttää pitkään noin **10 %** (915 kaappauksen moodi), se ei ole rikki

### 6.4 Historialuettelo (`0x01`)

Yhteyden onnistuttua vaaka työntää automaattisesti kaikki "ei synkronoidut" vanhat tietueet, kukin 20 tavua:

```
aika        = d[3..6]   (Unix-aikaleima, 4 tavua, big-endian)
paino       = ((d[8]<<16 | d[9]<<8 | d[10]) - 0x680000) / 1000
impedanssi1 = (d[11]<<8 | d[12])
impedanssi2 = (d[13]<<8 | d[14])
```

**Laukaisuehto** (tämä on kriittinen):

```
Kun on kirjoitettu "08 aikasynkronointi + 01 käyttäjä + D0 täysi kättely", vaaka työntää automaattisesti kaikki synkronoimattomat tietueet,
04D8 ei ole välttämätön (lähetettynä varmempi).
```

Työnnettyään vaaka merkitsee sisäisesti nämä tietueet "synkronoiduiksi", **eikä työnnä niitä enää**, kunnes uusi mittaus syntyy.
Jos vaa'assa ei alunperin ole tietueita, yhteys on aivan hiljainen — se on normaalia, ei merkki rikkinäisyydestä.

⚠️ **Sama aikaleima voi tulla 3 kertaa** (Bluetooth toimittaa uudelleen), ja duplikaatit on poistettava.
Me teemme sen yhdistämällä `aikaleima_paino` yksilölliseksi avaimeksi.

### 6.5 Miten tietää "missä vaiheessa mittaus nyt on"

```
vastaanotettu 0x02                             → valmis (lopullinen impedanssi)
vastaanotettu 0x00 tai 0x80, ja d[11] >= 100   → impedanssia mitataan
muu                                            → punnitus käynnissä
```

**Tärkein lause impedanssista**:

> Impedanssin määrää vain **fyysinen olosuhde**. Arvo saadaan vain kun paljain jaloin seistään neljällä elektrodilevyllä muodostaen kehon piiri;
> yhdellä jalalla, sukat jalassa tai liian kuivalla jalkapohjalla impedanssi on varmasti **0**, eikä mikään komento saa sitä aikaan. [A/B-vertailumittaus]
>
> Verkossa sanottu "lähettämällä `04 D6` saa impedanssimittauksen päälle" on **väärin** — se vain lisää reaaliaikapaketteja (26 → 77).
> Todellinen impedanssiarvo esiintyy vain `0x02`-lukitun paketin tavuissa 4–8.
---

## 7. Miltä yksi täydellinen mittaus näyttää alusta loppuun

```
aikajana
│
├─ käyttäjä astuu vaa'alle, vaa'an näyttö syttyy
│
├─ vaaka: mainonnassa huutaa "olen AFU-WL-TZ-A1"         —— 999 ms välein, jatkuvasti
│
├─ puhelin: löytää sen → yhdistää MACilla → tilaa FFB2
│
├─ puhelin: lähettää 8 komentoa järjestyksessä (400 ms väli)   —— noin 3,2 sekuntia
│    08 aikasynkronointi → 01 käyttäjä → 02 paikka → D0 kättely
│    → 06 kysely → 04D6 → 04D8 → 04D8
│
├─ vaaka: alkaa työntää 0x00-reaaliaikapaketteja (100–150 ms välein)  —— luvut hyppivät
├─ vaaka: paino vakiintuu → työntää 0x80 vakaan paketin
├─ vaaka: siirtyy impedanssimittaukseen → d[11] >= 100
├─ vaaka: mittaus valmis → työntää 0x02 lukittua pakettia toistuvasti (noin 6 s)  —— lopullinen impedanssi
│
├─ puhelin: purkaa lukitun paketin → laskee paino + rasva → tallentaa tietokantaan
│
├─ vaaka: jos vielä synkronoimattomia vanhoja tietueita → työntää 0x01 historiapaketteja
│         työnnettyään merkitsee sisäisesti "synkronoiduksi"
│
└─ loppu (vaaka menee hetken päästä itsestään lepotilaan)
```

**Miksi lukittua pakettia työnnetään toistuvasti 6 sekuntia**? Koska Bluetooth voi pudottaa paketteja, toistaminen varmistaa että puhelin varmasti saa sen.
Puhelin voi lopettaa yhden vastaanoton jälkeen.

---

## 8. Sudenkuopat, joihin oikeasti astuimme

Tämä osio on dokumentin arvokkain — **mitkään neljästä verkon reverse-dokumentista eivät maininneet näitä**.

### Sudenkuoppa 1 · kirjoitusominaisuudella vain "kirjattu kirje" -tila

`FFB1` tukee vain vastauksella tehtävää kirjoitusta. Ilman vastausta -tilassa **100 % poikkeus**.
(vitaloop käyttää Kotlinin oletusta, joka on vastauksella, joten se ei osunut; eräät JS/Dart-kirjastot eivät oleta sitä.)

### Sudenkuoppa 2 · Android 12:n "denylist" syö mainonnan hiljaisesti

Kun skannausluvassa on `neverForLocation`-lippu, tämän vaa'an mainonta tulkitaan beaconiksi ja suodatetaan pois.
Luvat on kaikki myönnetty, Bluetooth on päällä, silti ei löydy; logcatissa vain yksi rivi `Skipping data matching denylist`.

### Sudenkuoppa 3 · MIUI:ssa eri Bluetooth-kirjastojen nopeusero 400-kertainen

Sama puhelin, sama vaaka:

| Kirjasto | Skannauksen kesto |
| --- | --- |
| `flutter_blue_plus` | **alle 1 sekunti** |
| `react-native-ble-plx` | **noin 7 minuuttia** |

Tämä on **kirjastojen käärekerroksen ero**, ei liity lupiin. Tämä oli myös suora syy siihen, miksi lopulta kirjoitimme RN-version Flutteriksi.

### Sudenkuoppa 4 · UUID-esisuodatus skannauksessa pudottaa vaa'an

`startScan([ffb0:n UUID])` MIUI:ssa 4 minuuttia ilman tulosta; täysi skannaus + oma suodatus callbackissa, tulos sekunnissa.

### Sudenkuoppa 5 · juuri yhdistettynä tila "valehtelee irrotukseksi"

Sinä hetkenä kun GATT muodostuu, yhteystila hetkellisesti ilmoittaa virheellisesti `disconnected`.
Jos ripustat suoraan "irrotuksessa yhdistä uudelleen" -ajastimen, seuraa **kaksinkertainen kättely** — vaaka tulkitsee sen uudeksi synkronointisessioksi ja työntää historian uudelleen.

Korjaus: ennen uudelleenyhdistämistä tarkista `isConnected` uudelleen ja lisää "yhdistetään parhaillaan" -lukko.

### Sudenkuoppa 6 · "muuttuiko paino" -kynnys ei saa olla liian suuri

Haluamme kirjoittaa uusimman painon takaisin jäsenprofiiliin, joten pitää päätellä "muuttuiko arvo".

| Kynnys | Seuraus |
| --- | --- |
| 1 kg | 0,1 kg nousu tulkitaan "ei muuttunut", ei päivity koskaan |
| 0,05 kg | liukulukujen tarkkuusongelma: 55,85 − 55,80 laskee 0,0499…, silti estyy |
| **0,001 kg** | ✅ lopullinen valinta |

### Sudenkuoppa 7 · miehillä ja naisilla on täysin eri rasvakaavat

```
mies   = Deurenberg-kaava: 1,10×BMI + 0,23×ikä − 11,22   (impedanssi ei ole mukana!)
nainen = Segal-kaava: tarvitsee impedanssin, kahdesta impedanssista yhdistetään (i1+i2)×0,675
```

**Vielä yksi tiedettävä**: vaa'an oman näytön rasvaprosentti ja sovelluksen laskema **eroavat joitakin kymmenesosaprosenttiyksiköitä**.
Koska vaaka käyttää valmistajan omaa algoritmia (ei julkinen), sovellus käyttää yllä olevia julkisten artikkelien kaavoja.

**BMI on aina sama** (BMI katsoo vain painoa ja pituutta, siinä ei ole algoritmieroja).

Väärä sukupuoli → tulos lähes kaksinkertainen. Esimerkki (55,75 kg / 163 cm / 24 vuotta / impedanssi 430+387):

| Kumpi kaava | Laskettu rasvaprosentti |
| --- | --- |
| mieskaava | 17,4 % |
| naiskaava | 22,2 % |

### Sudenkuoppa 8 · vaa'assa on "edellinen käyttäjäasetus"

Vaaka säilyttää viimeksi kirjoitetun käyttäjäpaikan. Jos sovelluksen profiili muuttuu mutta vaa'assa on yhä vanha,
vaa'an näytön rasva on selvästi väärä. Tämän vuoksi lähetämme `02`-komennon joka yhteydellä ylikirjoittaaksemme.

### Sudenkuoppa 9 · varaus ei ole 77 % vaan 10 %

| Lähde | Lukema | Totuus |
| --- | --- | --- |
| standardi akkupalvelu `0x2A19` | 77 % | ❌ roskaa (palvelua ei ole olemassakaan) |
| reaaliaikapaketti `d[11] & 0x7F` | 10 % | ✅ todellinen (915 kaappauksen moodi) |

### Sudenkuoppa 10 · vaa'assa ei ole "poista tietue" -toimintoa

Käytiin läpi kaikki 29 virallista kirjoituskomentoa, **ei mitään poisto- tai tyhjennyskomentoa**.

Tämä tarkoittaa: heti kun vaaka merkitsee tietueen "synkronoiduksi", mikään sovellus ei saa sitä enää.
**Sovelluksen tallennusvirhe = pysyvä menetys**. Joten yhteyden aikana prosessia ei saa tappaa kesken.

---

## 9. Erot neljään verkon reverse-dokumenttiin

Viittasimme viiteen avoimen lähdekoodin projektiin, mutta **niiden mukaan tekemällä menee monessa pieleen**.
Tässä osiossa on mitattujen johtopäätösten ja dokumenttien väitteiden erot, jotta seuraavat säästyvät harhailulta.

### 9.1 Dokumentin väite vs. mitattu johtopäätös

| # | Mitä dokumentti sanoo | Mitä mittaaminen näyttää | Todiste |
| --- | --- | --- | --- |
| 1 | [AF] paino on täysi 32 bittiä, jaetaan `& 0x3FFFF`:llä | reaaliaika- ja vakaapaketti `((d[3]-0x68)×65536+d[4]×256+d[5])/1000`; **lukitun paketin paino on d[10:13]**, kaksi eri paikkaa | 55,75 kg koko ketju tarkistettu |
| 2 | [AF] vaaka ei mainosta lepotilassa, pitää astua päälle | tämä vaaka **mainostaa myös näytön ollessa sammuksissa** (999 ms), nRF löytää 2 sekunnissa, testipenkissä 84 ms | nRF + viestintäloki |
| 3 | [AF] tietopaketti lähetetään uudelleen 15 s välein, heartbeat tarvitaan | **heartbeat ei ole pakollinen**, ilman sitä impedanssi tulee vakaasti | mitattu ilman heartbeatiä, normaali |
| 4 | [VA] kättelyssä weight/target täytetään 0:lla | **todelliset arvot** ovat parempia, vaa'an paikka ja profiili pysyvät samoina | mitattu loki |
| 5 | [VA] yksi `D0` kättely riittää | ilman `01` käyttäjäkomentoa **impedanssi ei laukea**, koko 8 komennon sarja on vakain | ennen/jälkeen vertailu |
| 6 | [WT] ServiceDatan payloadissa on `AC27`-etuliite | payload = **MAC 6 tavua (käänteisesti) + 01**, ei etuliitettä | raakatavut tarkistettu |
| 7 | [WT] `D6`-komento on impedanssin lähde | `D6` vain lisää reaaliaikapaketteja (26→77), **lopullinen impedanssi on `0x02`-paketissa d[4:8]** | A/B-vertailu |
| 8 | [WT/HCI] tarkistussumma = rungon summa | tarkalleen **`sum(frame[2..18]) & 0xFF`** (**sisältää hännän [18]**) | tavu tavulta tarkistettu |

### 9.2 Neljä dokumenttia eivät kirjoittaneet, itse löysimme

1. `FFB1` **tukee vain vastauksella kirjoitusta** (tarkemmin sudenkuoppa 1)
2. Android 12:n `neverForLocation` johtaa siihen, että mainonta suodatetaan denylistillä (sudenkuoppa 2)
3. MIUI:ssa kahden Bluetooth-kirjaston nopeusero 400-kertainen (sudenkuoppa 3)
4. UUID-esisuodatus pudottaa vaa'an (sudenkuoppa 4)
5. yhteyden hetken tilan väpätys johtaa kaksoiskättelyyn (sudenkuoppa 5)
6. profiilin takaisinkirjoituksen kynnyksen pitää mennä 0,001 kg:iin asti (sudenkuoppa 6)
7. miesten ja naisten BIA-kaavat täysin erilaiset (sudenkuoppa 7)
8. `02`-komennon todellinen merkitys on "kirjoita kaksi käyttäjäpaikkaa, kussakin 7 tavua"
9. varauksen todellinen arvo on `d[11]`:n 7 alimmassa bitissä, eikä tässä vaa'assa ole `0x2A19`-palvelua (sudenkuoppa 9)
10. "synkronoitu"-merkintä vaikuttaa **kaikkiin** sovelluksiin, ja koska poistokomentoa ei ole = tallennusvirhe on pysyvä menetys (sudenkuoppa 10)

### 9.3 Tarkoitukselliset erot viralliseen Ant-sovellukseen

| Miten virallinen tekee | Miten me teemme | Miksi |
| --- | --- | --- |
| `02` vain irrotuksessa | joka yhteydellä (kokeellinen) | ylikirjoittaa vaa'assa olevat vanhat käyttäjäasetukset (oli jumissa 111 cm:ssä) |
| tietopaketti 15 s välein (heartbeat) | ei lähetetä | mitattu ei-pakolliseksi, säästää virtaa |
| `04D8` kerran | kaksi kertaa | varmuudeksi, sivuvaikutuksia ei havaittu |
| iOS-asiakasohjelma | Android / Flutter | erilainen skannausstrategia (ks. sudenkuoppa 3, sudenkuoppa 4) |

### 9.4 Vielä vahvistamattomat kysymykset

- [ ] `02`:n lähettämisen joka yhteydellä pitkän aikavälin sivuvaikutukset (jos historiaa työnnetään toistuvasti uudelleen, palataan "vain irrotuksessa")
- [ ] onko `deviceType` `0x29` välttämätön osassa laiteohjelmistoja (vitaloop toimii myös 0x29:llä)
- [ ] onko rasvaprosentin ja vaa'an näytön 0,4 prosenttiyksikön ero vakio painon mukaan
- [ ] onko 15 s heartbeat tarpeen erittäin pitkässä yhteydessä (>10 minuuttia)

---

## 10. Miten debugata itse

### 10.1 Avaa sovelluksen viestintäloki

Lokin sisäänkäynti on oletuksena piilotettu (easter egg):

> **Asetukset → Tietoja → napauta versionumeroa 7 kertaa**

Avauksen jälkeen mittaussivun oikeaan yläkulmaan ilmestyy "Viestintä N" -painike, josta näkee jokaisen lähetetyn ja vastaanotetun raakatavun.

### 10.2 Lokitiedosto kirjoittuu automaattisesti

Yhteyden aikana kirjoitus 3 s välein (irrotuksessa vielä pakotettu kirjoitus):

```
/storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

```bash
adb pull /storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

Muoto: `aika suunta(→ lähetetty / ← vastaanotettu) raaka 20 tavua [komennon nimi tai paketin tyyppi]`

### 10.3 Järjestelmätason avainsanat

| Oire | logcat-avainsana |
| --- | --- |
| skannaus suodatetaan järjestelmässä | `Skipping data matching denylist` |
| skannauksen eteneminen | `SCAN_STEP` |
| kirjoitus epäonnistuu | `PlatformException` + `not supported` |

### 10.4 Ristiintarkista nRF Connectillä

Kun itse kirjoitettu ohjelma käyttäytyy oudosti, yhdistä ensin käsin **nRF Connectillä** (puhelimen yleinen BLE-debugaustyökalu),
ja katso saako dataa normaalisti. Jos nRF:lläkään ei onnistu, kyse on fyysisestä tai ympäristöongelmasta (ei astuttu päälle, liian kaukana, akku vähissä).

---

## 11. Lähteet

Tätä protokollaa ei ole arvattu tyhjästä, pääasiallisesti on viitattu näihin julkisiin reverse-engineering-tuloksiin:

| Projekti | Kieli/alusta | Panos |
| --- | --- | --- |
| [Fatpandac/AFUScale](https://github.com/Fatpandac/AFUScale) | iOS / Swift | varhaisin protokollan reverse, komentosekvenssin perusta |
| [Mzdyl/ant-afu-welland-scale](https://github.com/Mzdyl/ant-afu-welland-scale) | Python | kehyksen muoto ja painon koodaus |
| [monkey-wenjun/vitaloop-app](https://github.com/monkey-wenjun/vitaloop-app) | Android / Kotlin | yhden kättelyn malli, `deviceType`-käyttö |
| [Xuan-lprk/WeighTrace](https://github.com/Xuan-lprk/WeighTrace) | dokumentaatio | mainonnan ServiceData-rakenne, skannausstrategia |
| [ZeroOneCN/AntAF](https://github.com/ZeroOneCN/AntAF) | dokumentaatio | painon 32-bittisen koodauksen selitys, tietopaketin heartbeat |

Lisäksi käytimme paikallista HCI-kaappausta (`ant_cleanup.log`, `unbind_official.log`) `02`-komennon lähdetodisteena.

---

## Liite: pikalista "itse toteuttavalle"

```
1. skannaus: täysi skannaus, callbackissa suodatus "nimi sisältää AFU-WL / ServiceData on 27AC / palvelu sisältää FFB0"
2. hae MAC: ServiceDatan 6 tavua käänteisesti
3. yhdistä → hae palvelu FFB0
4. tilaa FFB2:n ilmoitus (setNotifyValue(true))
5. kirjoita FFB1:een 8 komentoa, 400 ms väli, kaikki "vastauksella"-tilassa
6. kuuntele FFB2:n callbackia, päätä paketin tyyppi [2]:sta
7. 0x02-paketti: paino d[10:13], impedanssi d[4:8], kumpikin miinus poikkeama ja jaettuna 1000:lla
8. kun 0x02 on vastaanotettu, homma on valmis, tallenna
```

**Kolme helpoiten pieleen menevää kohtaa**: kirjoitustila (pakko vastauksella), tarkistussumman väli (sisältää [18]), painon poikkeama (`0x68` vs `0x680000`).
