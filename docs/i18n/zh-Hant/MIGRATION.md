# 從舊 RN 版遷移資料

Flutter 版與舊 React Native 版**可並存安裝**（套件名不同）。首次安裝後按下面步驟把舊記錄遷過來。

## 舊版資料在哪

舊 RN 版存在 AsyncStorage（本質是 SQLite 的 `RKStorage` 表）：

```bash
# 檢視資料目錄（需要可除錯套件或 root）
adb shell "run-as com.aiyue.afuscale ls databases/"
# 匯出
adb exec-out run-as com.aiyue.afuscale cat databases/RKStorage > afu_rn.db
# 資料表結構：CREATE TABLE kv_data(key TEXT, value TEXT)
sqlite3 afu_rn.db "SELECT key, value FROM kv_data" > rn_export.json
```

## 用程式匯入

已匯出為 JSON（形如 `{"afu_user_profiles":"[...]", "afu_records":"[...]", ...}`）後：

```dart
import 'data/migration.dart';
final count = await migrateFromJson(rnData);
```

## 鍵映射表

| 舊 RN 鍵 | 新 Flutter 鍵 | 說明 |
| --- | --- | --- |
| `afu_user_profiles` | `afu_profiles` | 成員檔案 |
| `afu_records` | `afu_records` | 測量記錄（含體成分 / profile）|
| `afu_goal_weights` | `afu_goals` | 目標體重 |
| `afu_display_unit` | `afu_display_unit` | 顯示單位 |
| `afu_pending_history` | `afu_pending` | 待分配歷史 |
| `afu_bound_devices` | `afu_devices` | 綁定裝置 |

遷移只寫入**目標鍵為空**的條目，不覆蓋已有資料，可安全重複執行。

## 電腦端 received.jsonl

接收端 `server/received.jsonl` 是獨立備份，每行結構與 `MeasurementRecord` 相容，可手動轉成 `afu_records` 陣列後按上法匯入。

## 驗證

遷移後開啟資料頁，成員數與記錄數應與舊版一致。若某些記錄顯示「本次未測得體阻抗」，說明原記錄本來就沒有阻抗（舊版同樣算不出體成分），不是遷移遺失。
