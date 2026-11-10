import { common } from '@kit.AbilityKit';

/**
 * 持有 UIAbilityContext，供页面/服务在非组件环境（如 EntryAbility 之外）获取上下文。
 */
export class AppContextHolder {
  private static ctx: common.UIAbilityContext | null = null;

  static set(context: common.UIAbilityContext): void {
    AppContextHolder.ctx = context;
  }

  static get(): common.UIAbilityContext | null {
    return AppContextHolder.ctx;
  }
}

/**
 * 响铃会话：wantAgent 拉起应用时，由 EntryAbility 写入，Ringing 页消费。
 */
export class RingSession {
  /** 待响铃的闹钟 id；空串表示无 */
  static pendingAlarmId: string = '';
  /** 本次响铃是否来自「贪睡后的一次性提醒」 */
  static pendingSnooze: boolean = false;
  /** 最近一次调度是否因代理提醒能力未开通（1700002/201）而失败 */
  static agentReminderDenied: boolean = false;
}
