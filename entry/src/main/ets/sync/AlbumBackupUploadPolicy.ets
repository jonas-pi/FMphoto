/**
 * 备份/同步上传的客户端策略（无 NAS 字段）：流量、低电量、仅照片。
 */
import { batteryInfo } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { getAlbumBackupSettingsCached } from './AlbumBackupSettings';

export class AlbumBackupUploadGate {
  allowed: boolean = true;
  reason: string = '';
}

const VIDEO_EXT: string[] = ['.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm', '.3gp'];

export function isLikelyVideoFileName(fileName: string): boolean {
  const lower = fileName.trim().toLowerCase();
  if (lower.length === 0) {
    return false;
  }
  for (let i = 0; i < VIDEO_EXT.length; i++) {
    if (lower.endsWith(VIDEO_EXT[i])) {
      return true;
    }
  }
  return false;
}

function netUsesCellular(): boolean {
  try {
    const net = connection.getDefaultNetSync();
    const caps = connection.getNetCapabilitiesSync(net);
    const bearers = caps.bearerTypes;
    if (bearers === undefined || bearers.length === 0) {
      return false;
    }
    for (let i = 0; i < bearers.length; i++) {
      if (bearers[i] === connection.NetBearType.BEARER_CELLULAR) {
        return true;
      }
    }
  } catch (_e) {
  }
  return false;
}

export async function evaluateAlbumBackupUploadGate(): Promise<AlbumBackupUploadGate> {
  const gate = new AlbumBackupUploadGate();
  const s = getAlbumBackupSettingsCached();
  if (s.stopWhenBatteryLow) {
    try {
      const level = batteryInfo.batterySOC;
      if (Number.isFinite(level) && level >= 0 && level < 15) {
        gate.allowed = false;
        gate.reason = '电量低于15%，已暂停备份';
        return gate;
      }
    } catch (_e) {
    }
  }
  if (!s.useCellularData && netUsesCellular()) {
    gate.allowed = false;
    gate.reason = '未开启「使用流量备份」';
    return gate;
  }
  return gate;
}
