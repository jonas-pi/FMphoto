/**
 * 备份目标目录计算。
 *
 * 官方 App 的「备份目录偏好」有 4 档（与服务端 folder_manage_mode 1–4 对应）：
 *   1 默认：交给 NAS（用服务端 upload/path 提示，本机不干预）
 *   2 按拍摄日期：<备份位置>/YYYY/MM（用拍摄时间，不用文件修改时间）
 *   3 按设备文件夹：<备份位置>/<设备内目录>，例如 DCIM/Camera
 *   4 保存在一个文件夹下：<备份位置>
 *
 * 目标路径通过上传时的签名路径头（Trim-Path）告诉服务端，服务端按该路径落盘，
 * 因此不需要服务端新增任何字段。
 */

/** 拼路径：去掉重复斜杠，保留首尾语义。 */
function joinPath(dir: string, name: string): string {
  const d = dir.trim();
  const n = name.trim();
  if (d.length === 0) {
    return n;
  }
  if (n.length === 0) {
    return d;
  }
  const left = d.endsWith('/') ? d.substring(0, d.length - 1) : d;
  const right = n.startsWith('/') ? n.substring(1) : n;
  return `${left}/${right}`;
}

/**
 * 算这张照片在 NAS 上的目标目录（不含文件名）。
 * @param baseDir 备份位置（NAS 上的目录）
 * @param mode 备份目录偏好 1–4
 * @param sourceAlbumPath 来源目录路径，如 /DCIM/Camera
 * @param takenMs 拍摄时间（毫秒）。没有拍摄时间时不要用修改时间或当前时间代替，否则会分错年月。
 */
export function albumBackupTargetDir(
  baseDir: string,
  mode: number,
  sourceAlbumPath: string,
  takenMs: number
): string {
  const base = baseDir.trim();
  if (base.length === 0) {
    return '';
  }
  if (mode === 3) {
    const rel = sourceAlbumPath.trim().replace(/^\/+/, '');
    if (rel.length > 0) {
      return joinPath(base, rel);
    }
    return base;
  }
  if (mode === 2) {
    // 只用拍摄时间。修改时间会把后来编辑、导入过的照片分到错误月份；
    // 当前时间则会把没拍摄时间的照片塞进今天，而且 forceDirHint 会把这个目录固化。
    if (takenMs <= 0) {
      return base;
    }
    const d = new Date(takenMs);
    const m = d.getMonth() + 1;
    const mm = m < 10 ? `0${m}` : `${m}`;
    return joinPath(base, `${d.getFullYear()}/${mm}`);
  }
  return base;
}
