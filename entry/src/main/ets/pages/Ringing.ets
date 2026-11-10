import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AlarmRecord, findRingtone, timeText } from '../model/Alarm';
import { AlarmStore } from '../service/AlarmStore';
import { AlarmPlayer } from '../service/AlarmPlayer';
import { snoozeAlarm, finishRinging } from '../service/ReminderScheduler';
import { AppContextHolder, RingSession } from '../common/AppContext';
import { Constants } from '../common/Constants';

const TAG = 'Ringing';

/** 响铃页：展示标签/时间/曲目，AVPlayer 播放抽中的歌曲，提供 停止 / 贪睡 */
@Entry
@Component
struct Ringing {
  @State labelText: string = '随机铃声闹钟';
  @State timeLabelText: string = '';
  @State songName: string = '';
  @State operating: boolean = false;
  private player: AlarmPlayer = new AlarmPlayer();
  private alarmId: string = '';
  private busy: boolean = false;

  aboutToAppear(): void {
    const ctx = AppContextHolder.get();
    if (ctx !== null) {
      AlarmStore.init(ctx);
    }
    let id = RingSession.pendingAlarmId;
    let snooze = RingSession.pendingSnooze;
    if (id.length === 0) {
      const params = router.getParams() as Record<string, Object> | undefined;
      if (params !== undefined && params !== null) {
        const value = params['alarmId'];
        if (typeof value === 'string') {
          id = value;
        }
        const flag = params['snooze'];
        snooze = flag === true || flag === 'true';
      }
    }
    RingSession.pendingAlarmId = '';
    RingSession.pendingSnooze = false;
    this.alarmId = id;
    this.startRinging(snooze);
  }

  aboutToDisappear(): void {
    this.player.release().catch((e: BusinessError) => {
      hilog.warn(0, TAG, `release on disappear failed: ${e.code}`);
    });
  }

  private async startRinging(snooze: boolean): Promise<void> {
    const now = new Date();
    this.timeLabelText = timeText(now.getHours(), now.getMinutes());

    let alarm: AlarmRecord | null = null;
    const list = AlarmStore.loadAll();
    for (const a of list) {
      if (a.id === this.alarmId) {
        alarm = a;
        break;
      }
    }
    if (alarm !== null && snooze && alarm.snoozeReminderId >= 0) {
      // 贪睡的一次性提醒已触发：清掉记录（避免下次误取消）
      alarm.snoozeReminderId = -1;
      AlarmStore.saveAll(list);
    }

    if (alarm !== null && alarm.label.length > 0) {
      this.labelText = alarm.label;
    }
    const ring = alarm !== null ? findRingtone(alarm, alarm.nextRingId) : null;
    if (ring !== null) {
      this.songName = ring.displayName;
      try {
        await this.player.playSandboxFile(ring.sandboxPath);
        return;
      } catch (e) {
        const err = e as BusinessError;
        hilog.error(0, TAG, `play sandbox file failed: ${err.code} ${err.message}`);
      }
    }
    this.songName = '预置铃声';
    this.playDefault();
  }

  private playDefault(): void {
    const ctx = AppContextHolder.get();
    if (ctx === null) {
      return;
    }
    this.player.playRawfile(ctx, Constants.RAWFILE_DEFAULT_RING).catch((e: BusinessError) => {
      hilog.error(0, TAG, `play rawfile failed: ${e.code} ${e.message}`);
    });
  }

  private backToList(): void {
    router.replaceUrl({ url: 'pages/Index' });
  }

  /** 停止：关掉播放器；重复闹钟立即抽出「下一首」并刷新系统提醒 */
  private async onStop(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.operating = true;
    await this.player.release();
    const ctx = AppContextHolder.get();
    const list = AlarmStore.loadAll();
    for (const a of list) {
      if (a.id === this.alarmId) {
        await finishRinging(ctx, a);
        break;
      }
    }
    AlarmStore.saveAll(list);
    this.backToList();
  }

  /** 贪睡：N 分钟后重新随机抽歌再响（一次性提醒，SNOOZE 语义） */
  private async onSnooze(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.operating = true;
    await this.player.release();
    const ctx = AppContextHolder.get();
    let message = '';
    const list = AlarmStore.loadAll();
    for (const a of list) {
      if (a.id === this.alarmId) {
        if (a.enabled && ctx !== null) {
          const result = await snoozeAlarm(ctx, a);
          if (result.ok) {
            message = `已贪睡，${Constants.SNOOZE_MINUTES} 分钟后再响`;
          } else {
            message = result.message;
          }
        } else {
          message = '闹钟未启用，无法贪睡';
        }
        break;
      }
    }
    AlarmStore.saveAll(list);
    promptAction.showToast({ message: message.length > 0 ? message : '已贪睡', duration: 2500 });
    this.backToList();
  }

  onBackPress(): boolean {
    this.onStop();
    return true;
  }

  build() {
    Column({ space: 18 }) {
      Blank()
      Column({ space: 8 }) {
        Text('⏰')
          .fontSize(56)
        Text(this.labelText)
          .fontSize(20)
          .fontColor('#EAF1FF')
        Text(this.timeLabelText)
          .fontSize(64)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .alignItems(HorizontalAlign.Center)

      Column({ space: 6 }) {
        Text('正在播放')
          .fontSize(13)
          .fontColor('#9FB4D8')
        Text(this.songName)
          .fontSize(18)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '86%' })
      }
      .alignItems(HorizontalAlign.Center)
      .padding(12)

      Blank()
      Row({ space: 16 }) {
        Button('停止')
          .fontSize(18)
          .fontColor(Color.White)
          .height(52)
          .layoutWeight(1)
          .backgroundColor('#E5484D')
          .enabled(!this.operating)
          .onClick(() => {
            this.onStop();
          })
        Button('贪睡')
          .fontSize(18)
          .fontColor(Color.White)
          .height(52)
          .layoutWeight(1)
          .backgroundColor('#3D7EFF')
          .enabled(!this.operating)
          .onClick(() => {
            this.onSnooze();
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 40 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1B2A4A')
    .alignItems(HorizontalAlign.Center)
  }
}
