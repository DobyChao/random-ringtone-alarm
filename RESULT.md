# RESULT — 随机铃声闹钟（HarmonyOS NEXT Stage 工程）

- bundleName：`com.dobychao.randomalarm`（未改动，后续在 AGC 用同一包名申请「代理提醒」开放能力）
- compatibleSdkVersion：`6.0.0(20)`（API 20）；targetSdkVersion：`26.0.0`（API 26，与本机 SDK `HarmonyOS 26.0.0 (API 26 Release)` 对齐）
- 本机已验证：`ohpm install` + `hvigorw clean` + `hvigorw assembleHap`（debug）**构建成功**，产物为未签名 HAP：`entry/build/default/outputs/default/entry-default-unsigned.hap`

## 1. 已实现功能

| 功能 | 实现 |
|---|---|
| 选歌 | `AudioViewPicker` + `AudioSelectOptions`（`maxSelectNumber=50` 多选），未用媒体库扫描、未申请 READ_AUDIO |
| 曲库持久化 | 选择器 URI → **拷贝进应用沙箱** `files/ringtone-library/<alarmId>/`（主策略）；同时尽力调用 `fileShare.persistPermission`（`PolicyInfo{uri, operationMode: READ_MODE}`）持久化来源 URI，成功则在元数据中标记。每只闹钟一个独立曲库，重启后仍在 |
| 随机抽歌 | 每次调度时随机抽一首；曲库 ≥2 首时**避开上一次播放的那首**（不连续重复）；响完后（响铃页「停止」）立即抽出下一首并 `updateReminder` 刷新，下次响铃换新歌 |
| EL1 下一首 | `context.getApplicationContext().createAreaModeContext(contextConstant.AreaMode.EL1)`（同步 API）→ 仅把「下一首要响的」一首拷到 EL1 的 `files/alarm-rings/next-<alarmId>.<ext>`，并清理该闹钟的历史文件（EL1 里只保留当前/下一首，不拷整个曲库） |
| 调度 | 仅用 `@kit.BackgroundTasksKit` 的 `reminderAgentManager`（`REMINDER_TYPE_ALARM` + `hour/minute/daysOfWeek`，1=周一…7=周日，空数组=只响一次）；`publishReminder` / `cancelReminder` / `updateReminder`（API 20+，1700003 时自动回退重新 publish）；按钮仅 关闭(CLOSE) + 贪睡(SNOOZE)；声明 `ohos.permission.PUBLISH_AGENT_REMINDER`；调度前调用 `notificationManager.requestEnableNotification()` |
| **1700002 处理** | 捕获后 UI（列表横幅 + Toast + 编辑页内联）显示中文：**「尚未获得代理提醒权限，功能已就绪，待能力审批后即可调度」**；若已启用提醒数 ≥60 则改为提示数量上限（API 26+ 上限 64 条）。1700002/201 不触发铃声重试（换铃声也无法成功） |
| customRingUri 回退 | `publishWithFallback`：先试 EL1 沙箱 `file://<EL1路径>` → 失败（401/1700007 参数类）依次回退 `$rawfile/default_alarm.wav`、`/rawfile/default_alarm.wav` → 最终回退不设置 `customRingUri`（系统默认铃声）。整条链路可切换、未写死 rawfile |
| 响铃页 | 展示闹钟标签/时间/正在播放曲目名；AVPlayer 播放抽中的用户歌曲（`fdSrc`），失败回退 rawfile 预置；「停止」关播放器+结算下一首；「贪睡」按 reminder SNOOZE 语义发布 N 分钟后的一次性提醒（重新随机抽歌）；系统通知按钮 CLOSE/SNOOZE 由系统按 `snoozeTimes=3 / timeInterval=600s` 处理 |
| CRUD UI（中文） | 列表：时间/重复（「周一至周五」「每天」「一次」等）/标签/曲库数/下一首预览/启用开关/删除（确认框）；编辑：TimePicker、星期多选、标签、启用开关、曲库管理（添加/移除、显示数量与文件名、大小）；开关关闭 `cancelReminder`，打开或保存时重新 publish/update |
| 本地数据 | `preferences`（`getPreferencesSync` + `getSync/putSync/flushSync`）存 JSON：闹钟列表、曲库元数据（显示名/来源 URI/沙箱路径/持久化标记）、当前/下一首、reminderId、snoozeReminderId、1700002 状态 |

## 2. 关键文件

```
AppScope/app.json5                                  # bundleName/版本/图标/应用名
build-profile.json5                                 # compatible 6.0.0(20) / target 26.0.0
entry/src/main/module.json5                         # 权限、ability、skills(randomalarm://)
entry/src/main/ets/
  common/Constants.ets                              # 常量（含 1700002 文案）
  common/AppContext.ets                              # Context 持有 + RingSession（响铃会话）
  model/Alarm.ets                                    # 数据模型 + repeatText 等工具
  service/AlarmStore.ets                             # preferences 持久化
  service/RingtoneLibrary.ets                        # 选歌/拷贝沙箱/persistPermission/随机抽取
  service/NextRingStore.ets                          # EL1 下一首拷贝与清理
  service/ReminderScheduler.ets                      # 调度核心：publish/update/cancel/snooze/
                                                    #   finishRinging、1700002 处理、铃声回退链
  service/AlarmPlayer.ets                            # AVPlayer 封装（沙箱文件 + rawfile）
  entryability/EntryAbility.ets                      # 解析响铃 Want，冷启动直入响铃页
  pages/Index.ets / AlarmEdit.ets / Ringing.ets      # 列表 / 编辑 / 响铃
entry/src/main/resources/rawfile/default_alarm.wav   # 预置兜底铃声（沿用根目录已有文件）
```

## 3. 已知限制

1. **代理提醒开放能力未开通**：`publishReminder` 将返回 1700002（普通应用无该能力时上限视为 0）。应用已完整捕获并给出 SPEC 指定的中文说明，闹钟数据照常保存，能力审批通过后打开开关即可真正调度。**本机无设备，未做真机验证。**
2. **未签名**：`signingConfigs` 为空，产物为 `entry-default-unsigned.hap`。未生成/配置任何正式签名材料（符合本次要求）。安装到真机需调试签名（DevEco Studio 自动签名，或 `hdc install` 前用调试证书签名）。
3. **customRingUri 真机未验证**：官方文档仅承诺 rawfile 下资源且未给出唯一格式示例。已实现 `EL1 file:// → $rawfile/… → /rawfile/… → 系统默认` 回退链与失败自动降级；`file://EL1` 是否被接受需真机确认（日志关键字 `publishReminder ok id=…, ringUri=…` 可看到实际生效的 URI）。
4. `persistPermission` 需 `ohos.permission.FILE_ACCESS_PERSIST`（三方可能拿不到），失败不影响沙箱副本；来源 URI 持久化标记 `persisted` 会如实显示「沙箱副本」。
5. 系统通知上的 SNOOZE 由系统按 `snoozeTimes/timeInterval` 重响（customRingUri 固定为发布时的 URI）；应用内「贪睡」按钮则会重新抽歌。响铃页长按返回/返回键等同「停止」。
6. 编辑页 TimePicker 的 `selected` 仅初始生效（组件行为），修改时间以 onChange 为准。
7. 构建有约 30 条「同步 IO 建议捕获异常」类 WARN（调用侧均有 try/catch 或容错路径），不影响产物。

## 4. Windows 构建命令（工具链按本机 Command Line Tools 与 JDK 21 安装路径配置）

cmd / PowerShell（`hvigorw.bat` 会自动设置 `DEVECO_SDK_HOME`、`DEVECO_NODE_HOME`）：

```bat
set JAVA_HOME=<本机 JDK 21 路径>
set PATH=%JAVA_HOME%\bin;<本机 Command Line Tools>\bin;%PATH%

cd /d <项目根目录>
ohpm install
hvigorw clean
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

产物：`entry\build\default\outputs\default\entry-default-unsigned.hap`

安装（需已签名；未签名包真机安装会被拒绝）：`hdc app install entry-default-signed.hap`
查看构建日志：`.hvigor\outputs\build-logs\build.log`

说明：本项目 hvigor `modelVersion` 为 `6.26.9`（匹配 Command Line Tools 26.0.0.865 / hvigor 6.26.9）；SDK 版本串规则：API 10–25 用 `"6.0.0(20)"` 式，API 26+ 用 `"26.0.0"` 式。

## 5. 建议的下一步

1. 在 AGC 为 `com.dobychao.randomalarm` 申请「代理提醒」开放能力（Agent Reminder）。审批通过后：
   - 无需改代码，打开闹钟开关即会真正调度（1700002 分支自动失效）；
   - 用真机验证 `customRingUri` 对 `file://<EL1路径>` 的接受度（看 hilog 中 `publishReminder ok … ringUri=`），必要时调整 `ReminderScheduler.ets` 中 `RAWFILE_RING_CANDIDATES` 顺序。
2. 配置正式签名：DevEco Studio「File > Project Structure > Signing Configs」登录账号选择证书/Profile，或用 `hvigorw` + `build-profile.json5` 的 `signingConfigs`（手动放入 `.p12/.cer/.p7b` 后打 release 包）。
3. 真机回归：锁屏响铃（EL1 可读性）、系统通知 SNOOZE 语义、多首曲库的「不连续重复」、卸载重装后曲库行为（沙箱随应用卸载清除，属预期）。
4. 可选增强：`maxScreenWantAgent`（锁屏全屏亮屏，当前 API 标记 reserved 未启用）、闹钟响铃渐强、曲库排序/重命名。
