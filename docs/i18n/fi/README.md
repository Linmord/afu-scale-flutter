# AFU

<p align="center">
  <a href="../../../README.md">简体中文</a> &middot; <a href="../zh-Hant/README.md">繁體中文</a> &middot; <a href="../ja/README.md">日本語</a> &middot; <a href="../de/README.md">Deutsch</a> &middot; <b>Suomi</b> &middot; <a href="../en/README.md">English</a>
</p>


**AFU-WL-TZ-A1** (Ant Afu × Welland ICOMON) -kehonkoostumusvaa'an Android-sovellus · Flutter-uudelleenkirjoitus  
Paikallinen ensisijaisesti · ei tiliä · ei pilvisynkronointia · 5 kieltä · vaalea ja tumma teema

<p align="center">
  <img src="../../screenshots/home.jpg" width="200" alt="Datasivu">
  &nbsp;&nbsp;
  <img src="../../screenshots/sett.jpeg" width="200" alt="Toimintojen yleiskuva">
  &nbsp;&nbsp;
  <img src="../../screenshots/proto.jpeg" width="200" alt="Viestintäloki">
</p>

<p align="center"><sub>Datasivu · Toimintojen yleiskuva · Viestintäloki (näkyvissä debug-tilassa)</sub></p>

## Ominaisuudet

- **Skannaus alle sekunnissa**: samalla puhelimella ja samalla vaa'alla vanha React Native -versio tarvitsi 7 minuuttia
- **Rengasmainen mittaristo**: punnitus → impedanssi → valmis, kolmivaiheinen animaatio
- **Useita käyttäjiä**: profiilien hallinta, nimen vaihto synkronoi historian, orpojen tietueiden korjaus
- **Data**: 72H / 7d / 30day / mukautettu aikaväli, trendikaavio, joukkosyöttö · siirto · poisto
- **Lähiverkkosynkronointi**: HTTP-push itse rakennettuun vastaanottimeen
- **Algoritmi täysin julkinen**: BIA-kaava ja jokainen kerroin selitetty kohta kohdalta, erottaen artikkelin alkuperäisen kaavan ja mitatut kalibrointiarvot
- 5 kieltä · vaalea ja tumma teema · kg / lb / 斤

## Dokumentaatio

| Dokumentti | Sisältö |
| --- | --- |
| [Protokolla · kansantajuinen versio](PROTOCOL.md) | Siitä "miten vaaka löydetään" siihen "miten tavuista tulee paino", sisältää 10 käytännössä havaittua sudenkuoppaa |
| [Protokolla · spesifikaatio](PROTOCOL_SPEC.md) | Toteuttajille suunnattu tekninen spesifikaatio: kenttätason määritelmät, tilakone, testivektorit, yhdenmukaisuuslista |
| [Kehonkoostumusalgoritmi](ALGORITHM.md) | Miten kehon rasvaprosentti / vesiprosentti / lihasmassa / luurankolihas lasketaan, sisältää kaavat ja kertoimien lähdemerkinnät |
| [Koontaminen ja asennus](BUILD.md) | Ympäristövaatimukset, kaksi pakollista sudenkuoppaa, langaton asennus |
| [Datan migraatio](MIGRATION.md) | Historia-aineiston tuonti vanhasta RN-versiosta |
| [Usein kysytyt kysymykset](FAQ.md) | Miksi BMI ei muutu sukupuolen mukaan, impedanssi 0, akku, historialuettelomekanismi |

## Pika-aloitus

```bash
git clone https://github.com/Linmord/afu-scale-flutter.git
cd afu-scale-flutter
flutter pub get
flutter build apk --release
```

> ⚠️ Projektin polku **ei saa sisältää kiinankielisiä merkkejä**, muuten Gradle antaa suoraan virheen. Katso tarkemmin [koontidokumentti](BUILD.md).

Jokainen push `main`-haaraan koontaa APK:n automaattisesti ([`.github/workflows/build.yml`](../../../.github/workflows/build.yml)), tuotos löytyy Actions-välilehden Artifacts-kohdasta.

## Vanha versio

React Native -versio on **lopetettu ylläpidosta** → [Linmord/afu-scale-app](https://github.com/Linmord/afu-scale-app)

## Vastuuvapauslauseke

Epävirallinen asiakassovellus, ei sidoksissa Ant Afu / Welland (ICOMON) -yrityksiin. Protokolla on johdettu julkisesta liikenteen kaappauksesta ja takaisinmallinnuksesta, ja voi lakata toimimasta laiteohjelmiston päivityksen myötä.
Kehonkoostumus on BIA-kaavalla arvioitu, tarkoitettu vain henkilökohtaiseen trendiviitteeseen, ei lääketieteellisen diagnoosin perustaksi.