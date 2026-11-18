# 从旧 RN 版迁移数据

Flutter 版与旧 React Native 版**可并存安装**（包名不同）。首次安装后按下面步骤把旧记录迁过来。

## 旧版数据在哪

旧 RN 版存在 AsyncStorage（本质是 SQLite 的 `RKStorage` 表）：

```bash
# 查看数据目录（需要可调试包或 root）
adb shell "run-as com.aiyue.afuscale ls databases/"
# 导出
adb exec-out run-as com.aiyue.afuscale cat databases/RKStorage > afu_rn.db
# 表结构：CREATE TABLE kv_data(key TEXT, value TEXT)
sqlite3 afu_rn.db "SELECT key, value FROM kv_data" > rn_export.json
```

## 用程序导入

已导出为 JSON（形如 `{"afu_user_profiles":"[...]", "afu_records":"[...]", ...}`）后：

```dart
import 'data/migration.dart';
final count = await migrateFromJson(rnData);
```

## 键映射表

| 旧 RN 键 | 新 Flutter 键 | 说明 |
| --- | --- | --- |
| `afu_user_profiles` | `afu_profiles` | 成员档案 |
| `afu_records` | `afu_records` | 测量记录（含体成分 / profile）|
| `afu_goal_weights` | `afu_goals` | 目标体重 |
| `afu_display_unit` | `afu_display_unit` | 显示单位 |
| `afu_pending_history` | `afu_pending` | 待分配历史 |
| `afu_bound_devices` | `afu_devices` | 绑定设备 |

迁移只写入**目标键为空**的条目，不覆盖已有数据，可安全重复执行。

## 电脑端 received.jsonl

接收端 `server/received.jsonl` 是独立备份，每行结构与 `MeasurementRecord` 兼容，可手工转成 `afu_records` 数组后按上法导入。

## 验证

迁移后打开数据页，成员数与记录数应与旧版一致。若某些记录显示「本次未测得体阻抗」，说明原记录本来就没有阻抗（旧版同样算不出体成分），不是迁移丢失。
