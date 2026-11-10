import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AlarmRecord, RingtoneMeta, findRingtone, stableNotificationId, timeText } from '../model/Alarm';
import { pickNextRingtone } from './RingtoneLibrary';
import { NextRingStore } from './NextRingStore';
import { AlarmStore } from './AlarmStore';
import { RingSession } from '../common/AppContext';
import { Constants } from '../common/Constants';

const TAG = 'ReminderScheduler';

/**
 * 代理提醒调度封装（仅使用 @kit.BackgroundTasksKit 的 reminderAgentManager）：
 * - REMINDER_TYPE_ALARM，hour/minute/daysOfWeek（1=周一…7=周日；空 = 只响一次）
 * - publishReminder / cancelReminder / updateReminder（API 20+）
 * - 操作按钮只有 关闭(CLOSE) + 贪睡(SNOOZE)（三方应用最多 2 个按钮）
 * - publishReminder 未获得「代理提醒」开放能力时返回 1700002：捕获后置 UI 提示，
 *   不再进行铃声回退重试（换铃声也无法成功）。
 * - 铃声 URI 采用可回退链：先试 EL1 沙箱 file:// URI（真机验证目标），
 *   因铃声 URI 无效而失败（401/1700007 等）时依次回退 rawfile 的两种写法，
 *   最终可回退为不设置 customRingUri（系统默认铃声）。
 */

/** rawfile 预置铃声的候选写法（官方文档只承诺 rawfile 下资源，未给出唯一格式示例） */
export const RAWFILE_RING_CANDIDATES: string[] = [
  `$rawfile/${Constants.RAWFILE_DEFAULT_RING}`,
  `/rawfile/${Constants.RAWFILE_DEFAULT_RING}`
];

/** EL1 沙箱路径 → customRingUri 使用的 file:// URI */
export function buildSandboxRingUri(el1Path: string): string {
  return `file://${el1Path}`;
}

export class ScheduleResult {
  ok: boolean = false;
  reminderId: number = -1;
  /** 是否属于「代理提醒能力未开通/无权限」类错误 */
  isPermissionIssue: boolean = false;
  /** 面向用户的中文消息；成功时为空 */
  message: string = '';
}

class PublishOutcome {
  ok: boolean = false;
  reminderId: number = -1;
  usedRingUri: string | null = null;
  error: BusinessError | null = null;
}

function isCapabilityDenied(err: BusinessError | null): boolean {
  return err !== null && (err.code === 1700002 || err.code === 201);
}

function isRingUriRejected(err: BusinessError | null): boolean {
  // 看起来像「参数/铃声 URI 不合法」的错误才值得换一种铃声写法重试
  return err !== null && (err.code === 401 || err.code === 1700007);
}

function errorMessage(err: BusinessError | null, activeReminders: number): string {
  if (err === null) {
    return '调度失败（未知错误）';
  }
  if (err.code === 1700002) {
    // 1700002 = 提醒数量超限。普通应用未获「代理提醒」开放能力时上限视为 0，
    // 同样报 1700002；能力开通后单应用上限 64 条（API 26+），按已启用数量区分提示。
    if (activeReminders >= 60) {
      return '提醒数量已达系统上限（64 条），请删除或停用部分闹钟后重试（错误码 1700002）';
    }
    return `${Constants.AGENT_REMINDER_DENIED_MSG}（错误码 1700002）`;
  }
  if (err.code === 201) {
    return `${Constants.AGENT_REMINDER_DENIED_MSG}（权限被拒绝 201）`;
  }
  if (err.code === 1700001) {
    return '通知未开启：请在系统设置中允许本应用通知后重试';
  }
  if (err.code === 1700003) {
    return '原提醒已不存在，正在重新调度';
  }
  if (err.code === 1700007) {
    return '提醒参数不合法（1700007），请检查时间与星期设置';
  }
  return `调度失败（错误码 ${err.code}）：${err.message}`;
}

/** 当前应用已发布的有效提醒数量（用于区分 1700002 的两种成因） */
function countActiveReminders(): number {
  let count = 0;
  const all = AlarmStore.loadAll();
  for (const a of all) {
    if (a.reminderId >= 0) {
      count++;
    }
    if (a.snoozeReminderId >= 0) {
      count++;
    }
  }
  return count;
}

async function ensureNotificationEnabled(context: common.UIAbilityContext): Promise<void> {
  try {
    await notificationManager.requestEnableNotification(context);
  } catch (e) {
    const err = e as BusinessError;
    hilog.warn(0, TAG, `requestEnableNotification rejected: ${err.code} ${err.message}`);
  }
}

/**
 * 构造提醒触发时拉起响铃页的 WantAgent（reminderAgentManager.WantAgent 结构体）：
 * 点击提醒通知 → 打开 EntryAbility 并携带 randomalarm://ringing 与闹钟参数。
 */
function buildRingWantAgent(alarm: AlarmRecord, snooze: boolean): reminderAgentManager.WantAgent {
  return {
    pkgName: Constants.BUNDLE_NAME,
    abilityName: Constants.ENTRY_ABILITY_NAME,
    uri: Constants.RINGING_URI,
    parameters: {
      'alarmId': alarm.id,
      'ringing': true,
      'snooze': snooze
    }
  };
}

function songNameOf(alarm: AlarmRecord): string {
  const ring: RingtoneMeta | null = findRingtone(alarm, alarm.nextRingId);
  return ring !== null ? ring.displayName : '预置铃声';
}

function buildRequest(alarm: AlarmRecord, ringUri: string | null, agent: reminderAgentManager.WantAgent,
  hour: number, minute: number, daysOfWeek: number[]): reminderAgentManager.ReminderRequestAlarm {
  const request: reminderAgentManager.ReminderRequestAlarm = {
    reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
    hour: hour,
    minute: minute,
    daysOfWeek: daysOfWeek,
    title: alarm.label.length > 0 ? alarm.label : '随机铃声闹钟',
    content: `${timeText(hour, minute)} · 即将播放：${songNameOf(alarm)}`,
    expiredContent: '本次提醒已结束',
    snoozeContent: '已贪睡，稍后再响',
    notificationId: stableNotificationId(alarm.id),
    slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
    ringDuration: Constants.RING_DURATION_SECONDS,
    snoozeTimes: Constants.SNOOZE_TIMES,
    timeInterval: Constants.SNOOZE_INTERVAL_SECONDS,
    actionButton: [
      { title: '关闭', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE },
      { title: '贪睡', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_SNOOZE }
    ],
    wantAgent: agent
  };
  if (ringUri !== null && ringUri.length > 0) {
    request.customRingUri = ringUri;
  }
  return request;
}

/**
 * 带铃声回退链的 publish：
 * 1) 首选 URI（一般是 EL1 沙箱 file:// URI）；
 * 2) 若因铃声 URI 被拒绝（401/1700007），依次尝试 rawfile 两种写法；
 * 3) 最终回退为不设置 customRingUri（系统默认铃声）。
 * 能力类错误（1700002/201/1700001）立即返回，不做铃声重试。
 */
async function publishWithFallback(alarm: AlarmRecord, agent: reminderAgentManager.WantAgent,
  preferredRingUri: string | null, hour: number, minute: number, daysOfWeek: number[]): Promise<PublishOutcome> {
  const candidates: Array<string | null> = [];
  if (preferredRingUri !== null && preferredRingUri.length > 0) {
    candidates.push(preferredRingUri);
  }
  for (const uri of RAWFILE_RING_CANDIDATES) {
    candidates.push(uri);
  }
  candidates.push(null);

  let lastError: BusinessError | null = null;
  for (const uri of candidates) {
    const request = buildRequest(alarm, uri, agent, hour, minute, daysOfWeek);
    try {
      const reminderId = await reminderAgentManager.publishReminder(request);
      const outcome = new PublishOutcome();
      outcome.ok = true;
      outcome.reminderId = reminderId;
      outcome.usedRingUri = uri;
      hilog.info(0, TAG, `publishReminder ok id=${reminderId}, ringUri=${uri === null ? '(系统默认)' : uri}`);
      return outcome;
    } catch (e) {
      const err = e as BusinessError;
      lastError = err;
      hilog.warn(0, TAG, `publishReminder failed (ringUri=${uri}): ${err.code} ${err.message}`);
      if (isCapabilityDenied(err) || err.code === 1700001) {
        break;
      }
      if (!isRingUriRejected(err)) {
        // 其它错误（如提醒数量超限 1700002 之外的限制等）换铃声写法大概率无效，但再试一次链路也无害
        continue;
      }
    }
  }
  const failure = new PublishOutcome();
  failure.error = lastError;
  return failure;
}

function markDeniedIfNeeded(outcome: PublishOutcome, result: ScheduleResult): void {
  if (isCapabilityDenied(outcome.error)) {
    result.isPermissionIssue = true;
    RingSession.agentReminderDenied = true;
    AlarmStore.setAgentReminderDenied(true);
  } else {
    RingSession.agentReminderDenied = false;
    AlarmStore.setAgentReminderDenied(false);
  }
}

/** 随机抽取下一首并拷入 EL1；返回首选 customRingUri（EL1 沙箱 file:// URI），失败/曲库空返回 null */
function stageNextRing(context: common.UIAbilityContext, alarm: AlarmRecord): string | null {
  const next = pickNextRingtone(alarm);
  if (next === null) {
    alarm.nextRingId = '';
    return null;
  }
  alarm.nextRingId = next.id;
  const el1Path = NextRingStore.stageNext(context, alarm, next);
  return el1Path !== null ? buildSandboxRingUri(el1Path) : null;
}

/**
 * 启用或修改闹钟后（重新）调度：
 * - 已有 reminderId 时先尝试 updateReminder（API 20+），提醒不存在（1700003）则重新 publish；
 * - publish 走铃声回退链；1700002/201 捕获后返回中文说明，UI 展示
 *   「尚未获得代理提醒权限，功能已就绪，待能力审批后即可调度」。
 */
export async function scheduleAlarm(context: common.UIAbilityContext, alarm: AlarmRecord): Promise<ScheduleResult> {
  await ensureNotificationEnabled(context);
  const preferred = stageNextRing(context, alarm);
  const agent = buildRingWantAgent(alarm, false);
  const result = new ScheduleResult();

  // 先尝试更新已有提醒
  if (alarm.reminderId >= 0) {
    const updateUri = preferred !== null ? preferred : RAWFILE_RING_CANDIDATES[0];
    const request = buildRequest(alarm, updateUri, agent, alarm.hour, alarm.minute, alarm.daysOfWeek);
    try {
      await reminderAgentManager.updateReminder(alarm.reminderId, request);
      result.ok = true;
      result.reminderId = alarm.reminderId;
      hilog.info(0, TAG, `updateReminder ok id=${alarm.reminderId}`);
      return result;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0, TAG, `updateReminder failed: ${err.code} ${err.message}`);
      if (isCapabilityDenied(err)) {
        alarm.reminderId = -1;
        result.message = errorMessage(err, countActiveReminders());
        markDeniedIfNeeded({ ok: false, reminderId: -1, usedRingUri: null, error: err } as PublishOutcome, result);
        return result;
      }
      // 提醒不存在或其它失败：回退到重新 publish
      alarm.reminderId = -1;
    }
  }

  const outcome = await publishWithFallback(alarm, agent, preferred, alarm.hour, alarm.minute, alarm.daysOfWeek);
  if (outcome.ok) {
    alarm.reminderId = outcome.reminderId;
    result.ok = true;
    result.reminderId = outcome.reminderId;
    RingSession.agentReminderDenied = false;
    AlarmStore.setAgentReminderDenied(false);
  } else {
    alarm.reminderId = -1;
    result.message = errorMessage(outcome.error, countActiveReminders());
    markDeniedIfNeeded(outcome, result);
  }
  return result;
}

/**
 * 响铃页「贪睡」：按 reminder 的 SNOOZE 语义，重新随机抽一首（避开刚播过的），
 * 拷入 EL1，并发布一条 N 分钟后的一次性提醒（daysOfWeek 为空 = 只响一次）。
 */
export async function snoozeAlarm(context: common.UIAbilityContext, alarm: AlarmRecord): Promise<ScheduleResult> {
  await ensureNotificationEnabled(context);
  alarm.lastPlayedRingId = alarm.nextRingId;
  const preferred = stageNextRing(context, alarm);
  const agent = buildRingWantAgent(alarm, true);
  const fireAt = new Date(Date.now() + Constants.SNOOZE_MINUTES * 60 * 1000);
  const result = new ScheduleResult();
  const outcome = await publishWithFallback(alarm, agent, preferred, fireAt.getHours(), fireAt.getMinutes(), []);
  if (outcome.ok) {
    if (alarm.snoozeReminderId >= 0 && alarm.snoozeReminderId !== outcome.reminderId) {
      try {
        await reminderAgentManager.cancelReminder(alarm.snoozeReminderId);
      } catch (e) {
        // 旧贪睡提醒可能已触发/不存在
      }
    }
    alarm.snoozeReminderId = outcome.reminderId;
    result.ok = true;
    result.reminderId = outcome.reminderId;
  } else {
    result.message = errorMessage(outcome.error, countActiveReminders());
    markDeniedIfNeeded(outcome, result);
  }
  return result;
}

/** 停用/删除闹钟：取消其全部提醒 */
export async function cancelAlarm(alarm: AlarmRecord): Promise<void> {
  const ids: number[] = [];
  if (alarm.reminderId >= 0) {
    ids.push(alarm.reminderId);
  }
  if (alarm.snoozeReminderId >= 0) {
    ids.push(alarm.snoozeReminderId);
  }
  for (const id of ids) {
    try {
      await reminderAgentManager.cancelReminder(id);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0, TAG, `cancelReminder ${id} failed: ${err.code} ${err.message}`);
    }
  }
  alarm.reminderId = -1;
  alarm.snoozeReminderId = -1;
}

/**
 * 本次响铃结束（响铃页「停止」）后的结算：
 * - 一次性闹钟（daysOfWeek 为空）：停用并结束；
 * - 重复闹钟：把刚播过的记为 lastPlayed，随机抽出「下一首」拷入 EL1，
 *   并用 updateReminder 刷新系统提醒（下次响铃换新歌，不永远重复同一首）。
 */
export async function finishRinging(context: common.UIAbilityContext | null, alarm: AlarmRecord): Promise<void> {
  if (alarm.snoozeReminderId >= 0) {
    try {
      await reminderAgentManager.cancelReminder(alarm.snoozeReminderId);
    } catch (e) {
      // 可能已自动结束
    }
    alarm.snoozeReminderId = -1;
  }
  alarm.lastPlayedRingId = alarm.nextRingId;

  if (alarm.daysOfWeek.length === 0) {
    // 只响一次的闹钟：响完即止
    alarm.enabled = false;
    alarm.reminderId = -1;
    return;
  }
  if (alarm.library.length === 0 || context === null) {
    return;
  }
  const next = pickNextRingtone(alarm);
  if (next === null) {
    return;
  }
  alarm.nextRingId = next.id;
  const el1Path = NextRingStore.stageNext(context, alarm, next);
  const ringUri = el1Path !== null ? buildSandboxRingUri(el1Path) : RAWFILE_RING_CANDIDATES[0];
  if (alarm.reminderId >= 0) {
    const agent = buildRingWantAgent(alarm, false);
    const request = buildRequest(alarm, ringUri, agent, alarm.hour, alarm.minute, alarm.daysOfWeek);
    try {
      await reminderAgentManager.updateReminder(alarm.reminderId, request);
      hilog.info(0, TAG, `refresh next ring after finishing, id=${alarm.reminderId}`);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0, TAG, `updateReminder after ring failed: ${err.code} ${err.message}`);
    }
  }
}
