# FAQ

## Why does BMI not change when the sex is switched?

Because **the definition of BMI contains no sex**:

```
BMI = weight(kg) ÷ height(m)²
```

This is the WHO standard definition and depends only on weight and height. **Change the height and BMI changes**; sex does not.

What really changes with sex is body composition:

| Metric | Male | Female |
| --- | --- | --- |
| body fat percentage | Deurenberg: `1.10×BMI + 0.23×age − 11.22` (impedance not involved) | Segal: needs impedance, combined as `(i1+i2)×0.675` |
| body water percentage | fat-free mass × 0.7185 | fat-free mass × 0.8475 |
| protein | weight × 0.163 | weight × 0.05 |
| skeletal muscle percentage | muscle mass × 0.548 | muscle mass × 0.651 |
| subcutaneous fat | body fat × 0.7165 | body fat × 0.72 |

For the same data set (55.75kg / 163cm / 24 years old / impedance 430+387): male **17.4%**, female **22.2%**, a difference of 4.8 percentage points.

## I changed sex/height but the history record metrics did not change?

Early versions had two defects (fixed since):

1. BMI used the **old height stored in the record**, not the current profile
2. records without impedance were skipped outright on recalculation, so the profile never updated at all

Now: when a record belongs to the currently selected member it is always computed live from the **latest profile**; changing height/sex/age takes effect immediately.

## Impedance is always 0 / it says "no body impedance was measured this time"

Impedance **is determined by physical conditions alone**; no command can switch it on:

- both feet must be **bare** and press all four electrode pads at the same time
- one foot, socks on, or a very dry sole → always 0
- when the battery is very low (around 10%) it can fail as well

The `04 d6` command only raises the realtime packet rate; it is **not an impedance switch** (verified with an A/B control test).

## Is a battery reading of around 10% normal?

Normal. The real battery level is the low 7 bits of `data[11]` in the realtime packet; when idle the measured mode is exactly **10%**.

Note: this scale has **no** standard `0x2A19` battery service; reading that characteristic returns garbage (77%, for instance), and this app does not trust it.

## Every weigh-in produces a "history record"?

That is the **normal mechanism**: every weigh-in creates a new record, and on the next connection the scale pushes out the records that are "not yet synced".

- once the push finishes the scale marks them synced internally and does not push them again
- duplicate BLE broadcasts of the same record are deduplicated by `timestamp_weight` and never stored twice
- **the scale has no delete command** (all 29 official write commands were checked), so do not kill the process midway while connected: a missed save is permanent loss

## The scale is not found / scanning is slow

Check in this order:

1. **wake it with a light step**: the scale does not advertise while asleep; only after it is woken and the screen lights up does it keep sending
2. **confirm the permissions**: Android 12+ needs "Nearby devices" + "Location", and `adb shell pm grant` can grant them
3. **do not pre-filter by UUID**: on MIUI, filtering by service UUID actually misses this scale in our tests; this project scans everything and filters in the callback
4. **do not add `neverForLocation`**: that flag makes Android 12+ filter out this scale's beacon advertising (visible in logcat as `Skipping data matching denylist`)

## After renaming, the data "disappeared"

A record stores the **member's name** (`record.unit`); if a rename is not propagated, the old records still hang under the old name.

- the new version propagates the rename automatically (`renameRecordOwner`)
- data already broken this way can be recovered with **Settings → Member management → Repair record ownership**: it lists the old names with their **residual profiles (sex/height/age)** and record counts, and you pick a target member to assign them to

## It disconnects right after connecting / reconnects over and over

Early versions misreported `disconnected` once at the instant the connection was established, which triggered a reconnect → the same session handshook twice → the scale treated it as a new sync session and pushed the history again.

Fixed now: `isConnected` is re-checked before reconnecting, plus a `_connecting` concurrency guard.

## Two AFU apps with the same name on the phone

The old RN version uses the package name `com.aiyue.afuscale`, the Flutter version `com.aiyue.afu_scale`; both show AFU as the desktop name.

Open the app and check whether there are two tabs, "Data / Settings", at the bottom — if there are, it is the Flutter version.
