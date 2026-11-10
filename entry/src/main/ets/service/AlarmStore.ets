import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AlarmRecord } from '../model/Alarm';

const TAG = 'AlarmStore';
const STORE_NAME = 'random_ringtone_alarm_store';
const KEY_ALARMS = 'alarms';
const KEY_DENIED = 'agent_reminder_denied';

/**
 * 闹钟列表与曲库元数据的持久化（preferences + JSON 字符串）。
 * 卸载/重启后仍在；曲库音频文件本体存于应用沙箱 files/ringtone-library/ 下。
 */
export class AlarmStore {
  private static pref: preferences.Preferences | null = null;

  static init(context: common.Context): void {
    if (AlarmStore.pref === null) {
      AlarmStore.pref = preferences.getPreferencesSync(context, { name: STORE_NAME });
    }
  }

  static loadAll(): AlarmRecord[] {
    const p = AlarmStore.pref;
    if (p === null) {
      return [];
    }
    const raw = p.getSync(KEY_ALARMS, '[]') as string;
    try {
      return JSON.parse(raw) as AlarmRecord[];
    } catch (e) {
      hilog.error(0, TAG, `parse alarms failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  static saveAll(alarms: AlarmRecord[]): void {
    const p = AlarmStore.pref;
    if (p === null) {
      return;
    }
    p.putSync(KEY_ALARMS, JSON.stringify(alarms));
    p.flushSync();
  }

  /** 记录「代理提醒能力未开通」状态，用于列表页横幅 */
  static setAgentReminderDenied(denied: boolean): void {
    const p = AlarmStore.pref;
    if (p === null) {
      return;
    }
    p.putSync(KEY_DENIED, denied);
    p.flushSync();
  }

  static isAgentReminderDenied(): boolean {
    const p = AlarmStore.pref;
    if (p === null) {
      return false;
    }
    return p.getSync(KEY_DENIED, false) as boolean;
  }
}
