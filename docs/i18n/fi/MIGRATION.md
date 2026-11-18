# Datan migraatio vanhasta RN-versiosta

Flutter-versio ja vanha React Native -versio **voidaan asentaa rinnakkain** (pakettien nimet eroavat). Ensimmäisen asennuksen jälkeen siirrä vanhat tietueet alla olevilla vaiheilla.

## Missä vanhan version data on

Vanha RN-versio tallentaa AsyncStorageen (pohjimmiltaan SQLiten `RKStorage`-taulu):

```bash
# katso datakansio (vaatii debugattavan paketin tai rootin)
adb shell "run-as com.aiyue.afuscale ls databases/"
# vie ulos
adb exec-out run-as com.aiyue.afuscale cat databases/RKStorage > afu_rn.db
# taulurakenne: CREATE TABLE kv_data(key TEXT, value TEXT)
sqlite3 afu_rn.db "SELECT key, value FROM kv_data" > rn_export.json
```

## Tuonti ohjelmalla

Kun data on viety JSON-muotoon (muodossa `{"afu_user_profiles":"[...]", "afu_records":"[...]", ...}`):

```dart
import 'data/migration.dart';
final count = await migrateFromJson(rnData);
```

## Avainten vastaavuustaulukko

| Vanha RN-avain | Uusi Flutter-avain | Selitys |
| --- | --- | --- |
| `afu_user_profiles` | `afu_profiles` | jäsenprofiilit |
| `afu_records` | `afu_records` | mittaustietueet (sisältää kehonkoostumuksen / profiilin) |
| `afu_goal_weights` | `afu_goals` | tavoitepaino |
| `afu_display_unit` | `afu_display_unit` | näyttöyksikkö |
| `afu_pending_history` | `afu_pending` | kohdistamaton historia |
| `afu_bound_devices` | `afu_devices` | sidotut laitteet |

Migraatio kirjoittaa vain merkinnät, joiden **kohdeavain on tyhjä**, ei ylikirjoita olemassa olevaa dataa, ja sen voi suorittaa turvallisesti toistamiseen.

## Tietokoneen received.jsonl

Vastaanottimen `server/received.jsonl` on itsenäinen varmuuskopio, jokaisen rivin rakenne on yhteensopiva `MeasurementRecord`-rakenteen kanssa; sen voi käsin muuntaa `afu_records`-taulukoksi ja tuoda yllä olevalla tavalla.

## Vahvistus

Migraation jälkeen avaa datasivu: jäsenmäärän ja tietuemäärän pitäisi vastata vanhaa versiota. Jos jotkin tietueet näyttävät "kehon impedanssia ei saatu tällä kertaa", se tarkoittaa, ettei alkuperäisessä tietueessa ollut impedanssia (vanha versiokaan ei pystynyt laskemaan kehonkoostumusta), ei sitä että migraatio hävitti dataa.
