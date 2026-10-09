<p align="center"><a href="README.md">English</a> · 简体中文</p>

<p align="center">
  <img src="Design/AppIcon.png" alt="Eventrail 应用图标：蓝色背景上一张象牙白的门票，缺口沿 E 字形穿过三个活动站点" width="128">
</p>

<h1 align="center">Eventrail</h1>

<p align="center"><a href="https://www.eventernote.com/">Eventernote</a> 的原生 iOS 伴侣应用——浏览活动、关注艺人，记下你去的每一场活动，从抽选到票根。</p>

<p align="center"><a href="docs/overview.md">功能概览（英文）</a></p>

<!-- TODO: add a 📸 Screenshots section here once screenshots exist -->

## 📱 获取方式

Eventrail 正通过 TestFlight 进行 **Beta 测试**，支持 iPhone、iPad 和 Apple Watch，尚未上架 App Store。

<!-- TODO: add the public TestFlight invite link here -->

> Eventrail 是一个独立项目，与 Eventernote 没有关联，也未获其认可。

## ✨ 功能

- **🔍 原生浏览** — 搜索 Eventernote 公开的活动和艺人，可按日期和地区筛选、按时间正序或倒序排列，也可以从网站自己的“今天”和“最新添加”列表开始；每个活动、艺人和场馆都有自己的页面
- **🎫 你自己的记录** — 把活动加入行程，记下参加过的每一轮抽选、座位、以任意货币记录的票价和备注；有没有票，由中签的那一轮决定
- **🎰 抽选** — 所有还在等结果的抽选集中在一个列表里，按公布日排列，结果可以直接在列表中记录，公布日当晚 8 点还会提醒
- **⭐ 收藏与关注** — 收藏活动、关注艺人，查看他们之后的所有出演日程；新增和有变动的日程会一直标记，直到你看过为止
- **🗺️ 活动护照** — 一张标出你去过的场馆的地图，以及活动背后的数字：在活动上度过的时间、按席种统计的门票花费，还有抽选战绩
- **🎟️ 票根** — 把门票做成一张纪念图片保存或分享，座位可以遮住
- **⏱️ 实时活动** — 有票的活动当天，在锁定屏幕、灵动岛和 Apple Watch 的智能叠放中，从入场一路跟到结束
- **⌚ Apple Watch App** — 把即将到来的活动戴在手腕上：倒计时、座位和时间
- **📅 日历同步** — 把行程写入应用自己的日历，并在入场时间提醒
- **📥 导入个人主页** — 导入 Eventernote 公开个人主页的参加记录和收藏（只读，无需密码），再勾选你有票的活动
- **☁️ iCloud 同步** — 通过你的 iCloud 私有存储在 iPhone 和 iPad 之间同步记录，应用没有自己的服务器
- **💾 备份与恢复** — 把行程导出为 `.eventrail` 文件，随时恢复
- **🌍 多语言** — 英语、日语、简体中文和繁体中文；活动概要可在设备上翻译，时间可按场馆当地或你所在的时区显示

各项功能如何运作、你的数据如何处理，请参阅[功能概览](docs/overview.md)（英文）。

## 🔧 开发

### 📋 环境要求

- iOS / iPadOS 26.0 及以上；手表 App 需要 watchOS 26.0 及以上
- Xcode 26.0 及以上（项目基于 Xcode 27 开发）
- 不使用包管理器，没有任何第三方依赖

### 🚀 快速开始

1. **克隆仓库**

   ```bash
   git clone https://github.com/shawnhuangyh/Eventrail.git
   cd Eventrail
   ```

2. **在 Xcode 中打开**

   ```bash
   open Eventrail.xcodeproj
   ```

3. **构建并运行** — 选择模拟器或设备，按 `⌘R`。`Eventrail` scheme 会一并构建小组件扩展和手表 App，并把两者嵌入。

   模拟器构建无需额外配置。真机构建需要在开发者账户中为 App ID 开启 iCloud（含 `iCloud.moe.shawn.Eventrail` CloudKit 容器）和推送通知，因为同步基于 CloudKit；还需要为 App 和小组件扩展都加上 App Group `group.moe.shawn.Eventrail`，实时活动的海报经由它传递。首次从 Xcode 进行真机构建时，自动签名会注册这个 App Group 以及扩展和手表 App 的 App ID；无法自动注册的签名方式（例如 Xcode Cloud）需要它们事先存在。TestFlight 构建要能同步，需先在 CloudKit 控制台把 CloudKit schema 部署到生产环境；之后每当模型新增类型或字段，都要再部署一次——先用开启了 iCloud 同步的开发构建运行一遍，让开发环境的 schema 里有这些内容可供部署。

   实时活动需要用真机 iPhone 检查：模拟器的截图不包含灵动岛，手表模拟器也收不到实时活动。

### 常用命令

```bash
# 列出当前 Xcode 可以构建的目标设备
xcodebuild -scheme Eventrail -showdestinations

# 为模拟器构建
xcodebuild -scheme Eventrail -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# 运行单元测试
xcodebuild test -scheme Eventrail -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# 运行单个测试（Swift Testing 的测试名要带上 "()"，否则一个测试也不会运行）
xcodebuild test -scheme Eventrail -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  '-only-testing:EventrailTests/TrackingTests/twoDevicesEditingDifferentAnswersKeepBoth()'
```

Xcode 27 不再附带 `Simulator.app`，模拟器窗口改为 `DeviceHub.app`（`open -b com.apple.dt.Devices`）。`xcrun simctl` 的用法不变。

## 🤝 参与贡献

欢迎贡献——可以提 issue，或向 `main` 提交 pull request。

所有工作都提交到 `main`。`release` 是 TestFlight 测试者使用的版本：Xcode Cloud 从它构建，只有在一个版本准备好发布时，才通过从 `main` 发起的 pull request 推进。

### 提交信息规范

本项目遵循 Conventional Commits 格式：

- 以类型开头：`feat`、`fix`、`docs`、`test`、`refactor` 或 `chore`
- 主题简洁，使用祈使语气
- 提交信息和 pull request 都用英文撰写
- pull request 的分支按类型命名（`feat/…`、`fix/…`）

```text
feat: remind on a lottery's results day at 8 PM
fix: stop the calendar mirror crashing on a new untimed event
docs: describe sync as SwiftData settles it
```

## 📝 许可证

本项目采用 [MIT 许可证](LICENSE)。该许可证只涵盖本应用自身的源代码，不涉及 Eventernote 的内容，那些内容仍归该网站所有。

## 🙏 致谢

- [Eventernote](https://www.eventernote.com/)，提供应用读取的活动、艺人和场馆信息
- [日本国土地理院](https://www.gsi.go.jp/)，提供地址搜索
- [OpenStreetMap](https://www.openstreetmap.org/copyright) 贡献者，提供精确到建筑的场馆位置
- [Frankfurter](https://frankfurter.dev/)，提供各国央行的参考汇率

---

**用 Swift 和 SwiftUI 以 ❤️ 打造**
