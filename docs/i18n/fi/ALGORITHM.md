# Kehonkoostumusalgoritmi · julkinen selvitys

> **Miksi tämä julkaistaan**: luku kuten kehon rasvaprosentti — jos käyttäjälle ei kerrota, miten se lasketaan,
> käyttäjä voi vain "uskoa" sitä — terveysdata ei saisi olla sellaista.
>
> Tässä dokumentissa avataan **jokainen kaavarivi** tiedostosta `lib/core/bodycomp.dart`,
> ja merkitään selvästi: mitkä ovat **julkisten artikkelien alkuperäisiä kaavoja**, mitkä meidän **mitattuna takaisin johdettuja kalibrointikertoimia**.
>
> **Johtopäätös yhdellä lauseella**: tämä vaaka **ei mittaa rasvaa suoraan**. Se mittaa **resistanssia**,
> ja rasvaprosentti **arvioidaan** resistanssista (tai pituudesta, painosta ja iästä).

---

## 1. Ymmärrä ensin periaate: miksi resistanssin mittaaminen kertoo rasvasta

### 1.1 Ihmiskehon sähkönjohtavuus vaihtelee

| Kudos | Vesipitoisuus | Johtavuus |
| --- | --- | --- |
| lihas, veri, sisäelimet | korkea (noin 70~75%) | **hyvä** (sisältää elektrolyyttejä, kuin suolavesi) |
| rasva | matala (noin 10~20%) | **huono** (kuin muovi) |
| luu | matala | huono |

Siis: **samalla painolla rasvaisemmalla henkilöllä on suurempi resistanssi**. Tähän perustuu koko BIA (bioimpedanssianalyysi).

### 1.2 Miten vaaka mittaa

```
       kaksi jalkaa, kummankin jalan alla kaksi elektrodilevyä (yhteensä 4)

  vasen etu  ─┐                   ┌─ oikea etu
              │  ╭────────────╮   │
              │  │vaa'an pinta│   │
              │  ╰────────────╯   │
  vasen taka ─┘                   └─ oikea taka

virtareitti: yhden jalan elektrodi lähettää hyvin heikon vaihtovirran (<1mA, ei tunnu)
          → kulkee pohkeen, reiden, lantion kautta → toisen jalan elektrodiin
          → välissä mitataan jännitehäviö → Ohmin lailla saadaan impedanssi (Ω)
```

**Keskeistä**: molemmilla jaloilla on **seistävä paljain jaloin samanaikaisesti** neljällä elektrodilla, jotta piiri sulkeutuu.
Yhdellä jalalla, sukat jalassa tai liian kuiva jalkapohja → mitattu impedanssi on **0**, eikä rasvaprosenttia voi laskea.

> Tätä ohjelmisto ei voi ohjata. Kaikki väitteet "lähettämällä tietyn komennon impedanssin saa päälle" ovat vääriä —
> teimme A/B-vertailukokeen vahvistaaksemme tämän (ks. [protokolladokumentti](PROTOCOL.md) sudenkuoppa 7).

### 1.3 Mitä raakadataa tämä vaaka antaa meille

Vaaka antaa mittauksen valmistuttua lukitussa paketissa **kaksi ADC-arvoa** (voi ymmärtää vasemman ja oikean kanavan raakalukemina):

```
impedanssi1 = (d[4] << 8 | d[5])   ← yksikkö ohmi
impedanssi2 = (d[6] << 8 | d[7])
```

Normaali vaihteluväli on noin **100 ~ 1500 Ω**. Tämän ulkopuoliset arvot katsotaan aina kelvottomiksi.

---

## 2. Ensimmäinen askel: yhdistä kaksi impedanssia yhdeksi

Artikkelien kaavat hyväksyvät vain **yhden** impedanssiarvon, mutta vaaka antaa kaksi. Meidän tapamme:

```
yhdistetty impedanssi R = (impedanssi1 + impedanssi2) × 0.675
```

### Mistä tuo 0.675 tulee

⚠️ **Tämä kerroin ei ole artikkelista, se on meidän mitattuna takaisin johdettu**.

Tapa: otimme virallisen Ant Health -sovelluksen samalla hetkellä näyttämän rasvaprosentin ja johdimme takaisin, millainen R saa kaavan täsmäämään.
Usean datasarjan sovituksen jälkeen noin 0.675 osui vakaasti (esim. 55.75kg + impedanssi [430, 387] → virallinen näyttää 22.2%).

**Miksi kaksi ADC:tä**: ehkä toinen kanava on 50kHz ja toinen toinen taajuus (monitaajuus-BIA:n tavallinen käytäntö),
kahden kanavan yhdistämisen tarkoitus on tavallisesti kontaktiresistanssin vaikutuksen kumoaminen. Valmistaja ei kuitenkaan julkaissut tätä, käsityksemme on vain päätelmä.

### Kelvollisuustarkistus

```
vain kun yhdistetty R osuu välille 100 ~ 1500 Ω, impedanssi katsotaan kelvolliseksi
```

---

## 3. BMI (ainoa mittari, joka ei perustu arvioon)

```
BMI = paino(kg) ÷ pituus(m)²
```

Esimerkki: 55.75kg, 163cm → 55.75 ÷ 1.63² = **21.0**

**BMI ei sisällä sukupuolta eikä ikää**. Tämä on Maailman terveysjärjestön (WHO) määritelmä,
kaikkien ohjelmistojen laskema BMI pitäisi olla sama (kun paino ja pituus ovat samat).

Joten: sukupuolen vaihtaminen ei muuta BMI:tä, se on **oikea toiminta**, ei bugi.

---

## 4. Miesten rasvaprosentti: Deurenberg-kaava (ei käytä impedanssia)

```
rasvaprosentti(%) = 1.10 × BMI + 0.23 × ikä − 11.22
```

**Lähde**: Deurenbergin ym. vuonna 1991 julkaisema etnisesti korjattu kaava (japanilaisen väestön versio).
Tämä on **julkisen artikkelin alkuperäinen kaava**, käytimme vain kiinteitä kertoimia, emme muuttaneet mitään.

**Huom: miesten kaavassa ei ole impedanssia**. Toisin sanoen, kun tiedetään pituus, paino ja ikä,
miesten rasvaprosentti voidaan laskea vaikka elektrodeille ei olisi astuttu kunnolla ja impedanssi olisi 0.

**Mitattu tarkistus**: 79.8kg miesnäyte → laskettu 25.4%, vastaa virallisen sovelluksen näyttöä.

Mallimerkintä: `deurenberg_jp_male`

---

## 5. Naisten rasvaprosentti: Segal-kaava (vaatii impedanssin)

Naisilla on toinen kaavasarja, joka tarvitsee impedanssin.

### 5.1 Laske ensin "rasvaton massa" (FFM, Fat-Free Mass)

```
FFM = paino − rasvan paino    ← eli lihasten, luiden, veden ja sisäelinten summa
```

Segal-kaava ei anna suoraan rasvaprosenttia, vaan arvioi ensin FFM:n ja johtaa siitä takaisin kaavalla `100 × (paino − FFM) ÷ paino`.

### 5.2 Kaksi haaraa: kokeile ensin 3C, sitten 3D

**Haara A (3C-kaava, sopii henkilöille joiden rasva < 30%)**

```
FFM_A = 10.43485
      + 0.00064602 × pituus²(cm²)
      − 0.01397   × R(yhdistetty impedanssi)
      + 0.42087   × paino(kg)
```

Lasketaan ensin A:lla, johdetaan siitä rasvaprosentti, **jos tulos < 30%, käytetään tätä arvoa**.

**Haara B (3D-kaava, sopii henkilöille joiden rasva ≥ 30%)**

```
FFM_B = 9.37938
      + 0.00091186 × pituus²(cm²)
      − 0.01466   × R
      + 0.29990   × paino
      − 0.07012   × ikä
```

> Miksi kaksi osaa? Koska Segal-kaava on alun perin kaksi eri regressiosuoraa eri lihavuusasteille,
> A-kaavalla lihavalta henkilöltä FFM aliarvioidaan systemaattisesti. Kahden osan yhdistäminen on artikkelin alkuperäinen tarkoitus.

**Lähde**: Segalin ym. vuonna 1988 lehdessä *American Journal of Clinical Nutrition* julkaisema kaava.
Alkuperäiset kertoimet ovat julkisia, käytimme niitä sellaisinaan.

**Huomaa pituuden yksikkö**: kaavan pituus on **cm**, neliöitynä cm² (esim. 163² = 26569).
Ei m². Tässä väärin meneminen aiheuttaa 10000-kertaisen heiton.

### 5.3 Järkevyyden rajaus

```
FFM rajataan painon 35% ~ 97% väliin
```

Estetään ääriarvoista syntyvät järjettömät tulokset (esim. impedanssi 100Ω ja paino 30kg).

**Mitattu tarkistus**: 55.75kg + impedanssi [430, 387] → yhdistetty R = 551Ω → laskettu 22.2%, vastaa virallista.

Mallimerkintä: `segal_3c_female_lt30` / `segal_3d_female_ge30`

### 5.4 Naisten varakaava ilman impedanssia

```
rasvaprosentti(%) = 1.10 × BMI + 0.23 × ikä − 5.4
```

Tämä on Deurenberg-kaavan **naisversio** (miesversiossa lopussa on −11.22, naisversiossa −5.4).
Huomaa ero mieskaavaan: samalla BMI:llä ja iällä naisille lasketaan **5.82 prosenttiyksikköä korkeampi** tulos —
se vastaa fysiologista tosiasiaa (naisten normaali rasvaprosentti on jo lähtökohtaisesti miesten yläpuolella).

Mallimerkintä: `deurenberg_jp_female`

---

## 6. Lopullinen rajaus

```
miesten rasvaprosentti rajataan 3% ~ 60%
naisten rasvaprosentti rajataan 8% ~ 60%
```

Alarajat eroavat, koska: miehillä alle 3% rasvaa on fysiologisesti lähes mahdotonta (kilpakehonrakennuksen raja noin 4~5%),
naisilla alle 8% vaikuttaa hormonitoimintaan. Yli 60% on käytännössä mittausvirhe.
---

## 7. Muut mittarit: kaikki "johdetaan" rasvaprosentista

⚠️ **Selvitetään ensin yksi asia**: tämä vaaka mittaa vain **painon** ja **impedanssin**.
Kaikki alla olevat mittarit **johdetaan** edellisessä vaiheessa lasketusta rasvaprosentista, niitä ei mitata erikseen.

Siksi niiden luotettavuus pitää ymmärtää tässä järjestyksessä:

```
luotettavuus: paino (suora mittaus) > BMI (puhdasta matematiikkaa) > rasvaprosentti (kaava-arvio) > muut mittarit (toisen asteen johdannaiset)
```

### 7.1 Rasvamassa / rasvaton massa

```
rasvamassa(kg)   = paino × rasvaprosentti/100
rasvaton massa(kg) = paino − rasvamassa
```

Puhdasta aritmetiikkaa, ei lisäoletuksia.

### 7.2 Luumassa: kiinteä prosentti

```
luumassa% = miehet 4.5%   /   naiset 4.0%
luumassa(kg) = paino × luumassa%
```

⚠️ **Tämä on kovakoodattu vakio, ei mitattu**. Todelliseen luuntiheyteen tarvitaan DEXA (röntgen),
kaikkien kotikehonkoostumusvaakojen "luumassa" on väestökeskiarvosta annettu arvio.
Meidän arvomme on mitattuna takaisin johdettu virallisen sovelluksen näyttämistä arvoista.

### 7.3 Lihasmassa: takaisinpäin vähentämällä

```
lihas% = 100 − rasva% − luumassa%      (tulos rajataan 20% ~ 95%)
lihasmassa(kg) = paino × lihas%
```

Logiikka on "kaikki muu paitsi rasva ja luu lasketaan lihakseksi".
Tarkasti sanoen tähän "muuhun" sisältyvät myös sisäelimet, vesi ja sidekudos, mutta valmistajat luokittelevat näin.

### 7.4 Vesiprosentti: rasvaton massa × kerroin

```
vesi% = (100 − rasva%) × kerroin
kerroin: miehet 0.7185   /   naiset 0.8475
(tulos rajataan 25% ~ 80%)
```

Fysiologinen peruste: rasvaton kudos (lihas, sisäelimet) sisältää vettä noin 73%; rasvakudos noin 10~20%.

⚠️ Naisten kerroin 0.8475 on selvästi yleisesti käytetyn 0.73:n yläpuolella; tämä on mitattuna takaisin johdettu virallisen sovelluksen arvo.
Valmistajalla voi olla oma korjausmallinsa, me kuljemme mitatulla arvolla.

### 7.5 Proteiini: suoraan painon suhteessa

```
proteiinimassa(kg) = paino × kerroin
kerroin: miehet 0.163   /   naiset 0.05
```

⚠️ **Tässä on kohta, joka pitää nostaa esiin**:

| Lähde | Miesten proteiiniosuus | Naisten proteiiniosuus |
| --- | --- | --- |
| fysiologinen yleissivistys | noin 16~18% | noin 16~18% |
| meidän toteutuksemme | 0.163 (järkevä) | **0.05 (selvästi liian pieni)** |

Naisten 0.05 on johdettu takaisin virallisen sovelluksen näyttämistä arvoista,
**fysiologisesti tämä luku ei ole kovin järkevä** — se näyttää 55.75kg naiselle vain 2.8kg proteiinia,
kun todellisuudessa pitäisi olla noin 9kg.

Pidämme sen, jotta "pysymme samassa kuin virallinen sovellus"; jos arvostat enemmän fysiologista järkevyyttä,
voit muuttaa kertoimen noin 0.16:een. **Viittaa tähän kohtaan varoen.**

### 7.6 Luurankolihasprosentti: lihasmassa × kerroin

```
luurankolihas% = lihas% × kerroin
kerroin: miehet 0.548   /   naiset 0.651
(tulos rajataan 10% ~ 70%)
```

"Luurankolihas" on lihaksen se osa, joka kiinnittyy luuhun (erotuksena sydänlihaksesta ja sileästä lihaksesta).
Se on tavallisesti 55~65% lihasten kokonaismäärästä; miesten ja naisten kertoimien ero on mitattuna takaisin johdettu tulos.

### 7.7 Ihonalaisrasva: rasva × kerroin

```
ihonalaisrasva% = rasva% × kerroin
kerroin: miehet 0.7165   /   naiset 0.72
(tulos rajataan 1% ~ rasva%)
```

Rasva jakautuu "ihonalaisrasvaksi" (se kerros, jonka voi nipistää) ja "sisäelinten rasvaksi" (elinten ympärillä).
Tämä kerroin kertoo, että noin 72% rasvasta on ihonalaista.

---

## 8. Täydellinen laskentakulku (pseudokoodi)

```
syöte: paino W(kg), pituus H(cm), ikä A, sukupuoli, impedanssi [i1, i2]

① BMI = W ÷ (H/100)²

② yhdistetty impedanssi R = (i1 + i2) × 0.675
   jos R ei ole välillä 100~1500 → katsotaan ettei kelvollista impedanssia ole

③ laske rasvaprosentti bf:
   jos sukupuoli=mies:
       bf = 1.10×BMI + 0.23×A − 11.22          ← impedanssia ei tarvita
   muuten (nainen):
       jos R on kelvollinen:
           FFM_A = 10.43485 + 0.00064602×H² − 0.01397×R + 0.42087×W
           jos 100×(W−FFM_A)/W < 30  →  bf = 100×(W−FFM_A)/W
           muuten:
               FFM_B = 9.37938 + 0.00091186×H² − 0.01466×R + 0.29990×W − 0.07012×A
               bf = 100×(W−FFM_B)/W
           jossa FFM rajataan välille W×0.35 ~ W×0.97
       muuten (ei impedanssia):
           bf = 1.10×BMI + 0.23×A − 5.4       ← naisten varakaava

④ bf rajataan: miehet 3~60, naiset 8~60

⑤ johdannaiset:
   rasvamassa        = W × bf/100
   rasvaton massa    = W − rasvamassa
   luumassa%         = miehet 4.5 / naiset 4.0
   lihas%            = 100 − bf − luumassa% (rajaus 20~95)
   vesi%             = (100−bf) × (miehet 0.7185 / naiset 0.8475) (rajaus 25~80)
   proteiinimassa    = W × (miehet 0.163 / naiset 0.05)
   luurankolihas%    = lihas% × (miehet 0.548 / naiset 0.651) (rajaus 10~70)
   ihonalaisrasva%   = bf × (miehet 0.7165 / naiset 0.72) (rajaus 1~bf)

⑥ kaikki tulosteet 1 desimaalilla
```

Vastaava koodi: `lib/core/bodycomp.dart` (76 riviä, ei ulkoisia riippuvuuksia, testattavissa erikseen)

---

---

## 8.5 Mitattu tuloste: mitä sama data antaa miehille ja naisille

Otetaan data `55.75kg / 163cm / 24 vuotta / impedanssi 430+387` ja ajetaan koko algoritmi:

| Mittari | Mieskaava | Naiskaava | Ero | Selitys |
| --- | --- | --- | --- | --- |
| BMI | **21.0** | **21.0** | **sama** | puhdasta matematiikkaa, ei sisällä sukupuolta |
| rasvaprosentti | 17.4% | 22.2% | +4.8 pp | miehillä ja naisilla eri kaava |
| vesiprosentti | 59.4% | 65.9% | +6.5 pp | naisten rasvattoman kudoksen vesikerroin on korkeampi |
| luurankolihas% | 42.8% | 48.0% | +5.2 pp | kerroin 0.548 vs 0.651 |
| ihonalaisrasva | 12.5% | 16.0% | +3.5 pp | seuraa rasvaprosenttia |
| proteiinimassa | **9.1 kg** | **2.8 kg** | ero 6.3 kg | ⚠️ naisten kertoimen 0.05 tunnettu ongelma (ks. §7.5) |

Mallimerkintä: miehet `deurenberg_jp_male` · naiset `segal_3c_female_lt30` (yhdistetty impedanssi 551.5Ω)

> Tämä taulukko haluaa sanoa kaksi asiaa:
> 1. **BMI on täsmälleen sama** — sukupuolen vaihtaminen ei muuta sitä, se on suunniteltua
> 2. **proteiini rivi on poikkeava** — miesten ja naisten ei pitäisi erota kolminkertaisesti, tämä on reverse-kertoimien perintöongelma

## 9. Kaavojen lähteet yhdellä silmäyksellä

| Kaava | Lähde | Julkinen alkuperäisversio |
| --- | --- | --- |
| BMI | WHO:n määritelmä | ✅ alkuperäinen |
| miesten rasva Deurenberg | Deurenberg et al. 1991 (japanilaisen väestön korjaus) | ✅ alkuperäinen |
| naisten rasva Segal 3C/3D | Segal et al. 1988, *AJCN* | ✅ alkuperäinen |
| naisten varakaava Deurenberg | sama kuin yllä, mieskaavan naisparametriversio | ✅ alkuperäinen |
| **yhdistetty impedanssi × 0.675** | meidän mitattuna takaisin johdettu virallisesta sovelluksesta | ❌ **kalibrointikerroin** |
| **vesikerroin 0.7185 / 0.8475** | sama | ❌ **kalibrointikerroin** |
| **proteiinikerroin 0.163 / 0.05** | sama (naisten arvo kyseenalainen) | ❌ **kalibrointikerroin** |
| **luurankolihaskerroin 0.548 / 0.651** | sama | ❌ **kalibrointikerroin** |
| **ihonalaisrasvakerroin 0.7165 / 0.72** | sama | ❌ **kalibrointikerroin** |
| **luumassa 4.5% / 4.0%** | sama | ❌ **kiinteä vakio** |

> Rehellinen huomautus: yllä olevan taulukon ❌-merkityillä osilla **ei ole artikkelitukea**, ne on johdettu takaisin virallisen sovelluksen näyttämistä arvoista.
> Ne saavat tämän sovelluksen lähelle virallisia tuloksia, mutta eivät tarkoita fysiologista totuutta.

---

## 10. Tämän algoritmin rajoitukset (tärkeä)

### 10.1 Vaa'an näyttöön jää kymmenesosaprosenttien ero

Vaa'an näyttö käyttää valmistajan **suljettua algoritmia** (ei julkinen). Me käytämme julkisia kaavoja + kalibrointikertoimia,
joten puolten väliin jää eroa noin **0.3~0.5 prosenttiyksikköä**.

**BMI on aina sama** (puhdasta matematiikkaa, algoritmierolle ei ole sijaa).

### 10.2 Impedanssiin vaikuttaa suuresti vesitasapaino

Samalla keholla eri tiloissa impedanssi voi erota kymmeniä ohmeja, mikä vastaa 2~5 prosenttiyksikön eroa rasvaprosentissa:

| Tilanne | Impedanssi | Rasvaprosenttilukema |
| --- | --- | --- |
| juuri herännyt aamulla (lievä kuivuminen) | korkeampi | korkeampi |
| juuri juonut vettä / juuri liikkunut (verentungos) | matalampi | matalampi |
| juuri käynyt suihkussa (iho kostea) | matalampi | matalampi |
| talvella kuiva jalkapohja | korkeampi | korkeampi |

**Oikea käyttötapa**: mittaa aina samassa tilassa (esim. joka aamu herättyä, virtsaamisen jälkeen, ennen juomista),
katso **trendiä** älä yksittäistä lukemaa.

### 10.3 Henkilöt, joille tämä ei sovi

- raskaana olevat (nesteiden jakautuminen poikkeava)
- urheilijat / kehonrakentajat (erittäin alhaisella rasvalla kaava ekstrapoloi epätarkasti)
- turvotus, askites, dialyysipotilaat (nesteet poikkeavat)
- lapset ja nuoret (kasvuvaiheessa kaava ei sovellu)
- henkilöt, joilla on sydämentahdistin (heikon virran riski, **älä ehdottomasti käytä**)

### 10.4 Ei lääkinnällinen laite

Kaikki luvut ovat **arvioita**, tarkoitettu vain henkilökohtaiseen trendiviitteeseen, niitä ei voi käyttää diagnoosiin, hoitoon tai mihinkään lääketieteelliseen päätöksentekoon.
Tarkkaa kehonkoostumusta varten tee DEXA (kaksenerginen röntgenabsorptiometria) tai MRI.

---

## 11. Kirjallisuusviitteet

1. **Segal KR, et al.** "Lean body mass estimation by bioelectrical impedance analysis:
   a four-site validation study." *Am J Clin Nutr.* 1988;47(1):7-14.
2. **Deurenberg P, et al.** "Body mass index as a measure of body fatness:
   age- and sex-specific prediction formulas." *Br J Nutr.* 1991;65(2):105-114.
3. **Deurenberg-Yap M, et al.** "The paradox of low body mass index and high body fat
   percentage among Chinese, Malays and Indians in Singapore." *Int J Obes.* 2000.
4. World Health Organization. "BMI classification."

> Kalibrointikertoimet (0.675 / 0.7185 / 0.8475 / 0.163 / 0.05 / 0.548 / 0.651 / 0.7165 / 0.72)
> eivät tule kirjallisuudesta, vaan tämän projektin mitattuna takaisin johdetuista virallisen Ant Health -sovelluksen näyttämistä arvoista,
> kirjattuna [protokolladokumentin](PROTOCOL.md) mittausmuistiinpanoihin.
