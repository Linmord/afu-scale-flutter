# Usein kysytyt kysymykset

## Miksi BMI ei muutu sukupuolta vaihdettaessa?

Koska **BMI:n määritelmässä ei ole sukupuolta**:

```
BMI = paino(kg) ÷ pituus(m)²
```

Tämä on WHO:n standardimääritelmä, se riippuu vain painosta ja pituudesta. **Pituuden muuttuessa BMI muuttuu**, sukupuolen ei.

Se mikä todella vaihtuu sukupuolen mukaan, on kehonkoostumus:

| Mittari | Mies | Nainen |
| --- | --- | --- |
| kehon rasvaprosentti | Deurenberg: `1.10×BMI + 0.23×ikä − 11.22` (impedanssi ei ole mukana) | Segal: tarvitsee impedanssin, `(i1+i2)×0.675` yhdistettynä |
| kehon vesiprosentti | rasvaton massa × 0.7185 | rasvaton massa × 0.8475 |
| proteiini | paino × 0.163 | paino × 0.05 |
| luurankolihas% | lihasmassa × 0.548 | lihasmassa × 0.651 |
| ihonalaisrasva | rasva × 0.7165 | rasva × 0.72 |

Sama data (55.75kg / 163cm / 24 vuotta / impedanssi 430+387): mies **17.4%**, nainen **22.2%**, ero 4.8 prosenttiyksikköä.

## Vaihdoin sukupuolen/pituuden, mutta historian mittarit eivät muuttuneet?

Varhaisissa versioissa oli kaksi puutetta (korjattu):

1. BMI käytti **tietueeseen tallennettua vanhaa pituutta**, ei nykyistä profiilia
2. Ilman impedanssia olevat tietueet ohitettiin uudelleenlaskennassa, profiilia ei päivitetty lainkaan

Nyt: kun tietue kuuluu valittuun jäseneen, se lasketaan aina **uusimman profiilin** mukaan reaaliajassa; pituuden/sukupuolen/iän muutos näkyy heti.

## Impedanssi on aina 0 / ilmoitus "kehon impedanssia ei saatu tällä kertaa"

Impedanssin määrää **vain fyysinen olosuhde**, sitä ei saa komennolla päälle:

- molemmilla jaloilla pitää **seisoa paljain jaloin** neljällä elektrodilevyllä
- yksi jalka, sukat jalassa, liian kuiva jalkapohja → varmasti 0
- myös liian alhainen varaus (noin 10%) voi aiheuttaa epäonnistumisen

`04 d6`-komento vain nostaa reaaliaikapakettien tahtia, **se ei ole impedanssikytkin** (vahvistettu A/B-vertailumittauksella).

## Onko noin 10% varaus normaali?

On. Todellinen varaus otetaan reaaliaikapaketin `data[11]` 7 alimmasta bitistä, valmiustilassa mitattu moodi on **10%**.

Huom: tässä vaa'assa **ei ole** standardia `0x2A19` akkupalvelua, sen ominaisuuden lukeminen antaa roskaa (esim. 77%), tämä sovellus ei käytä sitä.

## Onko joka punnituksella "historia"?

Tämä on **normaali mekanismi**: jokainen punnitus tuottaa uuden tietueen, seuraavalla yhteydellä vaaka työntää "synkronoimattomat" tietueet.

- työnnön jälkeen vaaka merkitsee ne sisäisesti synkronoiduiksi, eikä työnnä uudelleen
- saman tietueen BLE-toistolähetykset deduplikoidaan avaimella `aika_paino`, kantaan ei tule duplikaatteja
- **vaa'assa ei ole poistokomentoa** (kaikki 29 virallista kirjoituskomentoa on tarkistettu), joten yhteyden aikana prosessia ei saa tappaa kesken, tallennusvirhe on pysyvä menetys

## Vaaka ei löydy skannauksessa / skannaus on hidasta

Selvitä järjestyksessä:

1. **Herätä kevyesti astumalla**: vaaka ei mainosta lepotilassa; herätyksen jälkeen näyttö syttyy ja lähetys jatkuu
2. **Varmista luvat**: Android 12+ vaatii "lähellä olevat laitteet" + "sijaintitiedot", `adb shell pm grant` voi antaa ne jälkeenpäin
3. **Älä käytä UUID-esisuodatusta**: mitattuna MIUI:ssa palvelu-UUID:llä suodattaminen pudottaa vaa'an, tämä projekti käyttää täyttä skannausta + callback-suodatusta
4. **Älä lisää `neverForLocation`-lippua**: tämä flag saa Android 12+:n suodattamaan tämän vaa'an beacon-mainonnan (logcatissa näkyy `Skipping data matching denylist`)

## Nimen vaihdon jälkeen data "katosi"

Tietueeseen tallennetaan **jäsenen nimi** (`record.unit`); jos nimeä vaihdettaessa sitä ei synkronoida, vanhat tietueet jäävät vanhan nimen alle.

- uusi versio synkronoi nimen vaihdon automaattisesti (`renameRecordOwner`)
- jo rikkoutunut data voidaan palauttaa: **Asetukset → Jäsenhallinta → Korjaa tietueiden omistajuus** listaa vanhat nimet ja **jäänteiset profiilit (sukupuoli/pituus/ikä)** sekä tietuemäärät, valitse kohdejäsen ja ne siirretään sen alle

## Yhteys katkeaa heti yhdistämisen jälkeen / toistuva uudelleenyhdistäminen

Varhainen versio ilmoitti yhteyshetkellä kerran virheellisesti `disconnected`, mikä laukaisi uudelleenyhdistämisen → sama tilaisuus kättelytettiin kahdesti → vaaka käsitteli sen uutena synkronointitilaisuutena ja työnsi historian uudelleen.

Nyt korjattu: ennen uudelleenyhdistämistä tarkistetaan `isConnected` ja lisätty `_connecting`-samanaikaisuusvahti.

## Kaksi samannimistä AFU-sovellusta puhelimessa

Vanhan RN-version paketin nimi on `com.aiyue.afuscale`, Flutter-version `com.aiyue.afu_scale`, työpöydällä molempien nimi on AFU.

Kun sovellus on auki, katso onko alareunassa kaksi välilehteä "Data / Asetukset" — jos on, se on Flutter-versio.
