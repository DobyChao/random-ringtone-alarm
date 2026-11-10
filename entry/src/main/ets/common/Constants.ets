/**
 * 全局常量。bundleName 与 AGC 申请「代理提醒」开放能力时使用的包名一致，禁止改动。
 */
export class Constants {
  static readonly BUNDLE_NAME: string = 'com.dobychao.randomalarm';
  static readonly ENTRY_ABILITY_NAME: string = 'EntryAbility';
  /** wantAgent 拉起响铃页使用的 URI（与 module.json5 中 skills.uris 对应） */
  static readonly RINGING_URI: string = 'randomalarm://ringing';
  /** rawfile 目录下的预置兜底铃声（系统代理提醒在无法使用自定义铃声时使用） */
  static readonly RAWFILE_DEFAULT_RING: string = 'default_alarm.wav';
  /** 应用沙箱（EL2）内每只闹钟的曲库目录名，位于 files/ 下 */
  static readonly RING_LIBRARY_DIR: string = 'ringtone-library';
  /** EL1 设备级加密区内仅保存「下一首要响的」铃声的目录名 */
  static readonly EL1_RING_DIR: string = 'alarm-rings';
  /** 应用内贪睡：N 分钟后再响 */
  static readonly SNOOZE_MINUTES: number = 10;
  /** 代理提醒自身铃声时长（秒） */
  static readonly RING_DURATION_SECONDS: number = 60;
  /** 代理提醒通知上「贪睡」按钮的语义：最多小睡次数与间隔（秒） */
  static readonly SNOOZE_TIMES: number = 3;
  static readonly SNOOZE_INTERVAL_SECONDS: number = 600;
  /** 代理提醒开放能力未开通（publishReminder 返回 1700002）时的统一中文说明 */
  static readonly AGENT_REMINDER_DENIED_MSG: string = '尚未获得代理提醒权限，功能已就绪，待能力审批后即可调度';
}
