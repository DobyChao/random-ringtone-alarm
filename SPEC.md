# 随机铃声闹钟（HarmonyOS NEXT Stage 工程）

请在当前工作目录（`--cwd`）创建完整可构建的 HarmonyOS 应用源码，不要只写说明或设计文档。这是从零开始的工程，目录现在基本是空的。

## 身份与约束

- 应用显示名：随机铃声闹钟
- bundleName：**com.dobychao.randomalarm**（禁止改动，用户将用同一包名在 AGC 申请代理提醒）
- targetSdkVersion：**26**
- compatibleSdkVersion：**20**
- 模型：Stage 模型，HarmonyOS NEXT / API 20+
- 不要初始化或推送 GitHub 仓库；不要发版；不要写正式签名材料
- 签名/Profile：用调试/本地占位即可。用户还没有华为「代理提醒」开放能力；`publishReminder` 没有该能力时会返回 **1700002**，必须捕获并在 UI 上用中文说明「尚未获得代理提醒权限，功能已就绪，待能力审批后即可调度」
- 工程要能在 Windows 本机用 Huawei Command Line Tools 26.0.0.865 + hvigorw / ohpm 构建（你在 Linux 上只需把源码和构建配置写对）
- 不要申请 `ohos.permission.READ_AUDIO` / 读媒体库权限

## 必须实现的产品行为

1. **选歌**：用 `AudioViewPicker` + `AudioSelectOptions` 多选手机里的音乐。不要用媒体库扫描替代。
2. **曲库持久化**：选择器返回的 URI 是临时的。必须用 `persistPermission`，或把文件拷进应用沙箱，做成「每一只闹钟自己的曲库」。卸载/重启后曲库仍在。
3. **随机**：每次调度这只闹钟时，从该闹钟曲库随机抽一首。重复闹钟：这次响完之后再抽下一首（不要永远重复同一首，除非曲库只有一首）。
4. **EL1 下一首**：只把「下一首即将要响的」那一首拷到 EL1 的 `files/alarm-rings/`（省空间）。不是只能选一首，曲库可以多首；EL1 目录里保持当前/下一首，不要把整个曲库都拷进 EL1。
   - 使用 `AreaMode.EL1` / `createAreaModeContext`（或当前文档推荐的等价 API）拿到设备级加密区，保证锁屏前代理提醒也能读到文件。
5. **调度**：只用 `@kit.BackgroundTasksKit` 的 `reminderAgentManager`。**禁止**已废弃的 `@ohos.reminderAgent`。
   - 类型：`REMINDER_TYPE_ALARM`
   - 字段：`hour` / `minute` / `daysOfWeek`（1–7；空数组或未设 = 只响一次）
   - API：`publishReminder` / `cancelReminder` / `updateReminder`（API 20+）
   - 操作按钮只做 **CLOSE** + **SNOOZE**（三方应用最多 2 个按钮）
   - 权限声明：`ohos.permission.PUBLISH_AGENT_REMINDER`
   - 运行时调用 `notificationManager.requestEnableNotification()`（通知授权）
6. **铃声策略**：
   - 官方文档：`customRingUri` 只支持 `resources/rawfile` 预置音。
   - 系统代理提醒本身使用 rawfile 里的预置兜底铃声。
   - `wantAgent` 打开应用内「响铃页」；响铃页用 **AVPlayer** 播放抽中的用户歌曲。
   - 额外做一层可回退尝试：真机上验证 `customRingUri` 是否接受通知那套 `uri::` + EL1 沙箱 URI。用清晰的辅助函数封装：先尝试沙箱 URI，失败或捕获错误则回退 rawfile。不要把整条调度链路写死成只能 rawfile、也无法切换。
7. **响铃页**：展示闹钟标签/时间、正在播放的曲目名（若有）、停止、贪睡。停止时关掉 AVPlayer；贪睡按 reminder 的 SNOOZE 语义（并在下次响铃前重新随机抽歌，若这是重复/贪睡后的下一次）。
8. **闹钟 CRUD UI**（中文、简洁）：
   - 列表：时间、重复（例如「周一至周五」或「一次」）、标签、启用开关、删除
   - 编辑/新建：时间选择、星期多选、标签、启用、管理曲库（添加/移除歌曲、显示已选数量与文件名）
   - 开关关闭时 `cancelReminder`；打开或修改时重新 `publish`/`update`
9. **本地数据**：用 preferences 或应用文件中的 JSON 持久化闹钟列表、每只闹钟的曲库元数据（显示名、持久 URI 或沙箱路径）、当前/下一首信息、reminderId。

## 工程文件

生成标准 HarmonyOS 应用结构，至少包括：

- `AppScope/app.json5`（bundleName、vendor、version、icon/label）
- `AppScope/resources` 应用名「随机铃声闹钟」
- `entry/src/main/module.json5`（abilities、skills、requestPermissions：`ohos.permission.PUBLISH_AGENT_REMINDER` 等必要权限；不要 READ_AUDIO）
- `entry/src/main/ets/` 页面与 Ability（EntryAbility、闹钟列表、编辑、响铃页）
- `entry/src/main/resources/base/profile/main_pages.json`（或当前模板等价物）
- `entry/src/main/resources/rawfile/` 放预置兜底铃声（若目录里已有 `default_alarm.wav` 请直接引用，不要删）
- `build-profile.json5`、`oh-package.json5`、`hvigorfile.ts`、`hvigor/hvigor-config.json5`、`entry/build-profile.json5`、`entry/oh-package.json5`、`entry/hvigorfile.ts`、`code-linter.json5`、`.gitignore`
- SDK / compileSdk 与 target 26、compatible 20 对齐
- 如需 `srcEntry` / `skills` 以便 wantAgent 拉起响铃页，请配置正确的 ability 与 URI/entities

模块划分建议（可按你的判断微调，但职责要清楚）：

- `model/Alarm.ets` 数据模型
- `service/AlarmStore.ets` 持久化
- `service/RingtoneLibrary.ets` 选歌、persist/拷贝、曲库
- `service/NextRingStore.ets` EL1 下一首拷贝
- `service/ReminderScheduler.ets` reminderAgentManager 封装（含 1700002 处理、customRingUri 回退）
- `service/AlarmPlayer.ets` AVPlayer
- 页面：列表、编辑、响铃

## API 提示（请再核对官方文档，不要盲信）

- 后台代理提醒：`@kit.BackgroundTasksKit` → `reminderAgentManager`。参考：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/background-tasks-arkts
- 已废弃、禁止使用：`@ohos.reminderAgent`（https://developer.huawei.com/consumer/cn/doc/harmonyos-references/background-tasks-arkts-dep）
- 选歌：`AudioViewPicker` / `AudioSelectOptions`，一般在 `@kit.CoreFileKit` 的 picker 或 `@ohos.file.picker`
- URI 持久化：`fileShare.persistPermission` 或文档推荐的 persistable URI permission
- 通知：`@kit.NotificationKit` 的 `notificationManager.requestEnableNotification()`
- 播放：`@kit.MediaKit` 的 `media.createAVPlayer()` / AVPlayer，参考 https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-media-avplayer
- wantAgent：`@kit.AbilityKit`
- EL1：`contextConstant.AreaMode.EL1` + `applicationContext.createAreaModeContext`（名称以你查到的 API 20 文档为准）

如果某 API 在 API 20–26 之间有更名，优先用 kit 风格 `@kit.*` 新 API。

## 完成标准

- 工程文件齐全，配置里的 bundleName / SDK 版本正确
- 上述功能都有对应实现，而不是 TODO 空壳（1700002 与 customRingUri 回退必须有实际代码路径）
- UI 文案为中文
- 在仓库根目录写 `RESULT.md`，用中文写清：
  1. 已实现功能列表
  2. 关键文件路径
  3. 已知限制（代理提醒能力、签名、customRingUri 真机未验证等）
  4. 在 Windows 上用 Command Line Tools 构建调试包的命令（hvigorw / ohpm），工具链使用本机已安装的 Huawei Command Line Tools
  5. 建议的下一步（等 AGC 代理提醒批下来后接正式 Profile / 手动签名）

不要创建 git 仓库（可以写 .gitignore，但不要 `git init`）。
