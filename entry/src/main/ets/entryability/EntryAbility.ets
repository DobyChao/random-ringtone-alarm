import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContextHolder, RingSession } from '../common/AppContext';
import { Constants } from '../common/Constants';

const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppContextHolder.set(this.context);
    this.consumeRingWant(want);
  }

  onDestroy(): void {
  }

  onForeground(): void {
  }

  onBackground(): void {
  }

  /** 应用已在运行时，reminder 的 wantAgent 再次拉起会走这里 */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (this.consumeRingWant(want)) {
      this.jumpToRinging();
    }
  }

  /** 识别「响铃」Want（randomalarm://ringing 或 parameters.ringing=true），写入 RingSession */
  private consumeRingWant(want: Want | undefined): boolean {
    if (want === undefined || want === null) {
      return false;
    }
    let ringing = want.uri === Constants.RINGING_URI;
    const params = want.parameters;
    if (params !== undefined && params !== null) {
      const flag = params['ringing'];
      ringing = ringing || flag === true || flag === 'true';
    }
    if (!ringing) {
      return false;
    }
    let alarmId = '';
    let snooze = false;
    if (params !== undefined && params !== null) {
      const idValue = params['alarmId'];
      if (typeof idValue === 'string') {
        alarmId = idValue;
      }
      const snoozeValue = params['snooze'];
      snooze = snoozeValue === true || snoozeValue === 'true';
    }
    RingSession.pendingAlarmId = alarmId;
    RingSession.pendingSnooze = snooze;
    return true;
  }

  private jumpToRinging(): void {
    window.getLastWindow(this.context).then((win: window.Window) => {
      win.getUIContext().getRouter().replaceUrl({ url: 'pages/Ringing' });
    }).catch((e: Object) => {
      hilog.error(0, TAG, `jumpToRinging failed: ${JSON.stringify(e)}`);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 冷启动且来自提醒时直接进入响铃页
    const entryPage = RingSession.pendingAlarmId.length > 0 ? 'pages/Ringing' : 'pages/Index';
    windowStage.loadContent(entryPage, (err) => {
      if (err.code) {
        hilog.error(0, TAG, `loadContent failed: ${JSON.stringify(err)}`);
        return;
      }
      hilog.info(0, TAG, 'loadContent succeed');
    });
  }
}
