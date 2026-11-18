# AFU-WL-TZ-A1 协议文档（Flutter 版实际实现）

> 本文档描述 **afu-flutter 当前代码真实发送/解析的内容**，不是理想化协议。
> 每个部分标注证据来源：[HCI]=官方蚂蚁 App HCI 抓包、[WT]=WeighTrace 文档、
> [VA]=vitaloop-app 源码、[AF]=AntAF 文档、[实测]=本机 nRF/HCI/通讯日志验证。
> 代码位置：lib/core/protocol.dart（帧与解析）、lib/ble/scale_ble.dart（序列）。

## 1. 设备识别（扫描）

| 项 | 值 |
|---|---|
| 广播名 | AFU-WL-TZ-A1（完整名在广播里）[实测/nRF] |
| 服务 UUID | 0xFFB0、0x1530（16-bit 完整列表）[实测/nRF] |
| 厂商数据 | ID 0x27AC，数据 = MAC 小端 6B + 01 [WT/实测] |
| Service Data | UUID 0x27AC，payload 前 6 字节反转 = 真实 MAC [WT/实测] |
| 广播间隔 | 999ms（未踩亮时也广播）[实测/nRF] |
| deviceType | 秤侧自报 0x29（所有秤→手机包 ac 29）[实测] |

**App 策略**：全量扫描（**不做** GATT UUID 前置过滤——实测 MIUI 上前置过滤会把秤漏掉
[WT 建议 + 本次实测]），回调里按「名字含 AFU-WL ∨ ServiceData 27AC ∨ 服务含 FFB0」识别。
真实 MAC 从 ServiceData 解出，用于连接（广播地址可能变化时以真实 MAC 为准）。

已知坑：Android 12+ 若 BLUETOOTH_SCAN 带 neverForLocation，beacon 类广播被系统
denylist 过滤（logcat: "Skipping data matching denylist"）。我们的 Manifest 不带该 flag。
[实测 + Chromium issue 40839483]

## 2. 连接与 GATT

| 项 | 值 |
|---|---|
| 连接地址 | ServiceData 解出的真实 MAC |
| 服务 | 0000ffb0-0000-1000-8000-00805f9b34fb |
| 写特征 | 0xFFB1 —— **只支持 WRITE（带响应）**，不支持 WRITE_NO_RESPONSE [实测 8/8 报错] |
| 通知特征 | 0xFFB2 —— setNotifyValue(true) 后用 onValueReceived |
| DIS 0x180A | 2A29=ICOMON / 2A24=FG2313UWB-D / 2A26=fw1.2.3 / 2A28=sw1.3.0 [实测] |
| 电池服务 0x2A19 | 不存在，读出的是垃圾值（77%），弃用 [实测] |

## 3. 帧格式（20 字节，手机→秤）

    [0]=0xAC  [1]=deviceType(手机侧发 0x27)  [2..17]=payload(16B)
    [18]=tail(命令标识)  [19]=checksum = sum(frame[2..18]) & 0xFF

- 手机发 ac 27，秤回 ac 29（双方各自报自己的 deviceType）[HCI/实测]。
- payload 超过 16 字节的部分被丢弃（frame() 里 i+2<18 截断）。

## 4. 命令序列（连接后实际发送，共 8 条，间隔 400ms）

    1. 08 对时      tail=DF   payload: 08 | unix秒(4B) | utcQuarters
    2. 01 用户      tail=D1   payload: 01 00 01 | height | weight(2B, ×100) | age | sex
                               sex: 男=1 女=2；weight 来自档案/最近记录
    3. 02 槽位      tail=D1   payload: 02 00 | slot1(7B): 01 h wH wL age sex 00
                                        | slot2(7B): 02 h wH wL age 01 00
                               [HCI] 官方在「解绑」时用它写双槽位；我们每次连接都发
                               （实验性质——用于覆盖秤内旧用户配置，见 §8）
    4. D0 完整握手  tail=D0   payload: unix秒(4B) | tz | 00(kg) | 01(slot) | height
                                        | weight(2B) | age | sex | target(2B) | 03 | 00
    5. 06 查询      tail=DF   payload: 06
    6. 04d6 ADC     tail=DF   payload: 04 D6   （实测：不是阻抗开关，只增加实时包频率）
    7. 04d8 历史#1  tail=DF   payload: 04 D8
    8. 04d8 历史#2  tail=DF   payload: 04 D8

- utcQuarters = UTC 偏移（分钟为负）÷ 15 & 0xFF。
- weight/target 的参考值来源：档案体重 → 最近记录 → 60kg；目标 = 用户设定 → 参考体重×0.75。
- 写特征全部走 withResponse（FFB1 不支持 no-response）[实测]。

## 5. 通知解析（秤→手机，20 字节 ac 29 ...）

### type=00 实时包（测量中，约 100-150ms 一条）
    体重 = ((d[3]-0x68)*65536 + d[4]*256 + d[5]) / 1000    [RN 实测版公式]
    data[8:10] = 单组 ADC 原始值（实时阶段，非最终阻抗）
    data[11]   = 电量(低7位) **或** 状态标志 0x64(=100，测量完成)
    电量采信条件：type=00 且 raw>0 且 raw<100；真电量约 10% [实测众数 915 条]

### type=80 稳定包（称重稳定）
    结构同 type=00；data[11]>=100 视为「进入阻抗测量」阶段。

### type=02 锁定包（测量完成，循环广播约 6 秒）
    阻抗1 = (d[4]<<8)|d[5]     阻抗2 = (d[6]<<8)|d[7]
    体重 = ((d[10]<<16 | d[11]<<8 | d[12]) - 0x680000) / 1000
    实例：ac 29 02 00 01 ae 01 83 01 80 69 3b 6e ...
          → 430/387Ω，(0x693b6e-0x680000)=80750 → 80.75kg [实测 14:03]

### type=01 历史包（连接后秤推送未同步记录）
    时间 = d[3:7] (unix 大端)
    体重 = ((d[8]<<16 | d[9]<<8 | d[10]) - 0x680000) / 1000
    阻抗1 = (d[11]<<8)|d[12]   阻抗2 = (d[13]<<8)|d[14]
    BLE 会重复广播同一条（同记录最多见 3 次），App 按 key=时间_体重 去重入库。

### type=06 配置块
    06 查询后连推 5 包（index 00..04），内容每次相同，App 不解析。

## 6. 测量阶段判定

    type=02                 → done（锁定，含最终阻抗）
    type=00/80 且 d[11]>=100 → impedance（秤进入阻抗测量）
    其余                     → weighing

阻抗只由物理条件决定：双脚赤脚踩四电极才有非零阻抗；单脚/穿袜必为 0 [A/B 实测]。

## 7. 历史同步机制 [HCI/实测]

- 触发：08+01+完整握手写完后，秤自动推送所有**未同步**记录（04d8 非必需）。
- 推完秤内部标记已同步，不再重推，直到产生新测量。
- **没有任何删除/清空命令**（官方 29 条命令全查过）。漏存即永久丢。
- 秤内无记录时不推（连接后安静）。

## 8. 已知问题与实验点

1. **每次连接发 02 槽位（实验）**：官方只在解绑时发 02。我们每次连接发它来覆盖秤内
   用户配置（解决过 111cm 旧配置残留）。副作用未完全评估——若发现历史被反复重推，
   优先怀疑它，可改为「仅解绑时发」。
2. **体脂算法差异**：秤屏 26.2% vs App(Deurenberg 男) 25.8%，差 0.4 个百分点。
   BMI 永远一致（同实测体重同身高）。秤用厂商私有算法，App 用公开公式。
3. **连接状态抖动**：connectionState 在刚连接时会短暂误报 disconnected。
   已修：重连前复查 isConnected + _connecting 并发守卫（防止同一会话双握手）。
4. **deviceType 0x27 vs 0x29**：发 0x27（对齐官方抓包）。曾试 0x29 未观察到差异，
   保留 0x27。
5. **旧固件残留用户**：秤会保留上次 App 写入的用户槽位。若秤屏体脂明显不对，
   先确认 App 档案体重/身高是否与秤一致（对比 01 用户命令字节）。

## 9. 调试手段

- 通讯日志：连接后每 3 秒自动落盘
  /storage/emulated/0/Android/data/com.aiyue.afu_scale/files/comm_latest.txt
  格式：时间 →/← 原始20字节 [命令名/类型]，adb pull 即可分析。
- App 内查看：设备页右上「通讯 N」入口，可复制/导出/清空。
- logcat 关键字：Skipping data matching denylist（系统过滤）、flutter（SCAN_STEP 打点）。

## 10. 参考来源

- Fatpandac/AFUScale（iOS 官方逆向）
- Mzdyl/ant-afu-welland-scale（Python）
- monkey-wenjun/vitaloop-app（Android 原生，单握手模式）
- Xuan-lprk/WeighTrace（广播 ServiceData 结构、不做前置过滤）
- ZeroOneCN/AntAF（体重 32 位编码说明、15s 资料包心跳——我们未采用心跳）
- 本机 HCI 抓包 ant_cleanup.log / unbind_official.log（02 命令来源）

## 11. 与四份参考逆向文档的实测对比（2026-11-18）

### 11.1 实测推翻/修正了文档的点

| # | 文档说法 | 实测结论 | 证据 |
|---|---|---|---|
| 1 | [AF] 体重编码=完整32位 `& 0x3FFFF` 分档 | 实时/稳定包用 RN 公式 `((d[3]-0x68)*65536+d[4]*256+d[5])/1000`；type=02 锁定包体重在 **d[10:13]**，两处不同 | 80.75kg 全链路 |
| 2 | [AF] 休眠不广播，必须踩亮 | 本秤未亮屏也在广播（999ms 间隔），nRF 2 秒、验证台 84ms 扫到 | nRF + comm 日志 |
| 3 | [AF] 资料包 15 秒重发需心跳 | 心跳非必需：不发也稳定出阻抗，那是官方 App 循环展示 | 无心跳实测正常 |
| 4 | [VA] 握手 weight=0/target=0 | 发真实体重+目标更好：用户槽位与档案一致；BMI 不受影响（秤用实测） | 14:03 日志 |
| 5 | [VA] 单条 D0 握手即可 | 我们实测不带 01 用户命令时阻抗不触发（0x27 下）；8 条全序列最稳 | 前后对比 |
| 6 | [WT] 27AC payload 含 AC27 前缀 | payload = **MAC 6B 小端 + 01**，无前缀；首解曾偏 1 字节 | SD raw=24 76 07 ab 82 b0 01 |
| 7 | [WT] D6=阻抗来源 | D6 只是实时 ADC 流（频率 26→77）；**最终阻抗在 type=02 d[4:8]** | 04d6 A/B 对照 |
| 8 | [WT/HCI] checksum=sum(payload) | 精确为 **sum(frame[2..18]) & 0xFF**（含 tail） | 逐字节核对 |

### 11.2 实测新发现（四份文档都没有）

1. **FFB1 只支持 WRITE（带响应）**：WRITE_NO_RESPONSE 100% 报错。vitaloop 用 Kotlin 默认带响应没踩坑；ble-plx 默认无响应踩坑。
2. **Android 12+ denylist**：BLUETOOTH_SCAN 带 neverForLocation 时，此秤 iBeacon 广播被系统静默过滤（logcat: Skipping data matching denylist）。去掉 flag 恢复。
3. **MIUI 扫描天坑**：flutter_blue_plus 1 秒 vs react-native-ble-plx 7 分钟（同机同秤）。框架封装层差异，与权限无关。
4. **UUID 前置过滤会漏秤**：MIUI 上 startScan([ffb0]) 4 分钟无结果；全扫+回调筛选秒出。
5. **连接状态抖动**：GATT 建立瞬间 connectionState 短暂误报 disconnected，直接挂重连定时器会造成双握手（秤视为新同步会话）。必须复查 isConnected。
6. **档案回填阈值陷阱**：1kg 挡掉 0.1kg 真实变化；0.05kg 又被浮点误差(80.80-80.85=0.0499…)挡掉。最终 0.001kg。
7. **BIA 男女分离**：女=Segal+合成阻抗(i1+i2)*0.675；男=Deurenberg 1.10*bmi+0.23*age-11.22（阻抗不参与）。套错性别差近一倍。[WT] 的“两 ADC 让用户选”不如合成准（女）。
8. **02 命令真实语义** [HCI]：官方解绑时发，payload=两组用户槽位各 7B。我们借它覆盖秤内旧用户配置。
9. **电量** [实测 915 条]：data[11] 低 7 位，待机 10%；测量中变 0x64 当标志须排除；无 0x2A19 服务（读出 77% 是垃圾）。
10. **已同步标记对任何客户端生效**：无删除命令（官方 29 条写命令全查）。RN“拉完消失”与我们一致——新测量才有新历史。

### 11.3 与官方蚂蚁 App 的有意差异

| 官方 | 我们 | 理由 |
|---|---|---|
| 解绑时才发 02 | 每次连接都发（实验） | 覆盖秤内残留用户配置（曾卡 111cm） |
| 15 秒心跳重发资料包 | 不发 | 实测非必需 |
| 04d8 一次 | 发两次 | 保险，无副作用 |
| iOS | Android/Flutter | 扫描策略不同（见 11.2-3/4） |

### 11.4 待验证

- [ ] 02 每连接发送的长期副作用（若历史被反复重推→改回仅解绑时发）
- [ ] 0x29 deviceType 是否部分固件必需（vitaloop 默认 0x29 可工作）
- [ ] 体脂 0.4% 差异是否随体重恒定（决定是否加校准偏移）
- [ ] 15 秒心跳在长连接（>10 分钟）是否必要
