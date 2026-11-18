# AFU

<p align="center">
  <b>简体中文</b> &middot; <a href="docs/i18n/zh-Hant/README.md">繁體中文</a> &middot; <a href="docs/i18n/ja/README.md">日本語</a> &middot; <a href="docs/i18n/de/README.md">Deutsch</a> &middot; <a href="docs/i18n/fi/README.md">Suomi</a> &middot; <a href="docs/i18n/en/README.md">English</a>
</p>


**AFU-WL-TZ-A1**（蚂蚁阿福 × 沃莱 ICOMON）体脂秤的 Android 客户端 · Flutter 重写版  
本地优先 · 无账号 · 无云同步 · 5 语言 · 深浅双主题

<p align="center">
  <img src="docs/screenshots/home.jpg" width="200" alt="数据页">
  &nbsp;&nbsp;
  <img src="docs/screenshots/sett.jpeg" width="200" alt="功能一览">
  &nbsp;&nbsp;
  <img src="docs/screenshots/proto.jpeg" width="200" alt="通讯日志">
</p>

<p align="center"><sub>数据页 · 功能一览 · 通讯日志（调试模式下可见）</sub></p>

## 特性

- **扫描 1 秒内**：同一台手机同一杆秤，旧 React Native 版需要 7 分钟
- **环形仪表盘**：称重 → 阻抗 → 完成，三段式动画
- **多成员**：档案管理、改名同步历史、孤儿记录修复
- **数据**：72H / 7d / 30day / 自定义区间筛选，趋势图，批量推送 · 转移 · 删除
- **局域网同步**：HTTP 推送到自建接收端
- **算法完全公开**：BIA 公式与每个系数逐条说明，区分论文原式与实测校准值
- 5 语言 · 深浅双主题 · kg / lb / 斤

## 文档

| 文档 | 内容 |
| --- | --- |
| [协议 · 通俗版](docs/PROTOCOL.md) | 从"怎么找到秤"讲到"字节怎么变成体重"，含 10 个实测坑 |
| [协议 · 规格版](docs/PROTOCOL_SPEC.md) | 面向实现者的技术规格：字段级定义、状态机、测试向量、一致性清单 |
| [体成分算法](docs/ALGORITHM.md) | 体脂率/水分/肌肉/骨骼肌怎么算出来的，含公式与系数来源标注 |
| [构建与安装](docs/BUILD.md) | 环境要求、两个必踩的坑、无线安装 |
| [数据迁移](docs/MIGRATION.md) | 从旧 RN 版导入历史记录 |
| [常见问题](docs/FAQ.md) | BMI 为何不随性别变、阻抗为 0、电量、历史机制 |
| [技术待办](docs/BACKLOG.md) | 内部清单：已验证待实施的修正、待验证假设、已知局限 |

> 以上六份文档均提供 **6 种语言**版本：简体中文 · [繁體中文](docs/i18n/zh-Hant/README.md) · [日本語](docs/i18n/ja/README.md) · [Deutsch](docs/i18n/de/README.md) · [Suomi](docs/i18n/fi/README.md) · [English](docs/i18n/en/README.md)

## 快速开始

```bash
git clone https://github.com/Linmord/afu-scale-flutter.git
cd afu-scale-flutter
flutter pub get
flutter build apk --release
```

> ⚠️ 项目路径**不能含中文**，否则 Gradle 直接报错。详见 [构建文档](docs/BUILD.md)。

每次推送到 `main` 会自动构建 APK（[`.github/workflows/build.yml`](.github/workflows/build.yml)），产物在 Actions 的 Artifacts 里。

## 旧版

React Native 版已**停止维护** → [Linmord/afu-scale-app](https://github.com/Linmord/afu-scale-app)

## 免责声明

非官方客户端，与蚂蚁阿福 / 沃莱（ICOMON）无关联。协议通过公开抓包与逆向推导得出，可能随固件升级失效。
体成分为 BIA 公式估算值，仅供个人趋势参考，不作为医学诊断依据。
