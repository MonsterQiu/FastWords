<div align="center">

<img src=".github/assets/icon.png" width="128" alt="FastWords" />

# FastWords

**菜单栏里的极简背单词应用 · 间隔重复 · 离线中英词典**
*A minimalist menu-bar vocabulary app for macOS — spaced repetition, offline dictionary, exam word books.*

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://github.com/MonsterQiu/fast-world)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Release](https://img.shields.io/github/v/release/MonsterQiu/fast-world?label=download)](https://github.com/MonsterQiu/fast-world/releases/latest)
[![Algorithm](https://img.shields.io/badge/scheduler-FSRS--6-5B9DFF)](#工作原理--how-it-works)

[中文](#中文) · [English](#english)

</div>

---

<a name="中文"></a>

## 中文

FastWords 是一款常驻 **macOS 菜单栏**的背单词工具：单词安静地待在菜单栏，工作间隙瞥一眼就能复习。它把 **科学的间隔重复（FSRS-6）** 和 **离线中英词典 + 考试词书** 装进一个轻量、纯本地、无账号、无广告的应用里。

> ⚠️ FastWords 是 **菜单栏应用**，没有 Dock 图标。启动后请看屏幕**右上角菜单栏**的 `W` 图标。

### ✨ 功能

- **🧠 FSRS-6 间隔重复** — 采用业界最新的 FSRS-6 调度算法（Anki 同款思路，纯 Swift 实现），建模你的遗忘曲线，按目标记忆率精准安排复习；自动判定「已掌握」，告别 SM-2 的 ease hell。
- **📖 离线中英词典** — 内置约 **15,000** 个考试高频词（基于开源 ECDICT），带 **中文释义 + 英英释义 + 音标**，完全离线、秒出。
- **🎓 8 本考试词书** — 中考 / 高考 / 四级 / 六级 / 考研 / 托福 / 雅思 / GRE，一键加载切换，各自独立保存进度。
- **🔊 发音** — macOS 内置 TTS（美音 / 英音、可调语速、离线），有真人音频时优先播放并缓存；US / UK 双音标。
- **📚 多词书管理** — 可同时维护多本词书、随时切换；导入时**合并去重并保留已有进度**。
- **📊 学习热力图** — GitHub 风格的每日学习热力图 + 今日 / 连续天数 / 累计 / 已掌握统计。
- **⌨️ 顺手** — 键盘快捷键（Space 已认识、←/→ 翻页、↵ 朗读）、卡片显示内容自由开关、深靛蓝 + Maple 字体的精致界面。
- **🔒 纯本地** — 所有进度与设置存在 `~/Library/Application Support/FastWords/`，无账号、无云、无广告。

### 📥 下载安装

1. 到 [**Releases**](https://github.com/MonsterQiu/fast-world/releases/latest) 下载 `FastWords-vX.Y.Z.zip`。
2. 解压，把 **FastWords.app** 拖进「应用程序」文件夹。
3. **首次打开**（应用未做苹果签名，需绕过 Gatekeeper）：
   - **右键点击** FastWords.app → 选「**打开**」→ 在弹窗里再点「打开」。
   - 如果提示「已损坏 / 无法验证开发者」，在终端运行一次：
     ```sh
     xattr -dr com.apple.quarantine /Applications/FastWords.app
     ```
     然后正常双击打开即可。
4. 看屏幕**右上角菜单栏**的 `W` 图标——点开就能用。

### 🛠 从源码构建

需要安装 Xcode 命令行工具（`xcode-select --install`）。

```sh
git clone https://github.com/MonsterQiu/fast-world.git
cd fast-world

swift build            # 编译
swift test             # 跑测试（65 个单测）

./Scripts/package_app.sh   # 打包成 dist/FastWords.app
open dist/FastWords.app

./Scripts/release.sh       # 生成可分发的 dist/FastWords-vX.Y.Z.zip
```

### 🔬 工作原理 / How It Works

- **FSRS-6 调度**：每个词跟踪 **稳定性 (S) / 难度 (D) / 可提取性 (R)** 三个量，按幂函数遗忘曲线预测「你此刻还记得的概率」，并解出「掉到目标记忆率（默认 90%）的那一天」作为下次复习日。点「认识」间隔增长、「不认识」重置、「模糊」小幅推进。连续记牢（稳定性 ≥ 21 天）即自动「已掌握」。
- **离线词典**：内置 ECDICT 的考试词子集（TSV，约 15k 词，含中文/英英/音标/tag），按考试 `tag` 过滤即可切出任意一本考试书。查不到的词可联网用 Free Dictionary API 补例句和真人发音。
- **数据**：纯 JSON 文件持久化（`state.json`），含多词书、每词 FSRS 状态、每日学习计数。

### 🙏 致谢 / Acknowledgements

| 组件 | 用途 | 许可 |
|---|---|---|
| [ECDICT](https://github.com/skywind3000/ECDICT) | 内置中英词典数据（约 15k 词子集） | MIT |
| [Maple Mono](https://github.com/subframe7536/maple-font) | 单词主标题与音标字体 | SIL OFL 1.1 |
| [Free Dictionary API](https://dictionaryapi.dev) | 可选的在线例句 / 真人发音 | 免费 API（运行时调用） |
| Apple AVFoundation | 离线语音合成（TTS） | 系统框架 |

FastWords 本体代码采用 [MIT 许可](LICENSE)。

---

<a name="english"></a>

## English

FastWords is a **macOS menu-bar** vocabulary app: words sit quietly in your menu bar so you can review at a glance between tasks. It packs **modern spaced repetition (FSRS-6)** and an **offline English–Chinese dictionary with exam word books** into a lightweight, fully local app — no account, no cloud, no ads.

> ⚠️ FastWords is a **menu-bar app** with no Dock icon. After launching, look for the `W` icon in the **top-right menu bar**.

### ✨ Features

- **🧠 FSRS-6 spaced repetition** — the modern open-source scheduler (the algorithm Anki uses), implemented in pure Swift. Models your forgetting curve, schedules to a target retention, auto-detects "mastered," and avoids SM-2's ease-hell.
- **📖 Offline EN–CN dictionary** — ~**15,000** high-frequency exam words (from the open-source ECDICT) with **Chinese meaning + English definition + phonetics**, fully offline.
- **🎓 8 exam word books** — Zhongkao / Gaokao / CET-4 / CET-6 / Postgrad / TOEFL / IELTS / GRE; load and switch with one tap, each keeps its own progress.
- **🔊 Pronunciation** — built-in macOS TTS (US/UK accents, adjustable rate, offline), preferring & caching human audio when available; US/UK phonetics.
- **📚 Multiple word books** — keep several books, switch anytime; importing **merges & de-dupes while preserving existing progress**.
- **📊 Learning heatmap** — a GitHub-style daily-learning heatmap plus today / streak / total / mastered stats.
- **⌨️ Frictionless** — keyboard shortcuts (Space = known, ←/→ = navigate, ↵ = speak), per-card content toggles, a refined indigo + Maple-Mono UI.
- **🔒 Fully local** — all progress & settings live in `~/Library/Application Support/FastWords/`. No account, no cloud, no ads.

### 📥 Download & Install

1. Download `FastWords-vX.Y.Z.zip` from [**Releases**](https://github.com/MonsterQiu/fast-world/releases/latest).
2. Unzip and drag **FastWords.app** into your Applications folder.
3. **First launch** (the app is not Apple-notarized, so Gatekeeper needs a nudge):
   - **Right-click** FastWords.app → **Open** → click **Open** again in the dialog.
   - If macOS says it's "damaged" or "from an unidentified developer," run once in Terminal:
     ```sh
     xattr -dr com.apple.quarantine /Applications/FastWords.app
     ```
     then open it normally.
4. Look for the `W` icon in the **top-right menu bar** — click it to start.

### 🛠 Build from Source

Requires Xcode command-line tools (`xcode-select --install`).

```sh
git clone https://github.com/MonsterQiu/fast-world.git
cd fast-world

swift build            # compile
swift test             # run tests (65 unit tests)

./Scripts/package_app.sh   # package into dist/FastWords.app
open dist/FastWords.app

./Scripts/release.sh       # produce a distributable dist/FastWords-vX.Y.Z.zip
```

### 📜 License

FastWords is released under the [MIT License](LICENSE). Bundled third-party
data and fonts retain their own licenses (ECDICT — MIT; Maple Mono — SIL OFL 1.1).
See the Acknowledgements table above.
