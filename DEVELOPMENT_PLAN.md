# FastWords 增强开发计划

> 目标：做成比 LingoBar / VocaBar / Word Drop 更好用的菜单栏背单词应用。
> 核心差异化：**菜单栏瞥见式被动曝光 + 真正的间隔重复（SRS）+ 发音 + 无上限导入 + 全本地隐私**。
> 竞品调研结论：目前没有任何一个竞品同时做齐这几点。

## 设计原则（从竞品痛点反推）

- **绝不把核心功能上锁** —— 全本地、无账号、无广告。
- **交互宽容** —— 标记可撤销，轮换时正在交互就暂停翻页。
- **网络全部可选降级** —— 发音、词典联网失败都不影响离线使用。
- **保持分层** —— Core 为纯逻辑库（值类型 + 纯函数，可单测），UI 在可执行 target。
- **发音 / 词典全程零费用** —— 系统 TTS（AVSpeechSynthesizer，离线免费）+ Free Dictionary API（免费、含真人音频）。

## 进度总览

| 阶段 | 功能 | 状态 |
|---|---|---|
| P0-1 | SRS 间隔重复核心（SM-2）+ 单测 | ✅ 完成 |
| P0-2 | 发音（系统 TTS） | ✅ 完成 |
| P0-3 | 词典补全 + 真人音频（Free Dictionary API） | ✅ 完成 |
| P1-A | 内置离线中文词典（ECDICT）+ 考试词书（按 tag 选） | ✅ 完成 |
| P1-B | UI 重做（向 GlimpseWords 靠：菜单栏只显英文 / 弹窗固定 / 快捷键 / US-UK 双音标 / 视觉） | ✅ 完成 |
| P1-4 | 导入合并 / 去重 / 预览 | ⬜ 未开始 |
| P1-5 | 系统词典联动 | ⬜ 未开始 |
| P1-6 | 标准词书格式兼容 | ⬜ 未开始 |
| P2 | 轮换间隔 / 揭示模式 / 统计 / 多词书 / Keychain | ⬜ 未开始 |

状态图例：⬜ 未开始 · 🟡 进行中 · ✅ 完成（含验证）

---

## P0-1：SRS 间隔重复核心

**成功标准**
- `FastWordsCore/SRS.swift` 实现 SM-2，纯函数，输入「当前 SRS 状态 + 评分」返回「新 SRS 状态」。
- `WordEntry` 增加 SRS 字段：`easeFactor`、`interval`、`repetitions`、`dueDate`、`lastReviewedAt`，且 `Codable` 向后兼容（旧 state.json 能解码）。
- 三档评分枚举：`again / hard / good`（不认识 / 模糊 / 认识）。
- 单测覆盖：首次评分、连续答对 interval 增长、答错重置、ease 下限。
- `swift test` 全绿。

**实现记录**
- `Sources/FastWordsCore/SRS.swift`：`SRSState`（easeFactor/intervalDays/repetitions/dueDate/lastReviewedAt）+ `ReviewGrade`（again/hard/good，含中文标题）+ `SRS.apply(_:to:now:)` 纯函数 SM-2。`now` 注入便于测试。
- `WordEntry.swift`：增加 `srs` 与 `audioFileName` 字段，自定义 `init(from:)` 实现**向后兼容解码**（旧 state.json 缺字段则用默认值，已用现有 state.json 实测加载通过）。
- `AppSettings.swift`：`ReviewMode` 增加 `.smart`。
- `ReviewScheduler.swift`：新增 `nextIndex(currentIndex:words:mode:now:)` 重载——smart 模式挑最逾期的学习词；已掌握词永远排在所有学习词之后；单词不重复当前词。
- `WordStore.swift`：`grade(_:)` 应用 SRS 并前进；`showNext` 改用 smart 重载。
- UI：`AppActions.grade`、popover 仅在 smart 模式显示三档评分按钮（红/橙/绿 = 不认识/模糊/认识），不影响顺序/随机模式。
- 测试：新增 `SRSTests`（7 例）+ `SmartSchedulerTests`（4 例），`swift test` 共 18 例全绿。
- 验证：`swift build` 通过；启动 app 常驻菜单栏；`state.json` 已写入 srs/easeFactor 等键。

**成功标准**
- `FastWordsCore` 提供 `PronunciationService` 协议 + `SystemSpeechSynthesizer`（包 `AVSpeechSynthesizer`）。
- 可调语速、可选英/美音。
- popover 卡片有发音按钮；设置项「翻到新词自动朗读」。
- 离线可用，`swift build` 通过，手动验证出声。

**实现记录**
- `Sources/FastWordsCore/PronunciationService.swift`：`@MainActor` 协议 + `SpeechAccent`（en-US / en-GB）枚举。协议在 Core 便于抽象/测试，具体实现放 UI 层。
- `Sources/FastWords/SystemSpeechSynthesizer.swift`：`AVSpeechSynthesizer` 实现，离线免费；0...1 语速映射到合成器实际区间；重复点击会先停再读。
- `AppSettings.swift`：新增 `speechAccent` / `speechRate`（默认 0.45）/ `autoSpeak`，并加自定义 `init(from:)` 做**向后兼容解码**。
- `AppDelegate.swift`：持有 `PronunciationService`，新增 `advanced()`（翻词后刷新标题 + 按需自动朗读）与 `speakCurrentWord()`，导航/评分/定时器统一走 `advanced()`。
- UI：单词卡加扬声器按钮；设置加「Pronunciation」分区（口音 / 速度滑条 / 自动朗读开关）；设置窗口高度 420→540。
- 验证：`swift build` + `swift test`（18 例）通过；独立脚本确认系统有 68 个语音、en-US/en-GB 均可用、合成器实际发声（isSpeaking=true）；full app 启动正常。

**成功标准**
- `DictionaryService` 协议 + Free Dictionary API 实现（`https://api.dictionaryapi.dev`），可注入 mock。
- 导入只含单词的列表时自动补音标 / 释义 / 例句；失败则保留原样不阻塞。
- 真人音频 mp3 缓存到 `~/Library/Application Support/FastWords/audio/`，离线复用。
- 单词卡「查词典」按钮可手动补全 / 刷新。

**实现记录**
- `Sources/FastWordsCore/DictionaryService.swift`：`DictionaryService` 协议 + `DictionaryResult`（phonetic/meaning/example/audioURL）+ `FreeDictionaryService`（dictionaryapi.dev，免费无 key，可注入 session/baseURL）。解析为纯静态函数：优先选**带非空 audio 的音标条目**，404 / 非数组响应映射为 `notFound`。
- `Sources/FastWords/AudioCache.swift`：`@MainActor` 音频缓存，SHA256(url)→文件名，下载 mp3 到 `audio/` 目录并复用；`play(fileName:)` 缺文件返回 false 供调用方回退 TTS。
- `WordStore.swift`：`LookupState`（idle/loading/failed）+ `applyLookup`（**只填空字段，不覆盖用户已有数据**）+ `setAudioFileName`；暴露 `audioDirectory`。
- `AppDelegate.swift`：持有 `DictionaryService` + 懒加载 `AudioCache`；`lookUpCurrentWord()` 异步查词、回填、缓存音频（音频用 `try?` 失败不影响释义）；`speakCurrentWord()` **优先播放缓存真人音频，否则回退系统 TTS**。
- UI：单词卡操作区加「Dictionary」按钮；`noticeBlock` 显示查词中/失败/导入消息。
- 测试：`DictionaryServiceTests`（5 例，含音标优先、audio 选取、回退、空内容、404）；共 23 例全绿。
- 验证：`swift build` 通过；live 查 clarity/abandon 返回正确 word/meaning/audioURL；音频主机偶发慢响应已被 `try?` 容错（实测主机挂起不影响释义）；full app 启动正常。

> **P0 三项核心差异化（SRS / 发音 / 词典补全）全部完成并验证。**

---

## P1-A：内置离线中文词典（ECDICT）+ 考试词书

> 用户需求：词典补全要出**中文释义 + 音标**；并能在设置里选「考研/托福/雅思/四六级/GRE」等考试书。

**数据源**：[skywind3000/ECDICT](https://github.com/skywind3000/ECDICT)，**MIT 许可**（可合法打包，保留版权声明）。
- 字段：`word` / `phonetic`(UK) / `translation`(中文) / `pos` / `tag`(考试分类) / `frq`(词频) / `audio` 等。
- `tag` 空格分隔考试码（如 `zk gk cet4 cet6 ky toefl ielts gre`）——**一个词可属多本考试书，按 tag 过滤即可切书，无需多份数据**。

**构建策略**（已与用户确认）：不纯按词频砍，而是「**保留所有带考试 tag 的词**（考研/托福/雅思/四六级/GRE 完整保留）**+ 高频常用词补充**」，保证每本考试书完整、体积可控。

**成功标准**
- 离线中文释义：查词补全优先用内置 ECDICT（中文），查不到再回退在线 Free Dictionary。
- 设置里可选考试书（按 tag），选中后作为复习词书加载。
- 内置词库体积可控（目标压缩后数 MB），构建脚本可复现。

**实现记录**
- **数据核实**（已下载 ECDICT 77 万词源 CSV，统计后删除）：tag 取值确认为 `zk/gk/cet4/cet6/ky/toefl/ielts/gre`；所有带考试 tag 的词去重后仅 **14,942 个**（GRE 7504 / 托福 6974 / 六级 5407 / 雅思 5040 / 考研 4801 / 四级 3849 / 高考 3677 / 中考 1603）。
- **构建内置库**：清洗中文释义（去字面 `\n`/`\r` 转义、规整分隔符），导出 TSV `Sources/FastWordsCore/Resources/ecdict_exam.tsv`（**1.2MB**，gzip 0.5MB），每本考试书完整。基础 CSV 无真人音频，发音用系统 TTS + 在线补充。
- `Package.swift`：声明资源 `.copy("Resources/ecdict_exam.tsv")`。
- `OfflineDictionary.swift`：`@unchecked Sendable` 单例，懒加载解析 TSV，`NSLock` + 同步 `withLock`（避开 async 上下文锁限制）；实现 `DictionaryService.lookup`（中文）+ `words(for:)`（按 `ExamCategory` 出词书）+ `counts()`。`ExamCategory` 枚举含中文标题（考研/托福/雅思…）。
- `CompositeDictionaryService.swift`：按序回退——先离线 ECDICT（中文），无内容再在线 Free Dictionary（带真人音频）。
- `WordStore.loadExamBook(_:)`：从离线词典加载考试词书替换当前词集。`SettingsView` 加「Exam Word Books」分区（选考试 + 一键加载）。`AppDelegate` 词典改用 Composite（离线优先）。
- `Scripts/package_app.sh`：修复——把 SPM 生成的 `*.bundle` 资源一起拷进 `Contents/MacOS/`（否则打包后 `Bundle.module` 找不到词库）。打包后 app 仅 **2.2MB**。
- 测试：`OfflineDictionaryTests`（解析/跳过空词/未知 tag/normalize）、`CompositeDictionaryServiceTests`（回退逻辑）、`OfflineDictionaryDataTests`（**真实 bundle 数据**：abandon 出中文、8 本考试书非空、GRE/CET4 词数合理）。共 34 例全绿。
- 验证：`swift build` + 34 单测通过；真实 bundle 加载 ~65ms；打包 app 含词库、启动正常。

---

## P1-4：导入合并 / 去重 / 预览
**成功标准**
- 导入为「合并」而非「覆盖」：按 word 小写去重，新词追加，已存在的保留 SRS 进度。
- 支持拖拽文件到 popover 导入。
- 导入预览：「将新增 N 个 / 跳过 M 个重复」，确认后写入。

**实现记录**
- _（完成后填写）_

---

## P1-5：系统词典联动
- 单词卡一键查 macOS 系统词典（DictionaryServices / NSWorkspace）。
- （可选）全局快捷键划词加入词书。

**实现记录**
- _（完成后填写）_

---

## P1-6：标准词书格式兼容

**成功标准**
- 兼容 Anki 导出 txt（制表符分隔）和欧路 / 不背单词常见 CSV 列名。
- `.apkg` 解析列为 P2。

**实现记录**
- _（完成后填写）_

---

## P2：体验打磨

- 可配置轮换间隔：补 5s / 10s / 15min / 90min。
- 隐藏释义→点击揭示的「主动回忆」模式。
- 进度统计：已见 / 已掌握 / 到期待复习 计数。
- 多词书管理（可切换词书列表）。
- API Key 存 Keychain（目前明文存 json）。

**实现记录**
- _（完成后填写）_

---

## 验证与审查

- 每个阶段完成后用 `run` / `verify` 真实跑起来确认行为。
- P0 完成后跑一次 `code-review`。
- 遵循 karpathy 准则：小步、外科手术式改动、先定可验证成功标准。

### P0 审查结果（已处理）

1. **smart 调度 `priority()` 浮点精度丢失** —— 原用 `.greatestFiniteMagnitude/2 + secondsUntilDue` 把优先级压成单个 Double，导致已掌握词之间无法按到期日排序（与注释矛盾）。改为显式比较 `isHigherPriority(_:than:)`：先比是否掌握，再比 `dueDate`，排序精确。
2. **定时器自动朗读扰民** —— 原 `autoSpeak` 开启时后台定时器每个间隔都会出声朗读（用户离开也会"自言自语"）。改为：**定时器轮换只更新菜单栏不发声**，自动朗读仅在用户主动翻词时触发。
3. **自定义 `Decodable init` 是否破坏 `Encodable`** —— 实测确认不会：编码仍合成、round-trip 相等、旧 JSON 缺字段按默认值解码。无需改动。
- 复审后 `swift build` + 23 个单测全绿，full app 启动正常。
