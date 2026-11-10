/**
 * 数据模型：闹钟与曲库元数据。所有字段可被 JSON 序列化后写入 preferences。
 */

/** 曲库中的一首歌（已拷入应用沙箱，来源 URI 尽力持久化） */
export interface RingtoneMeta {
  /** 唯一 id（UUID） */
  id: string;
  /** 展示名（一般为去掉扩展名的文件名） */
  displayName: string;
  /** 选择器返回的来源 URI（若 persistPermission 成功则重启后仍可用） */
  sourceUri: string;
  /** 应用沙箱内的绝对路径（曲库的持久化主体，卸载前一直可用） */
  sandboxPath: string;
  /** 文件大小（字节） */
  size: number;
  /** 来源 URI 是否已成功持久化授权 */
  persisted: boolean;
}

/** 一只闹钟 */
export interface AlarmRecord {
  id: string;
  /** 0-23 */
  hour: number;
  /** 0-59 */
  minute: number;
  /** 重复星期，1=周一 … 7=周日（reminderAgentManager daysOfWeek 语义）；空数组 = 只响一次 */
  daysOfWeek: number[];
  /** 标签 */
  label: string;
  /** 是否启用 */
  enabled: boolean;
  /** 本闹钟自己的曲库 */
  library: RingtoneMeta[];
  /** 下一次（或当前正在响）要播放的曲目 id；空串 = 使用预置铃声 */
  nextRingId: string;
  /** 上一次实际播放过的曲目 id（用于避免连续重复同一首） */
  lastPlayedRingId: string;
  /** 已发布的重复闹钟提醒 id；-1 = 未发布 */
  reminderId: number;
  /** 贪睡产生的一次性提醒 id；-1 = 无 */
  snoozeReminderId: number;
  createdAt: number;
  updatedAt: number;
}

/** 星期展示标签，下标 0=周一 … 6=周日（与 daysOfWeek 的 1..7 对应） */
export const DAY_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

export function createAlarm(now: number): AlarmRecord {
  return {
    id: '',
    hour: 7,
    minute: 30,
    daysOfWeek: [],
    label: '',
    enabled: true,
    library: [],
    nextRingId: '',
    lastPlayedRingId: '',
    reminderId: -1,
    snoozeReminderId: -1,
    createdAt: now,
    updatedAt: now
  };
}

export function cloneRingtone(r: RingtoneMeta): RingtoneMeta {
  return {
    id: r.id,
    displayName: r.displayName,
    sourceUri: r.sourceUri,
    sandboxPath: r.sandboxPath,
    size: r.size,
    persisted: r.persisted
  };
}

export function cloneAlarm(a: AlarmRecord): AlarmRecord {
  const library: RingtoneMeta[] = [];
  for (const r of a.library) {
    library.push(cloneRingtone(r));
  }
  const days: number[] = [];
  for (const d of a.daysOfWeek) {
    days.push(d);
  }
  return {
    id: a.id,
    hour: a.hour,
    minute: a.minute,
    daysOfWeek: days,
    label: a.label,
    enabled: a.enabled,
    library: library,
    nextRingId: a.nextRingId,
    lastPlayedRingId: a.lastPlayedRingId,
    reminderId: a.reminderId,
    snoozeReminderId: a.snoozeReminderId,
    createdAt: a.createdAt,
    updatedAt: a.updatedAt
  };
}

/** 在曲库中按 id 查找 */
export function findRingtone(alarm: AlarmRecord, ringId: string): RingtoneMeta | null {
  if (ringId.length === 0) {
    return null;
  }
  for (const r of alarm.library) {
    if (r.id === ringId) {
      return r;
    }
  }
  return null;
}

/** 重复规则的中文描述 */
export function repeatText(daysOfWeek: number[]): string {
  if (daysOfWeek === undefined || daysOfWeek === null || daysOfWeek.length === 0) {
    return '一次';
  }
  const sorted: number[] = [];
  for (let d = 1; d <= 7; d++) {
    if (daysOfWeek.indexOf(d) >= 0) {
      sorted.push(d);
    }
  }
  if (sorted.length === 0) {
    return '一次';
  }
  if (sorted.length === 7) {
    return '每天';
  }
  if (sorted.length === 5 && sorted[0] === 1 && sorted[1] === 2 && sorted[2] === 3 && sorted[3] === 4 && sorted[4] === 5) {
    return '周一至周五';
  }
  if (sorted.length === 2 && sorted[0] === 6 && sorted[1] === 7) {
    return '周末';
  }
  const parts: string[] = [];
  for (const d of sorted) {
    parts.push('周' + DAY_LABELS[d - 1]);
  }
  return parts.join('、');
}

export function twoDigits(n: number): string {
  return n < 10 ? '0' + n.toString() : n.toString();
}

export function timeText(hour: number, minute: number): string {
  return twoDigits(hour) + ':' + twoDigits(minute);
}

/** 由闹钟 id 生成稳定的通知 id（同一只闹钟重复发布时覆盖旧通知） */
export function stableNotificationId(id: string): number {
  let h = 0;
  for (let i = 0; i < id.length; i++) {
    h = (h * 31 + id.charCodeAt(i)) % 900000;
  }
  return 100000 + h;
}
