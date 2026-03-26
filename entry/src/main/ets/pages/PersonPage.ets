import { router } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import { AiPersonItem, GalleryGetListData, GalleryListItem } from '../model/FnApiTypes';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import { GalleryNetworkThumb, nasUrl } from '../album/GalleryAlbumCommon';

const DATE_FEED_BATCH = 50;
const DAY_MAX_ROUNDS = 300;

interface TimelineDayModel {
  year: number;
  month: number;
  day: number;
  itemCount: number;
}

function fmtDayStart(y: number, m: number, d: number): string {
  return `${y}:${m.toString().padStart(2, '0')}:${d.toString().padStart(2, '0')} 00:00:00`;
}

function fmtDayEnd(y: number, m: number, d: number): string {
  return `${y}:${m.toString().padStart(2, '0')}:${d.toString().padStart(2, '0')} 23:59:59`;
}

function listFromData(data: GalleryGetListData | undefined): GalleryListItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  const raw = data.list ?? data.items ?? data.photos ?? data.records;
  return Array.isArray(raw) ? raw : [];
}

@Entry
@Component
struct PersonPage {
  @State private baseUrl: string = '';
  @State private loading: boolean = false;
  @State private opening: boolean = false;
  @State private error: string = '';
  @State private items: AiPersonItem[] = [];

  onBackPress(): boolean {
    router.back();
    return true;
  }

  aboutToAppear(): void {
    // 返回到该页时确保遮罩状态被清理
    this.opening = false;
    const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
    if (rp !== undefined && rp['baseUrl'] !== undefined) {
      this.baseUrl = String(rp['baseUrl']);
    }
    void this.loadData();
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {}
  }

  private personName(item: AiPersonItem): string {
    const n = item.name ?? item.nickName;
    return n !== undefined && n.length > 0 ? n : '未命名人物';
  }

  private personFace(item: AiPersonItem): string {
    if (item.faceUrl !== undefined && item.faceUrl.length > 0) {
      return item.faceUrl;
    }
    const id = item.faceId ?? item.avatarId ?? item.posterId ?? item.coverId ?? item.id;
    if (id === undefined || id === null) {
      return '';
    }
    return `/p/api/v1/stream/face/${String(id)}`;
  }

  private personId(item: AiPersonItem): string {
    if (item.id === undefined || item.id === null) {
      return '';
    }
    return String(item.id);
  }

  private personStatText(item: AiPersonItem): string {
    const p = Number(item.photoCount);
    const v = Number(item.videoCount);
    if (Number.isFinite(p) || Number.isFinite(v)) {
      return `${Number.isFinite(p) ? Math.max(0, Math.floor(p)) : 0} 张照片 · ${Number.isFinite(v) ? Math.max(0, Math.floor(v)) : 0} 个视频`;
    }
    const total = Number(item.itemCount ?? item.count ?? item.total);
    return Number.isFinite(total) ? `共 ${Math.max(0, Math.floor(total))} 项` : '点击查看';
  }

  private parsePersonTimeline(rawList: Array<Record<string, string | number | undefined>>): TimelineDayModel[] {
    const out: TimelineDayModel[] = [];
    for (let i = 0; i < rawList.length; i++) {
      const x = rawList[i];
      let y = 0;
      let m = 0;
      let d = 0;
      const yy = x['year'];
      const mm = x['month'];
      const dd = x['day'];
      if (typeof yy === 'number' && typeof mm === 'number' && typeof dd === 'number') {
        y = Math.floor(yy);
        m = Math.floor(mm);
        d = Math.floor(dd);
      } else {
        const stRaw = x['start_time'] ?? x['startTime'];
        const st = stRaw !== undefined ? String(stRaw) : '';
        const space = st.indexOf(' ');
        const date = space > 0 ? st.substring(0, space) : st;
        const seg = date.split(':');
        if (seg.length < 3) {
          continue;
        }
        y = Number(seg[0]);
        m = Number(seg[1]);
        d = Number(seg[2]);
      }
      if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) {
        continue;
      }
      const cRaw = x['itemCount'] ?? x['item_count'] ?? x['count'] ?? x['total'] ?? x['size'] ?? x['num'];
      const c = cRaw !== undefined && Number.isFinite(Number(cRaw)) ? Math.max(0, Math.floor(Number(cRaw))) : 0;
      out.push({ year: Math.floor(y), month: Math.floor(m), day: Math.floor(d), itemCount: c });
    }
    return out.sort((a, b): number => {
      if (a.year !== b.year) { return b.year - a.year; }
      if (a.month !== b.month) { return b.month - a.month; }
      return b.day - a.day;
    });
  }

  private async loadData(): Promise<void> {
    this.loading = true;
    this.error = '';
    this.items = [];
    const client = AppSession.getClient();
    if (client === null) {
      this.loading = false;
      this.error = '未登录';
      return;
    }
    try {
      const res = await client.getAiPersonList(true, -1, 0);
      if (!res.success || res.data === undefined) {
        this.error = res.message ?? '人物列表加载失败';
        this.loading = false;
        return;
      }
      const raw = res.data.list ?? res.data.items ?? res.data.records ?? [];
      const out: AiPersonItem[] = [];
      for (let i = 0; i < raw.length; i++) {
        const el = raw[i];
        if (typeof el === 'object' && el !== null) {
          out.push(el as AiPersonItem);
        }
      }
      this.items = out;
      if (out.length === 0) {
        this.error = '暂无人物';
      }
    } catch (e) {
      this.error = String(e) || '人物列表加载异常';
    }
    this.loading = false;
  }

  private async openPerson(item: AiPersonItem): Promise<void> {
    if (this.opening) {
      return;
    }
    const pid = this.personId(item);
    if (pid.length === 0) {
      this.toast('人物 ID 无效');
      return;
    }
    this.opening = true;
    let title = this.personName(item);
    let keepOpening = false;
    try {
      const client = AppSession.getClient();
      if (client === null) {
        this.toast('未登录');
        return;
      }
      const detail = await client.getAiPersonDetail(pid);
      let detailItemCount = 0;
      if (detail.success && detail.data !== undefined) {
        if (detail.data.name !== undefined && detail.data.name.length > 0) {
          title = detail.data.name;
        }
        const cntRaw = detail.data.itemCount;
        if (cntRaw !== undefined && Number.isFinite(Number(cntRaw))) {
          detailItemCount = Math.max(0, Math.floor(Number(cntRaw)));
        }
      }
      const tl = await client.getAiPersonPhotoTimeline(pid);
      if (!tl.success || tl.data === undefined) {
        this.toast(tl.message ?? '人物时间线加载失败');
        return;
      }
      const raw = tl.data.list ?? [];
      const rawIn: Array<Record<string, string | number | undefined>> = [];
      for (let i = 0; i < raw.length; i++) {
        const el = raw[i];
        if (typeof el === 'object' && el !== null) {
          rawIn.push(el as Record<string, string | number | undefined>);
        }
      }
      const days = this.parsePersonTimeline(rawIn);
      const merged: GalleryListItem[] = [];
      for (let di = 0; di < days.length; di++) {
        const day = days[di];
        const st = fmtDayStart(day.year, day.month, day.day);
        const et = fmtDayEnd(day.year, day.month, day.day);
        let off = 0;
        let rounds = 0;
        while (rounds < DAY_MAX_ROUNDS) {
          const one = await client.getAiPersonPhotoList(pid, st, et, DATE_FEED_BATCH, off, 20000);
          if (!one.success || one.data === undefined) {
            break;
          }
          const list = listFromData(one.data);
          if (list.length === 0) {
            break;
          }
          for (let i = 0; i < list.length; i++) {
            merged.push(list[i]);
          }
          off += list.length;
          rounds++;
          if (detailItemCount > 0 && merged.length >= detailItemCount) {
            break;
          }
          if (list.length < DATE_FEED_BATCH) {
            break;
          }
          if (day.itemCount > 0 && off >= day.itemCount) {
            break;
          }
        }
      }
      if (merged.length === 0) {
        this.toast('该人物暂无可预览媒体');
        return;
      }
      keepOpening = true;
      const opened = await CategoryGalleryNavStore.open(this.baseUrl, title, merged, this.getUIContext());
      if (!opened) {
        keepOpening = false;
        this.toast('打开人物媒体失败');
        return;
      }
      setTimeout((): void => {
        this.opening = false;
      }, 280);
    } finally {
      if (!keepOpening) {
        this.opening = false;
      }
    }
  }

  build() {
    Column() {
      Row() {
        Button('返回').height(34).onClick((): void => { router.back(); })
        Text('人物').layoutWeight(1).fontSize(20).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
        Blank().width(56)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 8 })

      if (this.loading) {
        Row({ space: 10 }) {
          LoadingProgress().width(28).height(28)
          Text('人物加载中…').fontSize(14).fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.error.length > 0) {
        Text(this.error)
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 24, right: 24, top: 40 })
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Grid() {
            ForEach(this.items, (item: AiPersonItem, idx: number) => {
              GridItem() {
                Column({ space: 8 }) {
                  GalleryNetworkThumb({
                    uri: nasUrl(this.baseUrl, this.personFace(item))
                  })
                    .width('100%')
                    .aspectRatio(1)
                    .borderRadius(12)
                  Text(this.personName(item))
                    .fontSize(13)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(this.personStatText(item))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }
                .width('100%')
                .padding({ left: 2, right: 2, bottom: 8 })
                .onClick((): void => { void this.openPerson(item); })
              }
            }, (_item: AiPersonItem, i: number) => `person_${i}`)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 10 })

          if (this.opening && !this.loading) {
            Column({ space: 12 }) {
              LoadingProgress().width(48).height(48).color(Color.White)
              Text('加载人物媒体中…').fontSize(14).fontColor(Color.White)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor('#80000000')
            .hitTestBehavior(HitTestMode.Block)
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
