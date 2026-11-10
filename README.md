# 随机铃声闹钟

HarmonyOS NEXT 闹钟应用：为每只闹钟维护独立曲库，调度时随机抽取下一首铃声。

- 包名：com.dobychao.randomalarm
- 兼容 API 20，目标 API 26
- 选歌使用系统 AudioViewPicker，不申请 READ_AUDIO
- 调度使用 reminderAgentManager（需在 AppGallery Connect 为该包名申请「代理提醒」能力）

本地构建（需 JDK 21 与 Huawei Command Line Tools）：

`at
ohpm install
hvigorw clean
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
`

真机安装需要调试签名（证书和 Profile 请自行保管，不要提交到仓库）。更细的实现说明见 RESULT.md。
