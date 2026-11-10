import { fileIo } from '@kit.CoreFileKit';
import { common, contextConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AlarmRecord, RingtoneMeta } from '../model/Alarm';
import { Constants } from '../common/Constants';

const TAG = 'NextRingStore';

/**
 * EL1「下一首」管理：
 * 通过 applicationContext.createAreaModeContext(AreaMode.EL1) 拿到设备级加密区上下文，
 * 只把「下一首即将要响的」那一首拷贝到 EL1 的 files/alarm-rings/ 下（省空间），
 * 保证锁屏前（设备级加密，开机即可访问）系统代理提醒也能读到文件。
 * EL1 目录内每只闹钟只保留一份 next-<alarmId>.<ext>，其余历史文件会被清理。
 */
export class NextRingStore {
  private static el1Context: common.Context | null = null;

  static el1(context: common.Context): common.Context {
    if (NextRingStore.el1Context === null) {
      const appContext = context.getApplicationContext();
      NextRingStore.el1Context = appContext.createAreaModeContext(contextConstant.AreaMode.EL1);
    }
    return NextRingStore.el1Context;
  }

  static ringDir(context: common.Context): string {
    return `${NextRingStore.el1(context).filesDir}/${Constants.EL1_RING_DIR}`;
  }

  /**
   * 把选中的下一首拷入 EL1。
   * @returns EL1 内绝对路径；失败返回 null（调用方应回退 rawfile 预置铃声）。
   */
  static stageNext(context: common.Context, alarm: AlarmRecord, ring: RingtoneMeta): string | null {
    try {
      const dir = NextRingStore.ringDir(context);
      try {
        fileIo.mkdirSync(dir, true);
      } catch (e) {
        // 已存在时忽略
      }
      const ext = ring.sandboxPath.lastIndexOf('.') > 0
        ? ring.sandboxPath.substring(ring.sandboxPath.lastIndexOf('.') + 1) : 'mp3';
      const dest = `${dir}/next-${alarm.id}.${ext}`;
      fileIo.copyFileSync(ring.sandboxPath, dest);
      NextRingStore.cleanup(context, alarm.id, dest);
      hilog.info(0, TAG, `staged next ring to ${dest}`);
      return dest;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0, TAG, `stageNext failed: ${err.code} ${err.message}`);
      return null;
    }
  }

  /** 清理该闹钟在 EL1 中的历史「下一首」文件，只保留当前这份 */
  static cleanup(context: common.Context, alarmId: string, keep: string): void {
    try {
      const dir = NextRingStore.ringDir(context);
      const names = fileIo.listFileSync(dir);
      for (const name of names) {
        if (!name.startsWith('next-')) {
          continue;
        }
        const full = `${dir}/${name}`;
        if (full !== keep && name === `next-${alarmId}.${name.substring(name.lastIndexOf('.') + 1)}`) {
          try {
            fileIo.unlinkSync(full);
          } catch (e) {
            // 忽略单个文件删除失败
          }
        }
      }
    } catch (e) {
      // 目录可能尚不存在
    }
  }

  /** 删除该闹钟在 EL1 中的全部铃声（删除闹钟时调用） */
  static removeAll(context: common.Context, alarmId: string): void {
    try {
      const dir = NextRingStore.ringDir(context);
      const names = fileIo.listFileSync(dir);
      for (const name of names) {
        if (name.startsWith(`next-${alarmId}.`)) {
          try {
            fileIo.unlinkSync(`${dir}/${name}`);
          } catch (e) {
            // 忽略单个文件删除失败
          }
        }
      }
    } catch (e) {
      // 目录可能尚不存在
    }
  }
}
