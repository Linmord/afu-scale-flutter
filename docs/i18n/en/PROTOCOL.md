# AFU-WL-TZ-A1 Body-Fat Scale Protocol · Plain-Language Edition

> **Who this is for**: people with basic networking knowledge (you know what an IP, a port and binary are) who have never touched a Bluetooth protocol.
> Read this one through and you should be able to write a program yourself that connects to this scale and reads out weight and body fat.
>
> **What this documents**: the protocol implementation that is **really running** inside `afu-flutter`, not an idealized textbook version.
> Every conclusion is tagged with its source of evidence:
> `[HCI]` = Bluetooth capture from the official Ant app · `[WT]` = WeighTrace docs ·
> `[VA]` = vitaloop-app source · `[AF]` = AntAF docs · `[tested]` = verified by us on real hardware.
>
> Corresponding code: `lib/core/protocol.dart` (frame assembly and parsing) · `lib/ble/scale_ble.dart` (connection and command sequence)

---

## 0. What we are doing, in one sentence

This scale is essentially a **talking electronic scale**. Between it and the phone:

1. The scale keeps broadcasting its name and identity into the air (like a shop hanging out its sign)
2. The phone sees the sign, connects, and receives two "mailboxes": one for sending, one for receiving
3. The phone stuffs in 8 little slips of paper of uniform format, in a fixed order (the **handshake**)
4. The scale starts dropping data packets into the receiving mailbox; the phone unpacks them byte by byte and computes weight and body fat

It sounds simple, but **every layer has a pitfall** — ordinary protocol documents only write "how it should be done",
while this one also writes down "how it actually goes wrong when you do it".

---

## 1. A few terms first

Bluetooth has a pile of jargon that confuses you the first time. Take a **parcel locker** as the analogy:

| Term | Parcel-locker analogy | Actual meaning |
| --- | --- | --- |
| **Advertising** | A for-rent ad pasted on the locker | The device can keep calling out "I am here, this is my name" without any connection |
| **Scan** | Building staff walking the map reading each ad | The phone does not connect, it only "listens" to who is calling out in the air |
| **GATT** | The locker system's whole set of rules | The standard rule set for transferring data over Bluetooth Low Energy (BLE) |
| **Service** | One locker, say "locker No. 3" | A collection of functions, numbered by UUID |
| **Characteristic** | One small compartment inside the locker | Where data is actually stored and fetched, with its own UUID |
| **Write** | You stuff a parcel in | Phone → device sends data |
| **Notify** | The locker pushes you a WeChat alert when it is full | Device → phone sends data proactively (no need for the phone to ask) |
| **UUID** | The locker's number, e.g. `0000ffb0-...` | A 128-bit (16-byte) number identifying some service or compartment |
| **MAC address** | An ID card number | The unique hardware address of a Bluetooth device, e.g. `B0:82:AB:07:76:24` |
| **Byte order (big-endian / little-endian)** | Whether the number 1234 is written "1 first or 4 first" | When several bytes make one number, whether the high bits come first or the low bits come first |

**Why you need to know byte order**: later you will find that for the same weight, the scale uses **big-endian** in one kind of packet and **little-endian** in the other,
get it backwards and you compute absurd numbers (reading 55.75kg as 14 tonnes, for example).

---

## 2. Step one: find it in the air (scan)

### 2.1 What the scale "shouts"

The scale's advertising carries these few things (we cross-checked with nRF Connect and system logs):

| Content | Value |
| --- | --- |
| Advertising name | `AFU-WL-TZ-A1` |
| Service UUID | `0xFFB0`, `0x1530` |
| Manufacturer data | Manufacturer ID `0x27AC` |
| **ServiceData** | `0x27AC` + **real MAC (6 bytes, reversed order) + 01** |
| Advertising interval | 999 milliseconds |

**Here is the counterintuitive part**: the Bluetooth address that shows up in the advertising (RemoteID)
**is not necessarily the scale's real MAC**. The real value hides inside ServiceData, and it is **stored backwards**.

```
ServiceData raw bytes:  24 76 07 AB 82 B0 01
                        └── 6B reversed ─────┘  └(fixed 01)
Read backwards:         B0:82:AB:07:76:24   ← the real MAC
```

> The first time we parsed this we overlooked "reversed order"; the MAC came out one position off and nothing would connect. [WT/tested]

### 2.2 How the phone recognises it

Three conditions, **any one of them hitting** is enough:

1. The advertising name contains `AFU-WL`
2. The UUID inside ServiceData is `0x27AC`
3. The advertised service list contains `0xFFB0`

### 2.3 Two pitfalls you must know

**Pitfall one: do not pre-filter by UUID**

Many tutorials teach you `startScan([ffb0's UUID])`, scanning only devices that carry this service — on this scale that **misses it**.
On MIUI this found nothing in 4 minutes in our tests; switching to "scan everything + filter it yourself in the callback" produced a result in 1 second. [tested]

**Pitfall two: do not add the `neverForLocation` flag**

From Android 12 on, when requesting the Bluetooth scan permission, if you attach the "this scan is not used for location" flag,
the system **silently filters out** certain kinds of advertising (this scale's advertising happens to be classified as a beacon).
The symptom: every permission granted, Bluetooth on, and it still finds nothing.

You can see it in logcat: `Skipping data matching denylist`. Removing the flag fixes it. [tested]

---

## 3. Step two: connect, and collect the two "mailboxes"

Connect using the **real MAC** decoded in step 2. Once connected you will see one service:

```
Service 0000ffb0-0000-1000-8000-00805f9b34fb
  ├── Characteristic FFB1  ← the phone writes commands here
  └── Characteristic FFB2  ← the scale sends data here (subscribe to notify first)
```

### 3.1 Writing mailbox FFB1: registered mail only

BLE writes come in two modes:

| Mode | Plain explanation | Supported by this scale? |
| --- | --- | --- |
| **WRITE** (with response) | Registered mail: you get told "received" | ✅ you must use this one |
| WRITE_NO_RESPONSE (without response) | Slip a note under the door and hope | ❌ **100% error** |

> This is the easiest place to get stuck: some BLE libraries default to the "without response" mode (better performance),
> and on this scale it throws every single time. We verified with 8 writes; all of them failed. [tested]

### 3.2 Receiving mailbox FFB2: "subscribe" first

The phone cannot just wait for the scale to send data; it has to call `setNotifyValue(true)` once (subscribe).
After subscribing, every message the scale sends invokes the phone's callback once, with 20 bytes as the argument.

```dart
// how flutter_blue_plus does it
await char.setNotifyValue(true);
char.onValueReceived.listen((data) {
  // data is a Uint8List, length 20
});
```

### 3.3 Device information you get for free

The scale also exposes a standard information service `0x180A` (Device Information), from which you can read:

| Field | Value |
| --- | --- |
| Manufacturer | ICOMON |
| Model | FG2313UWB-D |
| Firmware version | 1.2.3 |
| Software version | 1.3.0 |

⚠️ **Do not read the battery level characteristic `0x2A19`** — this scale has no such standard service at all,
what comes out is garbage (77%, say); the real battery level hides at another position inside the data packet (see §6.3). [tested]
---

## 4. Step three: understand the "envelope" format

Every message between phone and scale is **exactly 20 bytes**, not one byte more and not one byte less.
You can think of it as a standard envelope with a few fixed slots printed on it:

```
Byte:       [0]  [1]   [2] [3] [4] ... [17]   [18]   [19]
          ┌────┬────┬──────────────────────┬──────┬──────┐
Content:  │ AC │Type│        payload       │ tail │cksum │
          │    │    │      (16 bytes)      │(cmd) │      │
          └────┴────┴──────────────────────┴──────┴──────┘
```

| Position | Name | Description |
| --- | --- | --- |
| `[0]` | Start marker | Fixed `0xAC`, the equivalent of an "airmail" stamp on the envelope |
| `[1]` | Device type | The phone sends `0x27`, the scale answers `0x29` (each side declares its own identity) |
| `[2..17]` | Payload | 16 bytes; the real command and data go here |
| `[18]` | Tail | Command number, which helps tell which command this is |
| `[19]` | Checksum | Guards against data being corrupted in transit |

### 4.1 What the checksum is

Imagine you send a letter and write a number on the envelope flap: **"the total stroke count of every character inside"**.
The recipient opens it and counts again; if the two do not match, the letter was damaged on the way.

The rule here is:

```
checksum = (sum of bytes 2 through 18) & 0xFF
```

**What does `& 0xFF` mean**?

One byte holds at most 255. The sum can be far beyond 255 (2000, for example),
`& 0xFF` means "**keep only the last 8 binary bits**", which is the same as "take the remainder modulo 256".

```
Example: the sum comes out as 2000
2000 = binary 11111010000   (11 bits)
keep only the last 8 bits → 11010000 = 208
so the checksum is written as 208 (0xD0)
```

> ⚠️ Note the range is `[2..18]` — **the tail `[18]` is included, the checksum itself `[19]` is not**.
> Some documents online say "sum the payload only"; do that and it fails forever. [tested, checked byte by byte]

### 4.2 Payload beyond 16 bytes gets cut off

The frame builder has a truncation: bytes 2 through 17 are 16 slots, anything extra is simply discarded.
So **a single command carries at most 16 payload bytes**; if it will not fit, it has to be split.

---

## 5. Step four: send 8 commands in order (handshake)

Once connected you **cannot just ask for data**; you have to "report in" first. The scale has to know who you are before it will do any work.

The order is fixed, with **400 milliseconds** between commands (send too fast and the other side cannot keep up, and drops them).

| # | Command | Purpose | Payload (16 bytes) |
| --- | --- | --- | --- |
| 1 | `08` time sync | Tell the scale "what time it is" | `08` + Unix seconds (4 bytes) + time zone |
| 2 | `01` user | Tell the scale "who I am" | `01 00 01` + height + weight (2 bytes ×100) + age + sex |
| 3 | `02` slots | Overwrite the user configuration stored in the scale | two groups of 7 bytes each (slot 1 / slot 2) |
| 4 | `D0` full handshake | Report every piece of information once more in a single shot | time + time zone + unit + slot + height + weight + age + sex + target + `03 00` |
| 5 | `06` query | Ask for the configuration | `06` |
| 6 | `04 D6` | Raise the realtime packet rate | `04 D6` |
| 7 | `04 D8` | Request history records (first time) | `04 D8` |
| 8 | `04 D8` | Request history records (second time) | `04 D8` |

### 5.1 A few details that are easy to get wrong

**① How the time zone is computed**

```
utcQuarters = (UTC offset in minutes ÷ 15) & 0xFF
```

Why 15 minutes? Because some time zones in the world are offsets like UTC+5:30 or UTC+5:45 — half-hour and quarter-hour offsets;
using 15 minutes as the smallest unit represents every time zone exactly. China is UTC+8 → 480 minutes → 480÷15 = **32**.

**② Sex has only two values**

```
male = 1    female = 2
```

⚠️ This is not the programming "0/1" you are used to, it is **1 and 2**. Get it wrong and the body-fat formula picks the wrong branch, and the result is off by a factor of two.

**③ Weight is stored multiplied by 100**

Weight uses 2 bytes (maximum 65535), with the unit "hundredths of a kilogram".
So 55.75kg is stored as `5575` = hexadecimal `0x16 0b`.

**④ Height stores integers only**

Height occupies 1 byte only (maximum 255cm), so 168.6cm becomes **168**.

**⑤ Where these values come from**

```
weight = weight from the member profile → most recent measurement record → if neither, fall back to 60kg
target weight = what the user set → if unset, "reference weight × 0.75"
```

### 5.2 What is special about the third command, `02`

The official Ant app sends this command **only when "unbinding the device"**; its job is to clear the user slots stored in the scale.

We changed it to **send on every connection** — because we ran into residual old configuration inside the scale (height stuck at 111cm, impossible to change),
and resending this command overwrites it. This is an experimental practice; see §8 for the side effects. [HCI]

---

## 6. Step five: read what the scale says back

The packets the scale sends are also 20 bytes; `[0]` is `0xAC` but `[1]` becomes `0x29`.
The real answer to "which kind of packet is this" hides in `[2]`:

| Value of `[2]` | Packet type | When it appears |
| --- | --- | --- |
| `0x00` | realtime packet | During a measurement, one every 100~150ms |
| `0x80` | stable packet | The weight has settled |
| `0x02` | **locked packet** | Measurement complete, carries the final impedance (the most important one) |
| `0x01` | history packet | After connecting, the scale pushes unsynced old records on its own |
| `0x06` | config block | Answers the `06` query, 5 packets in a row |

### 6.1 How weight is computed from 3 bytes

This is the part of the whole document you most need to understand. Start with the formula the realtime packet uses (**little-endian style**):

```
weight(g) = ((d[3] - 0x68) × 65536 + d[4] × 256 + d[5]) ÷ 1000
```

**Why multiply by 65536 and 256?**

Because a single byte holds only 0~255, which cannot express a few hundred kilograms (hundreds of thousands when measured in grams).
So **three bytes are combined into one "big number"**:

```
Think of the three bytes as three dials:
  dial 1 (d[3]): each step = +65536
  dial 2 (d[4]): each step = +256
  dial 3 (d[5]): each step = +1

This is like decimal: hundreds ×100, tens ×10, units ×1
except these three "digits" are base 256, so the weights are 65536 / 256 / 1
```

**What is the `- 0x68` doing there?**

The factory "zero point" of the scale is not 0 but `0x68` (104 decimal). It is like an old mechanical bathroom scale whose needle was never aligned to zero;
you have to subtract this offset first.

**`÷ 1000`**: because the computed unit is grams, and you need kilograms.

### 6.2 Why the locked packet's weight moved position and changed notation

In the locked packet the weight lives in **`d[10..12]`** (not `d[3..5]`), and the formula becomes:

```
weight(g) = ((d[10]<<16 | d[11]<<8 | d[12]) - 0x680000) ÷ 1000
```

**What are `<<16` and `|`?**

`<<16` means "shift left 16 bits", equivalent to **× 65536**; `|` "joins the three parts together".
So this formula and the one above are essentially **the same algorithm**, just written in a more "programmer" style:

```
notation A (plain)       notation B (bit ops)
d[10] × 65536            d[10] << 16
d[11] × 256              d[11] << 8
d[12] × 1                d[12]
add all three            join all three with |
```

⚠️ But the **offset differs**: here it is `0x680000` (not `0x68`).
Because the number as a whole was scaled up 65536 times, the offset has to scale up with it.

**A complete worked example** (one we captured on real hardware):

```
raw packet: ac 29 02 00 01 ae 01 83 01 80 68 d9 c6 ...
                                          └──┬──┘
                                          3 weight bytes

d[10]=0x68  d[11]=0xD9  d[12]=0xC6
joined: 0x68d9c6 = 6,871,494
minus offset: 6,871,494 - 0x680000(6,815,744) = 55,750
divided by 1000: 55,750 ÷ 1000 = 55.75

→ weight 55.75 kg ✅

impedance in the same packet:
impedance1 = (d[4]<<8 | d[5]) = (0x01<<8 | 0xae) = 256 + 174 = 430 Ω
impedance2 = (d[6]<<8 | d[7]) = (0x01<<8 | 0x83) = 256 + 131 = 387 Ω
```

### 6.3 Where the battery level hides

**There is no standard battery service** (as §3.3 said). The real battery level sits in the **low 7 bits** of `d[11]` in the realtime packet:

```
battery = d[11] & 0x7F
```

`& 0x7F` = "keep only the low 7 bits" (the top bit is treated as a flag and does not count towards the battery level).

⚠️ **Two traps**:
1. During a measurement `d[11]` becomes `0x64` (=100); that is the "measurement complete" status flag, **not the battery level**, and must be excluded
2. This scale's battery level has shown around **10%** for a long time (the mode across 915 packet captures); it is not broken

### 6.4 History packets (`0x01`)

After a successful connection the scale automatically pushes down every old record that has "never been synced"; each record is also 20 bytes:

```
time        = d[3..6]   (Unix timestamp, 4 bytes, big-endian)
weight      = ((d[8]<<16 | d[9]<<8 | d[10]) - 0x680000) / 1000
impedance1  = (d[11]<<8 | d[12])
impedance2  = (d[13]<<8 | d[14])
```

**Trigger condition** (this one is crucial):

```
After writing "08 time sync + 01 user + D0 full handshake", the scale pushes every unsynced record down by itself,
04D8 is not required (sending it is safer).
```

After the push, the scale marks these records internally as "synced" and **never pushes them again**, until a new measurement is produced.
If the scale held no records to begin with, the connection is completely silent — that is normal, not a fault.

⚠️ **The same timestamp may arrive 3 times** (Bluetooth can deliver duplicates), so deduplication is mandatory.
Our approach is to form a unique key from `timestamp_weight` and deduplicate on it.

### 6.5 How to tell "which stage the measurement is at"

```
recv 0x02                           → done (final impedance present)
recv 0x00 or 0x80, and d[11] >= 100 → measuring impedance
anything else                       → weighing
```

**The single most important sentence about impedance**:

> Impedance is determined by **physical conditions alone**. You get a value only when both bare feet press the four electrode pads and form a circuit through the body;
> with one foot, with socks on, or with a very dry sole, impedance is always **0** — no command can conjure it up. [A/B comparison tested]
>
> The claim online that "sending `04 D6` turns on impedance measurement" is **wrong** — it only makes the realtime packets more numerous (26→77).
> The actual impedance numbers appear only in bytes 4~8 of the `0x02` locked packet.
---

## 7. What one complete measurement looks like, start to finish

```
Timeline
│
├─ the user steps on the scale, the scale screen lights up
│
├─ scale: calls out in advertising "I am AFU-WL-TZ-A1"        —— every 999ms, non-stop
│
├─ phone: finds it → connects by MAC → subscribes to FFB2
│
├─ phone: sends the 8 commands in order (400ms apart)         —— about 3.2s
│    08 time sync → 01 user → 02 slots → D0 handshake
│    → 06 query → 04D6 → 04D8 → 04D8
│
├─ scale: starts pushing 0x00 realtime packets (every 100~150ms)  —— the number is jumping
├─ scale: weight stabilises → pushes 0x80 stable packets
├─ scale: enters impedance measurement → d[11] >= 100
├─ scale: measurement complete → repeats 0x02 locked packets (~6s)  —— with the final impedance
│
├─ phone: parses the locked packet → computes weight + body fat → stores it
│
├─ scale: if unsynced old records remain → pushes 0x01 history packets
│         then marks them "synced" inside the scale
│
└─ end (the scale sleeps on its own after a while)
```

**Why does the locked packet repeat for 6 seconds**? Because Bluetooth may drop packets; repeating a few times guarantees the phone receives it.
The phone only has to receive it once and can then stop.

---

## 8. Pitfalls we really did step in

This section is the most valuable part of the whole document — **none of the four reverse-engineering documents online mention it**.

### Pitfall 1 · Writing a characteristic only accepts "registered mail" mode

`FFB1` supports write with response only. Use the without-response mode and it **throws 100% of the time**.
(vitaloop uses Kotlin, whose default is with-response, so it never hit this; some JS/Dart libraries default to without.)

### Pitfall 2 · Android 12's "denylist" silently eats the advertising

When the scan permission carries the `neverForLocation` flag, the system classifies this scale's advertising as a beacon and filters it out.
Every permission granted, Bluetooth on, and it still finds nothing; logcat holds a single line, `Skipping data matching denylist`.

### Pitfall 3 · On MIUI two Bluetooth libraries differ 400 times in speed

The same phone and the same scale:

| Library | Scan time |
| --- | --- |
| `flutter_blue_plus` | **under 1 second** |
| `react-native-ble-plx` | **about 7 minutes** |

This is a **difference in the libraries' wrapper layers**, unrelated to permissions. It is also the direct reason we eventually rewrote from RN to Flutter.

### Pitfall 4 · Filtering the scan by UUID misses the scale

`startScan([ffb0's UUID])` returned nothing on MIUI for 4 minutes; a full scan plus filtering yourself in the callback finds it in a second.

### Pitfall 5 · Right after connecting, the state "pretends to disconnect"

At the very instant the GATT is established, the connection state briefly misreports `disconnected`.
If you simply hang a "reconnect on disconnect" timer there, you get a **double handshake** — the scale treats it as a new sync session and pushes the whole history again.

The fix: re-check `isConnected` before reconnecting, and add a "connection in progress" concurrency lock.

### Pitfall 6 · The threshold for "did the weight change" must not be too large

We want to write the newest weight back into the member profile, which requires deciding "did the value change".

| Threshold | Consequence |
| --- | --- |
| 1 kg | a 0.1kg gain counts as "unchanged", so it never updates |
| 0.05 kg | floating point precision: 55.85 − 55.80 comes out as 0.0499…, and it is still blocked |
| **0.001 kg** | ✅ what we finally adopted |

### Pitfall 7 · Men and women need completely different body-fat formulas

```
male   = Deurenberg formula: 1.10×BMI + 0.23×age − 11.22   (impedance not involved!)
female = Segal formula: needs impedance, combine the two as (i1+i2)×0.675
```

**One more thing worth knowing**: the body fat percentage shown on the scale's own screen and the one the app computes **differ by a few tenths of a percentage point**.
Because the scale uses the vendor's proprietary algorithm (not published), while the app uses the formulas from the public papers above.

**BMI is always identical** between the two (BMI looks only at weight and height, there is no room for algorithmic disagreement there).

Use the wrong sex and the result nearly doubles. For example (55.75kg / 163cm / 24 years old / impedance 430+387):

| Which formula | Computed body fat percentage |
| --- | --- |
| male formula | 17.4% |
| female formula | 22.2% |

### Pitfall 8 · The scale holds "the previous user configuration"

The scale keeps the user slot last written to it. If the profile in the app changed but the scale still holds the old one,
the body fat shown on the scale's screen is obviously wrong. That is why we send the `02` command on every connection to overwrite it.

### Pitfall 9 · The battery level is not 77%, it is 10%

| Source | Reading | Genuine? |
| --- | --- | --- |
| standard battery service `0x2A19` | 77% | ❌ garbage (this service does not exist at all) |
| realtime packet `d[11] & 0x7F` | 10% | ✅ the real value (mode across 915 packet captures) |

### Pitfall 10 · The scale has no "delete record" feature

We checked all 29 official write commands: **there is no delete or clear instruction of any kind**.

That means that once the scale marks a record as "synced", no app can retrieve it any more.
**A missed save in the app = permanent loss**. So never kill the process midway while connected.

---

## 9. Where we differ from the four reverse-engineering documents online

We referenced five open source projects, but there are plenty of places where **following them leads you into a ditch**.
This section lists the gaps between what the documents claim and what we measured, so those who come later take fewer detours.

### 9.1 What the documents say vs. what we measured

| # | What the document says | What we measured | Evidence |
| --- | --- | --- | --- |
| 1 | [AF] The weight is a full 32 bits, split with `& 0x3FFFF` | The realtime/stable packets use `((d[3]-0x68)×65536+d[4]×256+d[5])/1000`; **in the locked packet the weight is at d[10:13]**, two different positions | 55.75kg verified across the whole chain |
| 2 | [AF] The scale does not advertise while asleep; you must step on it to light the screen | This scale **advertises even with the screen off** (999ms); nRF found it in 2 seconds, the test bench in 84ms | nRF + communication log |
| 3 | [AF] The profile packet is resent every 15 seconds, so a heartbeat is needed | **The heartbeat is not required**; impedance still comes out reliably without it | works normally in testing without a heartbeat |
| 4 | [VA] Fill weight/target with 0 during the handshake | Filling in **real values** is better; the slot inside the scale then matches the profile | test log |
| 5 | [VA] One `D0` handshake packet is enough | Without the `01` user command **impedance does not trigger**; the full 8-command sequence is the most reliable | before/after comparison |
| 6 | [WT] The ServiceData payload carries an `AC27` prefix | payload = **6-byte MAC (reversed) + 01**, no prefix | raw byte check |
| 7 | [WT] The `D6` command is the source of impedance | `D6` only makes realtime packets more numerous (26→77); **the final impedance is in the `0x02` packet at d[4:8]** | A/B comparison |
| 8 | [WT/HCI] checksum = sum of the payload | Precisely **`sum(frame[2..18]) & 0xFF`** (**tail [18] included**) | byte-by-byte check |

### 9.2 Things none of the four documents describe, which we found ourselves

1. `FFB1` **supports write with response only** (see pitfall 1)
2. On Android 12 `neverForLocation` causes the advertising to be filtered by the denylist (pitfall 2)
3. On MIUI the two Bluetooth libraries differ 400 times in speed (pitfall 3)
4. Pre-filtering by UUID misses the scale (pitfall 4)
5. State flapping at the instant of connection causes a double handshake (pitfall 5)
6. The profile write-back threshold has to be as small as 0.001kg (pitfall 6)
7. The BIA formulas for men and women are completely different (pitfall 7)
8. The real meaning of the `02` command is "write two user slots, 7 bytes each"
9. The true battery level is in the low 7 bits of `d[11]`, and this scale has no `0x2A19` service (pitfall 9)
10. The "synced" mark takes effect for **any** app, and with no delete command that means a missed save is permanent loss (pitfall 10)

### 9.3 Deliberate differences from the official Ant app

| What the official app does | What we do | Why |
| --- | --- | --- |
| sends `02` only when unbinding | sends it on every connection (experimental) | overwrites residual old user configuration in the scale (once stuck at 111cm) |
| resends the profile packet every 15 seconds (heartbeat) | does not send it | not required in testing, saves power |
| sends `04D8` once | sends it twice | for safety; no side effects observed |
| iOS client | Android / Flutter | different scan strategy (see pitfall 3, pitfall 4) |

### 9.4 Questions not yet verified

- [ ] the long-term side effects of sending `02` on every connection (if history keeps being pushed again and again, revert to "send only when unbinding")
- [ ] whether sending `deviceType` `0x29` is required on some firmware (vitaloop works with 0x29 as well)
- [ ] whether the 0.4 percentage point gap against the scale's screen stays constant across weights
- [ ] whether the 15-second heartbeat is necessary on very long connections (>10 minutes)

---

## 10. How to debug it yourself

### 10.1 Turning on the communication log inside the app

The log entry point is hidden by default (an easter egg):

> **Settings → About → tap the version number 7 times**

Once unlocked, a "Comm N" button appears in the top right of the measurement page, and you can see the raw bytes of every send and receive.

### 10.2 The log file is written to disk automatically

Written every 3 seconds while connected (and forcibly once more on disconnect):

```
/storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

```bash
adb pull /storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
```

Format: `时间 方向(→发出 / ←收到) 原始20字节 [命令名或包类型]`

### 10.3 Keywords at the system level

| Symptom | logcat keyword |
| --- | --- |
| scanning filtered by the system | `Skipping data matching denylist` |
| scan progress tracing | `SCAN_STEP` |
| write fails | `PlatformException` + `not supported` |

### 10.4 Cross-checking with nRF Connect

When your own program behaves oddly, first connect manually with **nRF Connect** (a general-purpose BLE debugging tool for the phone),
and check whether it receives data normally. If nRF cannot do it either, the problem is physical or environmental (the scale was not stepped on to wake it, it is too far away, the battery is low).

---

## 11. Reference material

This protocol was not guessed out of thin air; it mainly draws on these public reverse-engineering results:

| Project | Language / platform | Contribution |
| --- | --- | --- |
| [Fatpandac/AFUScale](https://github.com/Fatpandac/AFUScale) | iOS / Swift | the earliest protocol reverse engineering, the basis of the command sequence |
| [Mzdyl/ant-afu-welland-scale](https://github.com/Mzdyl/ant-afu-welland-scale) | Python | frame format and weight encoding |
| [monkey-wenjun/vitaloop-app](https://github.com/monkey-wenjun/vitaloop-app) | Android / Kotlin | single-handshake mode, usage of `deviceType` |
| [Xuan-lprk/WeighTrace](https://github.com/Xuan-lprk/WeighTrace) | documentation | advertising ServiceData layout, scan strategy |
| [ZeroOneCN/AntAF](https://github.com/ZeroOneCN/AntAF) | documentation | the 32-bit weight encoding, profile packet heartbeat |

We also used HCI captures from this machine (`ant_cleanup.log`, `unbind_official.log`) as evidence for where the `02` command comes from.

---

## Appendix: a cheat sheet for anyone who wants to implement it themselves

```
1. Scan: scan everything, filter in the callback by "name contains AFU-WL / ServiceData is 27AC / service list contains FFB0"
2. Get the MAC: the 6 bytes in ServiceData, reversed
3. Connect → obtain service FFB0
4. Subscribe to notifications on FFB2 (setNotifyValue(true))
5. Write the 8 commands to FFB1, 400ms apart, all in "with response" mode
6. Listen to the FFB2 callback and tell the packet type from [2]
7. 0x02 packet: weight at d[10:13], impedance at d[4:8]; subtract the offset and divide by 1000 in both cases
8. Once 0x02 arrives you are done — store it
```

**The three places things go wrong most easily**: the write mode (must be with response), the checksum range (includes [18]), and the weight offset (`0x68` vs `0x680000`).
