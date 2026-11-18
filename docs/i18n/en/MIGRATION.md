# Migrating data from the old RN version

The Flutter version and the old React Native version **can be installed side by side** (different package names). After the first install, follow the steps below to bring the old records over.

## Where the old data lives

The old RN version keeps it in AsyncStorage (essentially the SQLite `RKStorage` table):

```bash
# list the data directory (needs a debuggable build or root)
adb shell "run-as com.aiyue.afuscale ls databases/"
# export
adb exec-out run-as com.aiyue.afuscale cat databases/RKStorage > afu_rn.db
# table schema: CREATE TABLE kv_data(key TEXT, value TEXT)
sqlite3 afu_rn.db "SELECT key, value FROM kv_data" > rn_export.json
```

## Import with a program

Once it has been exported as JSON (of the shape `{"afu_user_profiles":"[...]", "afu_records":"[...]", ...}`):

```dart
import 'data/migration.dart';
final count = await migrateFromJson(rnData);
```

## Key mapping table

| Old RN key | New Flutter key | Description |
| --- | --- | --- |
| `afu_user_profiles` | `afu_profiles` | member profiles |
| `afu_records` | `afu_records` | measurement records (with body composition / profile) |
| `afu_goal_weights` | `afu_goals` | goal weight |
| `afu_display_unit` | `afu_display_unit` | display unit |
| `afu_pending_history` | `afu_pending` | history awaiting assignment |
| `afu_bound_devices` | `afu_devices` | bound devices |

The migration only writes entries whose **target key is empty** and never overwrites existing data, so it is safe to run repeatedly.

## received.jsonl on the computer side

The receiver's `server/received.jsonl` is an independent backup; each line is structurally compatible with `MeasurementRecord` and can be converted by hand into an `afu_records` array and then imported as above.

## Verification

After migrating, open the data page: the member count and record count should match the old version. If some records show "no body impedance was measured this time", that means the original record had no impedance to begin with (the old version likewise could not compute body composition), not that the migration lost it.
