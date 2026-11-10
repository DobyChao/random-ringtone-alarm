import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'AlarmPlayer';

/**
 * 响铃页播放器：AVPlayer 播放抽中的用户歌曲（沙箱文件），
 * 失败时由调用方回退到 rawfile 预置铃声（playRawfile）。
 */
export class AlarmPlayer {
  private player: media.AVPlayer | null = null;
  private openedFd: number = -1;
  private playing: boolean = false;

  isPlaying(): boolean {
    return this.playing;
  }

  /** 播放应用沙箱内的音频文件 */
  async playSandboxFile(path: string): Promise<void> {
    await this.release();
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    this.openedFd = file.fd;
    const stat = fileIo.statSync(file.fd);
    await this.playFd(file.fd, 0, stat.size);
  }

  /** 播放 rawfile 预置铃声 */
  async playRawfile(context: common.Context, name: string): Promise<void> {
    await this.release();
    const descriptor = await context.resourceManager.getRawFd(name);
    await this.playFd(descriptor.fd, descriptor.offset, descriptor.length);
  }

  private async playFd(fd: number, offset: number, length: number): Promise<void> {
    const player = await media.createAVPlayer();
    this.player = player;
    player.on('error', (err: BusinessError) => {
      hilog.error(0, TAG, `AVPlayer error: ${err.code} ${err.message}`);
    });
    return new Promise<void>((resolve, reject) => {
      player.on('stateChange', (state: string) => {
        if (state === 'initialized') {
          player.prepare().catch((e: BusinessError) => {
            reject(e);
          });
        } else if (state === 'prepared') {
          player.play().catch((e: BusinessError) => {
            reject(e);
          });
        } else if (state === 'playing') {
          this.playing = true;
          resolve();
        } else if (state === 'error') {
          reject(new Error('AVPlayer 进入错误状态'));
        }
      });
      player.on('error', (err: BusinessError) => {
        reject(err);
      });
      // 仅 idle 状态可设置数据源
      player.fdSrc = { fd: fd, offset: offset, length: length } as media.AVFileDescriptor;
    });
  }

  async stop(): Promise<void> {
    this.playing = false;
    if (this.player !== null) {
      try {
        await this.player.stop();
      } catch (e) {
        // 忽略停止失败（可能尚未进入可停止状态）
      }
    }
  }

  async release(): Promise<void> {
    this.playing = false;
    const player = this.player;
    this.player = null;
    if (player !== null) {
      try {
        await player.release();
      } catch (e) {
        const err = e as BusinessError;
        hilog.warn(0, TAG, `release failed: ${err.code} ${err.message}`);
      }
    }
    if (this.openedFd >= 0) {
      try {
        fileIo.closeSync(this.openedFd);
      } catch (e) {
        // fd 可能已随 release 关闭
      }
      this.openedFd = -1;
    }
  }
}
