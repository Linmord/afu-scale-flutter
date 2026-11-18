# 旧 RN 版からのデータ移行

Flutter 版と旧 React Native 版は**共存してインストールできる**（パッケージ名が異なる）。初回インストール後に次の手順で旧記録を移行する。

## 旧版のデータはどこにあるか

旧 RN 版は AsyncStorage に保存している（実体は SQLite の `RKStorage` テーブル）：

```bash
# データディレクトリを確認（デバッグ可能なビルドか root が必要）
adb shell "run-as com.aiyue.afuscale ls databases/"
# エクスポート
adb exec-out run-as com.aiyue.afuscale cat databases/RKStorage > afu_rn.db
# テーブル構造：CREATE TABLE kv_data(key TEXT, value TEXT)
sqlite3 afu_rn.db "SELECT key, value FROM kv_data" > rn_export.json
```

## プログラムでインポートする

JSON へ書き出した後（`{"afu_user_profiles":"[...]", "afu_records":"[...]", ...}` のような形）に：

```dart
import 'data/migration.dart';
final count = await migrateFromJson(rnData);
```

## キー対応表

| 旧 RN キー | 新 Flutter キー | 説明 |
| --- | --- | --- |
| `afu_user_profiles` | `afu_profiles` | メンバープロフィール |
| `afu_records` | `afu_records` | 測定記録（体組成 / profile を含む）|
| `afu_goal_weights` | `afu_goals` | 目標体重 |
| `afu_display_unit` | `afu_display_unit` | 表示単位 |
| `afu_pending_history` | `afu_pending` | 割り当て待ちの履歴 |
| `afu_bound_devices` | `afu_devices` | 紐付け済みデバイス |

移行は**対象キーが空**のエントリにだけ書き込み、既存データを上書きしない。何度実行しても安全。

## PC 側の received.jsonl

受信側の `server/received.jsonl` は独立したバックアップで、各行の構造は `MeasurementRecord` と互換。手作業で `afu_records` 配列に変換し、上記の方法でインポートできる。

## 検証

移行後にデータページを開き、メンバー数と記録数が旧版と一致していることを確認する。一部の記録に「今回の測定では体インピーダンスが取れていない」と表示される場合、その記録にもともとインピーダンスが無かったという意味で（旧版でも体組成は算出できない）、移行で失われたわけではない。
