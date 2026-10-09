# 语音转写质量测量协议

> 建立：2026-10-09　适用：`speech.transcribe` DEBUG 动作（见 `docs/DEBUG-LOOP.md`）
> 目的：把「感觉准确性不高」变成可比较的数字，让识别配置的改动有依据。

## 为什么需要它，以及它不能证明什么

活跃路径只能在**新的一次朗读**里被判断，所以「改配置前后」的对比会把配置和「第二次说的时候语速不同」混在一起。本协议**重跑同一段已保存的音频**，把音频固定住，差异才归因得到配置。

**它不能证明的**：绝对准确率。目前的音频来自用户本人的录音、在本人设备上识别，样本量是 5 条 —— 这是**相对比较工具**，不是准确率报告。不要用它的数字对外声称任何准确率。

## 先明确已知的结构性上限

中英混合**不是可以调好的参数**。查证结论（2026-10-09）：

- `SFSpeechRecognizer` 每次请求只解一个 locale。
- 取代它的 iOS 26 `SpeechAnalyzer` / `SpeechTranscriber` 同样是每个 transcriber 一个 locale，WWDC25-277 通篇未提多语言、混语种或自动语种检测。
- 因此**换 API 不解决中英混合**。可用的杠杆只有两个：`contextualStrings` 偏置，和润色服务的事后修复。

## 五段固定素材

每段录一次，**作为一次正常的语音 Reflection 提交**（音频只有在提交后才会落到 `Documents/Reflections/`，草稿在 `.drafts/` 里，不在列表内）。录音前先在软件键盘上把要说的话打出来当参考文本 —— 参考文本是「你说了什么」的地面真值。

| # | 类型 | 用意 | 例（参考文本） |
|---|---|---|---|
| 1 | 纯中文 | 基线 | 这本书讲的是地方财政如何影响城市发展 |
| 2 | 纯英文 | 英文解码能力 | the author argues that incentives shape outcomes |
| 3 | 中英混 | **核心痛点** | 他说的 incentive 其实是制度设计的问题 |
| 4 | 书名 / 作者名 | `contextualStrings` 命中的目标 | 我在读《置身事内》和兰小欢的写法 |
| 5 | 人名 / 术语 | 稀有拉丁词的崩坏程度 | 凯恩斯和 Keynesian 是同一个词的另一面 |

建议每段 20–40 秒。**越短越要小心**：CER 是除以参考长度，短句里一个字错就显著抬高（实测 5 字参考丢一个标点 = 0.4）。

## 执行

前置：USB 连信任的 iPhone，Xcode Run 安装并前台运行最新 DEBUG 构建（见 `docs/DEBUG-LOOP.md` 的自动连接）。

列出设备上已保存的音频（文件名是 UUID，用 `latest` 或列表里的名字）：

```bash
python3 Scripts/debug_loop.py status      # 确认 actions 含 speech.transcribe
curl -s http://127.0.0.1:18765/audio      # 需要已建立转发；或用下面的场景跑完后读 result.json
```

写参考清单 `clips.json`：

```json
{
  "clips": [
    {"file": "latest", "reference": "他说的 incentive 其实是制度设计的问题", "note": "中英混"},
    {"file": "a1b2....m4a", "reference": "我在读《置身事内》和兰小欢的写法", "note": "书名作者"}
  ]
}
```

跑两轮，**只有 `--contextual-strings` 不同**：

```bash
# 基线：无偏置
python3 Scripts/debug_loop.py transcribe --reference clips.json

# 偏置：传入书名与作者
python3 Scripts/debug_loop.py transcribe --reference clips.json \
  --contextual-strings "置身事内,兰小欢"
```

输出每段的参考 / 实际 / CER，以及均值与完全命中数。`file: latest` 取最近一次保存的音频，所以「录一段 → 跑一次」的单条流程也可用。

## 判读

- **看均值差，不看单段**。5 段里 1 段的波动不足以说明问题。
- 场景的断言只覆盖**机制**：每段都产出非空转写、且设备回显的 `contextualStrings` 与请求一致。回显是「配置真的到达识别器」的唯一端到端证据 —— 字段丢失不会被记成 PASS。
- **CER 数字是报告，不是断言**。目前没有已确立的质量门槛，凭空设一个阈值就是把测量变回猜测。等跑够几轮基线再定门槛。

## 已知会污染测量的因素

- **服务端 vs 端上**：`requiresOnDeviceRecognition` 默认为关，即允许走 Apple 服务端。服务端模型通常更强，设备联网状况会影响结果，所以要记录当时是否联网。
- 同一台设备重复跑结果应稳定；**换设备或换 iOS 版本后不要把数字直接对比**。
- 音频是 AAC/M4A 有损压缩，转写质量受录音质量影响；录音时离麦克风远近会显著影响结果，五段请用一致的姿势。

## 下一步（等测量结果决定，不要提前做）

若偏置确实有正收益 → 值得把**当前阅读段落里的术语**也喂进 `contextualStrings`（现在只喂了书名与作者，见 `speechContextualStrings(for:)`）。那需要一次查找 + 术语抽取，属于真功能，先用测量确认值得再做。
若偏置无收益 → 转向润色提示词的识别错误修复（`TranscriptPolishService`），那是唯一能语义修复混合语种崩坏的地方。
