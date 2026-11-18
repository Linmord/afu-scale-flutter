# 术语对照表 / Terminology Glossary

> 翻译文档时**必须**遵循本表。技术名词、命令名、字节值一律保持原文（英文/十六进制）。

## 核心协议术语

| 中文 | English | 日本語 | 繁體中文 | Deutsch | Suomi |
| --- | --- | --- | --- | --- | --- |
| 帧 | frame | フレーム | 幀 | Frame | kehys |
| 载荷 / 正文 | payload | ペイロード | 載荷 | Payload / Nutzlast | hyötykuorma |
| 校验和 | checksum | チェックサム | 校驗和 | Prüfsumme | tarkistussumma |
| 广播 | advertising | アドバタイジング | 廣播 | Advertising / Werbung | mainonta |
| 扫描 | scan | スキャン | 掃描 | Scan | skannaus |
| 服务（GATT）| service | サービス | 服務 | Dienst | palvelu |
| 特征值 | characteristic | キャラクタリスティック | 特徵值 | Charakteristik | ominaisuus |
| 通知（GATT）| notification / notify | 通知 | 通知 | Benachrichtigung | ilmoitus |
| 写入（带响应）| write with response | 応答付き書き込み | 帶回應寫入 | Schreiben mit Antwort | kirjoitus vastauksella |
| 连接 | connection | 接続 | 連線 | Verbindung | yhteys |
| 握手 | handshake | ハンドシェイク | 握手 | Handshake | kättely |
| 设备类型 | device type | デバイスタイプ | 裝置類型 | Gerätetyp | laitetyyppi |
| 大端 / 小端 | big-endian / little-endian | ビッグエンディアン | 大端 / 小端 | Big-Endian | big-endian |
| 状态机 | state machine | 状態機械 | 狀態機 | Zustandsautomat | tilakone |
| 时序 | timing / sequence | タイミング | 時序 | Zeitverlauf | ajoitus |
| 用户槽位 | user slot | ユーザースロット | 使用者槽位 | Benutzerslot | käyttäjäpaikka |
| 历史记录 | history record | 履歴記録 | 歷史記錄 | Verlaufsdatensatz | historia |
| 锁定包 | locked packet | 確定パケット | 鎖定封包 | Sperrpaket | lukittu paketti |
| 实时包 | realtime packet | リアルタイムパケット | 即時封包 | Echtzeitpaket | reaaliaikapaketti |
| 稳定包 | stable packet | 安定パケット | 穩定封包 | Stabilitätspaket | vakaa paketti |

## 体成分术语

| 中文 | English | 日本語 | 繁體中文 | Deutsch | Suomi |
| --- | --- | --- | --- | --- | --- |
| 阻抗 | impedance | インピーダンス | 阻抗 | Impedanz | impedanssi |
| 体脂率 | body fat percentage | 体脂肪率 | 體脂率 | Körperfettanteil | kehon rasvaprosentti |
| 去脂体重 | fat-free mass (FFM) | 除脂肪体重 | 去脂體重 | Fettfreie Masse | rasvaton massa |
| 肌肉量 | muscle mass | 筋肉量 | 肌肉量 | Muskelmasse | lihasmassa |
| 骨骼肌 | skeletal muscle | 骨格筋 | 骨骼肌 | Skelettmuskulatur | luurankolihas |
| 皮下脂肪 | subcutaneous fat | 皮下脂肪 | 皮下脂肪 | Unterhautfett | ihonalaisrasva |
| 体水分率 | body water percentage | 体水分率 | 體水分率 | Körperwasseranteil | kehon vesiprosentti |
| 蛋白质 | protein | タンパク質 | 蛋白質 | Protein | proteiini |
| 骨量 | bone mass | 骨量 | 骨量 | Knochenmasse | luumassa |
| 生物电阻抗分析 | bioelectrical impedance analysis (BIA) | 生体電気インピーダンス法 | 生物電阻抗分析 | Bioelektrische Impedanzanalyse | bioimpedanssianalyysi |
| 体脂秤 | body-fat scale | 体組成計 | 體脂計 | Körperanalysewaage | kehonkoostumusvaaka |

## 翻译规则

1. **不翻译**：代码块内容、十六进制字面量（`0xAC`）、命令名（`08`/`D0`/`04 D6`）、
   字段路径（`d[3..5]`）、文件名、URL、UUID、MAC 地址、公式。
2. **保留** markdown 结构：标题层级、表格列数、代码围栏数量、列表缩进。
3. **Mermaid 图内的节点 ID 和语法关键字不翻译**，只翻译标签文字（如 `--> Scanning: 扫描`）。
4. 语体：技术规格（PROTOCOL_SPEC）用陈述式；教学版（PROTOCOL）保留讲解语气与类比。
5. 芬兰语为小语种，优先保证**技术准确性**而非文学流畅；不确定的复合词保留英文原文并加括号说明。
6. 所有语言**不译**「AFU」「AFU-WL-TZ-A1」「ICOMON」「Welland」「FG2313UWB-D」等专有名词。
