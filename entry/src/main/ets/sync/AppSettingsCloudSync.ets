/**
 * 把配置信封写入 fmphoto_cfg.db 的 appsettings 表，再交给华为云空间同步。
 * 库名、表名、字段与 AGC 开发环境里已保存的容器一致。
 */
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { fnDiagError } from '../common/FnDiagLog';

const TAG = 'CloudSync';
const DB_NAME = 'fmphoto_cfg.db';
const TABLE = 'appsettings';
const ROW_ID = 'default';
const CLOUD_SPACE_URI = 'hicloud://cloudDrive/getInfo?path=MainActivity';

export class CloudSyncResult {
  ok: boolean = false;
  message: string = '';
  payload: string = '';
}

let storePromise: Promise<relationalStore.RdbStore> | null = null;

async function openStore(ctx: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
  if (storePromise !== null) {
    return storePromise;
  }
  storePromise = openStoreOnce(ctx).catch((err: Object) => {
    storePromise = null;
    throw err as Error;
  });
  return storePromise;
}

async function openStoreOnce(ctx: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
  const config: relationalStore.StoreConfig = {
    name: DB_NAME,
    securityLevel: relationalStore.SecurityLevel.S1
  };
  const store = await relationalStore.getRdbStore(ctx, config);
  await store.executeSql(
    'CREATE TABLE IF NOT EXISTS appsettings (id TEXT PRIMARY KEY, updated_at INTEGER, payload TEXT)'
  );
  const dist: relationalStore.DistributedConfig = { autoSync: true };
  await store.setDistributedTables([TABLE], relationalStore.DistributedType.DISTRIBUTED_CLOUD, dist);
  return store;
}

function fail(err: Object): CloudSyncResult {
  const result = new CloudSyncResult();
  const be = err as BusinessError;
  if (be.code === 801) {
    result.message = '当前系统不支持云空间同步（需要 HarmonyOS 6.1 及以上）';
    return result;
  }
  const msg = be.message !== undefined ? be.message : '';
  result.message = msg.length > 0 ? msg : '云空间同步失败';
  return result;
}

async function writeRow(store: relationalStore.RdbStore, json: string): Promise<void> {
  const values: relationalStore.ValuesBucket = {
    'id': ROW_ID,
    'payload': json,
    'updated_at': Date.now()
  };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', ROW_ID);
  const changed = await store.update(values, predicates);
  if (changed === 0) {
    await store.insert(TABLE, values);
  }
}

async function readPayload(store: relationalStore.RdbStore): Promise<string> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', ROW_ID);
  const result = await store.query(predicates, ['payload']);
  try {
    if (!result.goToFirstRow()) {
      return '';
    }
    const index = result.getColumnIndex('payload');
    if (index < 0) {
      return '';
    }
    return result.getString(index);
  } finally {
    result.close();
  }
}

async function runCloudSync(store: relationalStore.RdbStore, mode: relationalStore.SyncMode): Promise<void> {
  await store.cloudSync(mode, [TABLE], (_details: relationalStore.ProgressDetails): void => {
  });
}

/** 把当前信封写入本地表，再按本机优先推到云空间。 */
export async function pushSettingsToCloud(ctx: common.UIAbilityContext, json: string): Promise<CloudSyncResult> {
  try {
    const store = await openStore(ctx);
    await writeRow(store, json);
    await runCloudSync(store, relationalStore.SyncMode.SYNC_MODE_NATIVE_FIRST);
    const result = new CloudSyncResult();
    result.ok = true;
    result.message = '已上传到云空间';
    return result;
  } catch (err) {
    // 只记错误本身，不记 payload（里面有账号与地址）。
    fnDiagError(TAG, 'push cloud sync failed', err as Object);
    return fail(err as Object);
  }
}

/** 云端优先拉回本地表，并返回信封 JSON。 */
export async function pullSettingsFromCloud(ctx: common.UIAbilityContext): Promise<CloudSyncResult> {
  try {
    const store = await openStore(ctx);
    await runCloudSync(store, relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST);
    const payload = await readPayload(store);
    const result = new CloudSyncResult();
    if (payload.length === 0) {
      result.message = '云空间里还没有配置';
      return result;
    }
    result.ok = true;
    result.payload = payload;
    result.message = '已从云空间下载';
    return result;
  } catch (err) {
    fnDiagError(TAG, 'pull cloud sync failed', err as Object);
    return fail(err as Object);
  }
}

/** 打开系统云空间首页，方便打开本应用的同步开关。 */
export async function openHuaweiCloudSpace(ctx: common.UIAbilityContext): Promise<string> {
  const want: Want = { uri: CLOUD_SPACE_URI };
  try {
    await ctx.startAbility(want);
    return '';
  } catch (err) {
    const be = err as BusinessError;
    const msg = be.message !== undefined ? be.message : '';
    return msg.length > 0 ? msg : '暂时无法打开云空间';
  }
}
