import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AlarmRecord, RingtoneMeta, DAY_LABELS, createAlarm } from '../model/Alarm';
import { AlarmStore } from '../service/AlarmStore';
import { pickAndImport, removeRingtone } from '../service/RingtoneLibrary';
import { scheduleAlarm, cancelAlarm } from '../service/ReminderScheduler';
import { AppContextHolder } from '../common/AppContext';

const TAG = 'AlarmEdit';

/** 编辑/新建页：时间选择、星期多选、标签、启用、曲库管理（添加/移除） */
@Entry
@Component
struct AlarmEdit {
  @State hour: number = 7;
  @State minute: number = 30;
  @State daySelected: boolean[] = [false, false, false, false, false, false, false];
  @State label: string = '';
  @State enabledSwitch: boolean = true;
  @State songs: RingtoneMeta[] = [];
  @State statusMsg: string = '';
  @State picking: boolean = false;
  @State saving: boolean = false;
  private timeInit: Date = new Date(2026, 0, 1, 7, 30);
  private isNew: boolean = true;
  private editingId: string = '';

  aboutToAppear(): void {
    const ctx = AppContextHolder.get();
    if (ctx !== null) {
      AlarmStore.init(ctx);
    }
    const params = router.getParams() as Record<string, Object> | undefined;
    let alarmId = '';
    if (params !== undefined && params !== null) {
      const value = params['alarmId'];
      if (typeof value === 'string') {
        alarmId = value;
      }
    }
    if (alarmId.length > 0) {
      const list = AlarmStore.loadAll();
      for (const a of list) {
        if (a.id === alarmId) {
          this.applyAlarm(a);
          this.isNew = false;
          this.editingId = a.id;
          break;
        }
      }
    }
  }

  private applyAlarm(a: AlarmRecord): void {
    this.hour = a.hour;
    this.minute = a.minute;
    for (let i = 0; i < 7; i++) {
      this.daySelected[i] = a.daysOfWeek.indexOf(i + 1) >= 0;
    }
    this.label = a.label;
    this.enabledSwitch = a.enabled;
    this.songs = [];
    for (const s of a.library) {
      this.songs.push(s);
    }
    this.timeInit = new Date(2026, 0, 1, a.hour, a.minute);
  }

  /** 构造草稿（新增歌曲需要先有稳定的闹钟 id 与曲库目录） */
  private draft(): AlarmRecord {
    if (this.editingId.length === 0) {
      this.editingId = util.generateRandomUUID();
    }
    const alarm = createAlarm(Date.now());
    alarm.id = this.editingId;
    alarm.hour = this.hour;
    alarm.minute = this.minute;
    for (let i = 0; i < 7; i++) {
      if (this.daySelected[i]) {
        alarm.daysOfWeek.push(i + 1);
      }
    }
    alarm.label = this.label;
    alarm.enabled = this.enabledSwitch;
    for (const s of this.songs) {
      alarm.library.push(s);
    }
    return alarm;
  }

  private async addSongs(): Promise<void> {
    if (this.picking) {
      return;
    }
    const ctx = AppContextHolder.get();
    if (ctx === null) {
      return;
    }
    this.picking = true;
    const draft = this.draft();
    try {
      const added = await pickAndImport(ctx, draft);
      if (added > 0) {
        this.songs = [];
        for (const s of draft.library) {
          this.songs.push(s);
        }
        promptAction.showToast({ message: `已添加 ${added} 首歌曲`, duration: 2000 });
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.info(0, TAG, `pick canceled or failed: ${err.code} ${err.message}`);
    }
    this.picking = false;
  }

  private removeSong(songId: string): void {
    const draft = this.draft();
    removeRingtone(draft, songId);
    this.songs = [];
    for (const s of draft.library) {
      this.songs.push(s);
    }
  }

  private sizeText(size: number): string {
    if (size >= 1024 * 1024) {
      return `${(size / (1024 * 1024)).toFixed(1)} MB`;
    }
    return `${Math.max(1, Math.round(size / 1024))} KB`;
  }

  private back(): void {
    router.back();
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    const ctx = AppContextHolder.get();
    if (ctx === null) {
      this.back();
      return;
    }
    this.saving = true;
    this.statusMsg = '';
    const list = AlarmStore.loadAll();
    const alarm = this.draft();

    let target: AlarmRecord | null = null;
    if (!this.isNew) {
      for (const a of list) {
        if (a.id === this.editingId) {
          target = a;
          break;
        }
      }
    }
    if (target === null) {
      list.push(alarm);
      target = alarm;
    } else {
      target.hour = alarm.hour;
      target.minute = alarm.minute;
      target.daysOfWeek = alarm.daysOfWeek;
      target.label = alarm.label;
      target.enabled = alarm.enabled;
      target.library = alarm.library;
      // 下一首引用若已不在曲库中则清空，调度时会重抽
      let found = false;
      for (const s of target.library) {
        if (s.id === target.nextRingId) {
          found = true;
          break;
        }
      }
      if (!found) {
        target.nextRingId = '';
      }
    }

    if (target.enabled) {
      const result = await scheduleAlarm(ctx, target);
      if (!result.ok) {
        // 保存闹钟数据，但停留在本页展示失败原因（如 1700002 能力未开通）
        target.updatedAt = Date.now();
        AlarmStore.saveAll(list);
        this.statusMsg = result.message;
        this.saving = false;
        return;
      }
    } else {
      await cancelAlarm(target);
    }
    target.updatedAt = Date.now();
    AlarmStore.saveAll(list);
    this.saving = false;
    this.back();
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Text('‹ 返回')
            .fontSize(16)
            .fontColor('#3D7EFF')
            .padding({ top: 4, bottom: 4, right: 8 })
            .onClick(() => this.back())
          Blank()
          Text(this.isNew ? '新建闹钟' : '编辑闹钟')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#202124')
          Blank()
          Text('‹ 返回')
            .fontSize(16)
            .fontColor(Color.Transparent)
            .padding({ top: 4, bottom: 4, left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Column({ space: 6 }) {
          Text('时间')
            .fontSize(14)
            .fontColor('#5F6368')
          TimePicker({ selected: this.timeInit })
            .useMilitaryTime(true)
            .onChange((value: TimePickerResult) => {
              this.hour = value.hour;
              this.minute = value.minute;
            })
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor(Color.White)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 10 }) {
          Text('重复')
            .fontSize(14)
            .fontColor('#5F6368')
          Row({ space: 8 }) {
            ForEach(DAY_LABELS, (day: string, index: number) => {
              Text(day)
                .fontSize(14)
                .fontColor(this.daySelected[index] ? Color.White : '#5F6368')
                .width(36)
                .height(36)
                .textAlign(TextAlign.Center)
                .borderRadius(18)
                .backgroundColor(this.daySelected[index] ? '#3D7EFF' : '#F1F3F5')
                .onClick(() => {
                  const next = !this.daySelected[index];
                  this.daySelected[index] = next;
                })
            }, (day: string, index: number) => `${day}-${index}-${this.daySelected[index]}`)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          Text('不选任何星期 = 只响一次')
            .fontSize(12)
            .fontColor('#9AA0A6')
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor(Color.White)
        .alignItems(HorizontalAlign.Start)

        Row() {
          Text('标签')
            .fontSize(14)
            .fontColor('#5F6368')
            .layoutWeight(1)
          TextInput({ placeholder: '例如：起床（可选）', text: this.label })
            .layoutWeight(2)
            .backgroundColor(Color.Transparent)
            .fontSize(15)
            .onChange((value: string) => {
              this.label = value;
            })
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor(Color.White)

        Row() {
          Text('启用')
            .fontSize(15)
            .fontColor('#202124')
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.enabledSwitch })
            .onChange((isOn: boolean) => {
              this.enabledSwitch = isOn;
            })
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor(Color.White)

        Column({ space: 10 }) {
          Row() {
            Text(`曲库（${this.songs.length} 首）`)
              .fontSize(14)
              .fontColor('#5F6368')
              .layoutWeight(1)
            Button(this.picking ? '选择中…' : '添加歌曲')
              .fontSize(14)
              .height(34)
              .backgroundColor('#3D7EFF')
              .onClick(() => {
                this.addSongs();
              })
          }
          .width('100%')

          if (this.songs.length === 0) {
            Text('曲库为空时将使用预置铃声；每次响铃会从曲库随机抽歌')
              .fontSize(12)
              .fontColor('#9AA0A6')
          } else {
            ForEach(this.songs, (song: RingtoneMeta) => {
              Row() {
                Column({ space: 2 }) {
                  Text(song.displayName)
                    .fontSize(15)
                    .fontColor('#202124')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(this.sizeText(song.size) + (song.persisted ? ' · 已持久授权' : ' · 沙箱副本'))
                    .fontSize(11)
                    .fontColor('#9AA0A6')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('移除')
                  .fontSize(13)
                  .fontColor('#E5484D')
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .onClick(() => {
                    this.removeSong(song.id);
                  })
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
            }, (song: RingtoneMeta) => `${song.id}-${song.persisted}`)
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor(Color.White)
        .alignItems(HorizontalAlign.Start)

        if (this.statusMsg.length > 0) {
          Text(this.statusMsg)
            .fontSize(13)
            .fontColor('#C4402F')
            .backgroundColor('#FDECEC')
            .borderRadius(8)
            .padding(10)
            .width('100%')
        }

        Button(this.saving ? '保存中…' : '保存')
          .width('100%')
          .height(46)
          .fontSize(16)
          .backgroundColor('#3D7EFF')
          .margin({ top: 4, bottom: 20 })
          .enabled(!this.saving)
          .onClick(() => {
            this.save();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 6 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
    .scrollBar(BarState.Off)
  }
}
