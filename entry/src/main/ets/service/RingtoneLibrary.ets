import { picker, fileShare, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AlarmRecord, RingtoneMeta } from '../model/Alarm';
import { Constants } from '../common/Constants';

const TAG = 'RingtoneLibrary';

/** 某只闹钟的曲库目录（应用沙箱 EL2 files 下） */
export function ringLibraryDir(context: common.Context, alarmId: string): string {
  return `${context.filesDir}/${Constants.RING_LIBRARY_DIR}/${alarmId}`;
}

function ensureDir(dir: string): void {
  try {
    fileIo.mkdirSync(dir, true);
  } catch (e) {
    // 已存在时忽略
  }
}

function displayFileNameOf(uri: string): string {
  let name = uri;
  const idx = uri.lastIndexOf('/');
  if (idx >= 0) {
    name = uri.substring(idx + 1);
  }
  try {
    name = decodeURIComponent(name);
  } catch (e) {
    // 名称非 URI 编码时保留原样
  }
  return name;
}

function extensionOf(fileName: string, fallback: string): string {
  const dot = fileName.lastIndexOf('.');
  if (dot > 0 && dot < fileName.length - 1) {
    return fileName.substring(dot + 1).toLowerCase();
  }
  return fallback;
}

/**
 * 用 AudioViewPicker 多选手机里的音乐，并把文件拷贝进该闹钟自己的沙箱曲库。
 * 同时对选择器返回的来源 URI 尽力调用 fileShare.persistPermission 做持久化授权；
 * 即使持久化失败（权限受限等），沙箱副本也保证卸载前的可用性。
 *
 * @returns 本次成功导入的歌曲数
 */
export async function pickAndImport(context: common.Context, alarm: AlarmRecord): Promise<number> {
  const audioPicker = new picker.AudioViewPicker(context);
  const options = new picker.AudioSelectOptions();
  options.maxSelectNumber = 50;
  const uris: Array<string> = await audioPicker.select(options);
  if (uris === undefined || uris === null || uris.length === 0) {
    return 0;
  }
  ensureDir(ringLibraryDir(context, alarm.id));

  const imported: RingtoneMeta[] = [];
  for (const uri of uris) {
    try {
      const fileName = displayFileNameOf(uri);
      const ext = extensionOf(fileName, 'mp3');
      const id = util.generateRandomUUID();
      const dest = `${ringLibraryDir(context, alarm.id)}/${id}.${ext}`;
      const src = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      fileIo.copyFileSync(src.fd, dest);
      fileIo.closeSync(src);
      const stat = fileIo.statSync(dest);
      const dot = fileName.lastIndexOf('.');
      const displayName = dot > 0 ? fileName.substring(0, dot) : fileName;
      const meta: RingtoneMeta = {
        id: id,
        displayName: displayName,
        sourceUri: uri,
        sandboxPath: dest,
        size: stat.size,
        persisted: false
      };
      imported.push(meta);
      alarm.library.push(meta);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0, TAG, `import ${uri} failed: ${err.code} ${err.message}`);
    }
  }

  // 尽力而为：持久化来源 URI（失败不影响沙箱副本使用）
  if (imported.length > 0) {
    try {
      const policies: Array<fileShare.PolicyInfo> = [];
      for (const m of imported) {
        policies.push({ uri: m.sourceUri, operationMode: fileShare.OperationMode.READ_MODE });
      }
      await fileShare.persistPermission(policies);
      for (const m of imported) {
        m.persisted = true;
      }
      hilog.info(0, TAG, 'persistPermission ok');
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(0, TAG, `persistPermission failed (已保留沙箱副本): ${err.code} ${err.message}`);
    }
  }
  return imported.length;
}

/** 从曲库移除一首（删除沙箱文件并清理引用） */
export function removeRingtone(alarm: AlarmRecord, ringId: string): void {
  let index = -1;
  for (let i = 0; i < alarm.library.length; i++) {
    if (alarm.library[i].id === ringId) {
      index = i;
      break;
    }
  }
  if (index < 0) {
    return;
  }
  const meta = alarm.library[index];
  try {
    fileIo.unlinkSync(meta.sandboxPath);
  } catch (e) {
    // 文件可能已不存在
  }
  alarm.library.splice(index, 1);
  if (alarm.nextRingId === ringId) {
    alarm.nextRingId = '';
  }
  if (alarm.lastPlayedRingId === ringId) {
    alarm.lastPlayedRingId = '';
  }
}

/** 删除某只闹钟的整个曲库目录 */
export function removeLibraryDir(context: common.Context, alarmId: string): void {
  try {
    fileIo.rmdirSync(ringLibraryDir(context, alarmId));
  } catch (e) {
    // 目录可能已不存在
  }
}

/**
 * 随机抽取下一首铃声：
 * - 曲库为空返回 null（由调用方回退预置铃声）；
 * - 只有一首时恒定返回该首；
 * - 多首时避开上一次播放过的那首（曲库≥2 首时不连续重复）。
 */
export function pickNextRingtone(alarm: AlarmRecord): RingtoneMeta | null {
  if (alarm.library.length === 0) {
    return null;
  }
  if (alarm.library.length === 1) {
    return alarm.library[0];
  }
  const pool: RingtoneMeta[] = [];
  for (const r of alarm.library) {
    if (r.id !== alarm.lastPlayedRingId) {
      pool.push(r);
    }
  }
  if (pool.length === 0) {
    pool.push(alarm.library[0]);
  }
  const index = Math.floor(Math.random() * pool.length);
  return pool[index];
}
