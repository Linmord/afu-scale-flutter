# AFU

<p align="center">
  <a href="../../../README.md">简体中文</a> &middot; <a href="../zh-Hant/README.md">繁體中文</a> &middot; <a href="../ja/README.md">日本語</a> &middot; <a href="../de/README.md">Deutsch</a> &middot; <a href="../fi/README.md">Suomi</a> &middot; <b>English</b>
</p>


**AFU-WL-TZ-A1** (Ant Afu × Welland ICOMON) body-fat scale Android client · Flutter rewrite  
Local-first · No account · No cloud sync · 5 languages · Light and dark themes

<p align="center">
  <img src="../../screenshots/home.jpg" width="200" alt="Data page">
  &nbsp;&nbsp;
  <img src="../../screenshots/sett.jpeg" width="200" alt="Feature overview">
  &nbsp;&nbsp;
  <img src="../../screenshots/proto.jpeg" width="200" alt="Communication log">
</p>

<p align="center"><sub>Data page · Feature overview · Communication log (visible in debug mode)</sub></p>

## Features

- **Scan in under a second**: the same phone and the same scale took 7 minutes with the old React Native version
- **Ring gauge**: weighing → impedance → done, a three-stage animation
- **Multiple members**: profile management, renaming updates history, orphan record repair
- **Data**: 72H / 7d / 30day / custom range filters, trend charts, batch push · transfer · delete
- **LAN sync**: HTTP push to a receiver you host yourself
- **Fully open algorithm**: the BIA formulas and every coefficient are documented one by one, separating the paper's original formulas from measured calibration values
- 5 languages · Light and dark themes · kg / lb / jin

## Documentation

| Document | Contents |
| --- | --- |
| [Protocol · Plain-language edition](PROTOCOL.md) | From "how to find the scale" to "how bytes become weight", including 10 pitfalls found in real testing |
| [Protocol · Specification edition](PROTOCOL_SPEC.md) | Technical specification for implementers: field-level definitions, state machine, test vectors, conformance checklist |
| [Body composition algorithm](ALGORITHM.md) | How body fat percentage / water / muscle / skeletal muscle are computed, with formulas and coefficient provenance |
| [Build and install](BUILD.md) | Environment requirements, two pitfalls you will definitely hit, wireless install |
| [Data migration](MIGRATION.md) | Import history records from the old RN version |
| [FAQ](FAQ.md) | Why BMI does not vary by sex, zero impedance, battery level, the history mechanism |

## Quick start

```bash
git clone https://github.com/Linmord/afu-scale-flutter.git
cd afu-scale-flutter
flutter pub get
flutter build apk --release
```

> ⚠️ The project path **must not contain Chinese characters**, otherwise Gradle reports an error outright. See the [build documentation](BUILD.md).

Every push to `main` builds an APK automatically ([`.github/workflows/build.yml`](../../../.github/workflows/build.yml)); the artifact appears under Artifacts in Actions.

## Legacy version

The React Native version is **no longer maintained** → [Linmord/afu-scale-app](https://github.com/Linmord/afu-scale-app)

## Disclaimer

Unofficial client, not affiliated with Ant Afu / Welland (ICOMON). The protocol was derived from public packet captures and reverse engineering and may stop working after firmware upgrades.
Body composition values are estimates from BIA formulas, for personal trend reference only, and are not a basis for medical diagnosis.
