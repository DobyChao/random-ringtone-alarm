import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AlarmRecord, findRingtone, repeatText, timeText } from '../model/Alarm';
import { AlarmStore } from '../service/AlarmStore';
import { scheduleAlarm, cancelAlarm } from '../service/ReminderScheduler';
import { NextRingStore } from '../service/NextRingStore';
import { removeLibraryDir } from '../service/RingtoneLibrary';
import { AppContextHolder, RingSession } from '../common/AppContext';
import { Constants } from '../common/Constants';

const TAG = 'Index';

/** 闹钟列表页：时间 / 重复 / 标签 / 启用开关 / 删除；处理 1700002 横幅 */
@Entry
@Component
struct Index {
  @State alarms: AlarmRecord[] = [];
  @State deniedBanner: boolean = false;
  private busy: boolean = false;

  aboutToAppear(): void {
    const ctx = AppContextHolder.get();
    if (ctx !== null) {
      AlarmStore.init(ctx);
    }
    this.reload();
  }

  onPageShow(): void {
    this.reload();
    // 双保险：若从提醒拉起但落在了列表页，转发到响铃页
    if (RingSession.pendingAlarmId.length > 0) {
      router.replaceUrl({ url: 'pages/Ringing' });
    }
  }

  private reload(): void {
    this.alarms = AlarmStore.loadAll();
    this.deniedBanner = AlarmStore.isAgentReminderDenied() || RingSession.agentReminderDenied;
  }

  private nextRingLabel(alarm: AlarmRecord): string {
    if (!alarm.enabled) {
      return '已停用';
    }
    if (alarm.reminderId < 0) {
      return '待代理提醒能力开通后调度';
    }
    const ring = findRingtone(alarm, alarm.nextRingId);
    return ring !== null ? `下一首：${ring.displayName}` : '下一首：预置铃声';
  }

  private async onToggle(alarm: AlarmRecord, on: boolean): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const list = AlarmStore.loadAll();
    let target: AlarmRecord | null = null;
    for (const a of list) {
      if (a.id === alarm.id) {
        target = a;
        break;
      }
    }
    if (target === null) {
      this.busy = false;
      return;
    }
    target.enabled = on;
    if (on) {
      const ctx = AppContextHolder.get();
      if (ctx !== null) {
        const result = await scheduleAlarm(ctx, target);
        if (!result.ok) {
          promptAction.showToast({ message: result.message, duration: 3500 });
        }
      }
    } else {
      await cancelAlarm(target);
    }
    target.updatedAt = Date.now();
    AlarmStore.saveAll(list);
    this.reload();
    this.busy = false;
  }

  private confirmDelete(alarm: AlarmRecord): void {
    AlertDialog.show({
      title: '删除闹钟',
      message: `确定删除「${timeText(alarm.hour, alarm.minute)}」这只闹钟及其曲库吗？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#E5484D',
        action: () => {
          this.deleteAlarm(alarm);
        }
      },
      cancel: () => {
      }
    });
  }

  private async deleteAlarm(alarm: AlarmRecord): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const list = AlarmStore.loadAll();
    let index = -1;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === alarm.id) {
        index = i;
        break;
      }
    }
    if (index >= 0) {
      await cancelAlarm(list[index]);
      const ctx = AppContextHolder.get();
      if (ctx !== null) {
        NextRingStore.removeAll(ctx, list[index].id);
        removeLibraryDir(ctx, list[index].id);
      }
      list.splice(index, 1);
      AlarmStore.saveAll(list);
    }
    this.reload();
    this.busy = false;
  }

  build() {
    Column() {
      Row() {
        Text('随机铃声闹钟')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#202124')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 10 })
      .justifyContent(FlexAlign.Start)

      if (this.deniedBanner) {
        Row() {
          Text(`⚠ ${Constants.AGENT_REMINDER_DENIED_MSG}`)
            .fontSize(13)
            .fontColor('#8A5A00')
            .lineHeight(18)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#FFF3D6')
        .borderRadius(10)
        .margin({ left: 12, right: 12, bottom: 6 })
        .alignItems(VerticalAlign.Center)
      }

      if (this.alarms.length === 0) {
        Column({ space: 8 }) {
          Text('还没有闹钟')
            .fontSize(16)
            .fontColor('#9AA0A6')
          Text('点击下方按钮创建第一只闹钟')
            .fontSize(13)
            .fontColor('#9AA0A6')
        }
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
      } else {
        List({ space: 10 }) {
          ForEach(this.alarms, (alarm: AlarmRecord) => {
            ListItem() {
              this.AlarmItem(alarm)
            }
          }, (alarm: AlarmRecord) => `${alarm.id}-${alarm.enabled}-${alarm.updatedAt}-${alarm.library.length}-${alarm.nextRingId}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 12, right: 12, top: 4 })
      }

      Button('＋ 新建闹钟')
        .width('90%')
        .height(46)
        .fontSize(16)
        .backgroundColor('#3D7EFF')
        .margin(12)
        .onClick(() => {
          router.pushUrl({ url: 'pages/AlarmEdit' });
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }

  @Builder
  AlarmItem(alarm: AlarmRecord) {
    Row() {
      Column({ space: 4 }) {
        Text(timeText(alarm.hour, alarm.minute))
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(alarm.enabled ? '#202124' : '#9AA0A6')
        Row({ space: 6 }) {
          Text(repeatText(alarm.daysOfWeek))
            .fontSize(13)
            .fontColor(alarm.enabled ? '#5F6368' : '#9AA0A6')
          if (alarm.label.length > 0) {
            Text(`· ${alarm.label}`)
              .fontSize(13)
              .fontColor(alarm.enabled ? '#5F6368' : '#9AA0A6')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 120 })
          }
          Text(`${alarm.library.length} 首`)
            .fontSize(12)
            .fontColor('#3D7EFF')
        }
        .alignItems(VerticalAlign.Center)
        Text(this.nextRingLabel(alarm))
          .fontSize(12)
          .fontColor('#9AA0A6')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        router.pushUrl({ url: 'pages/AlarmEdit', params: { alarmId: alarm.id } });
      })

      Column({ space: 12 }) {
        Toggle({ type: ToggleType.Switch, isOn: alarm.enabled })
          .onChange((isOn: boolean) => {
            this.onToggle(alarm, isOn);
          })
        Text('删除')
          .fontSize(13)
          .fontColor('#E5484D')
          .padding({ top: 2, bottom: 2, left: 6, right: 6 })
          .onClick(() => {
            this.confirmDelete(alarm);
          })
      }
      .alignItems(HorizontalAlign.Center)
    }
    .padding(14)
    .borderRadius(14)
    .backgroundColor(Color.White)
  }
}
