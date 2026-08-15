/**
 * 官方图库风格视频浮层。
 * 沉浸光感与底栏相同：HdsTabs 必须给明确宽高（与 Home 侧钮一致），不能用 100% 去撑 wrap 父节点。
 * 图标/文字叠在 HdsTabs 材质之上居中，避免页签默认内边距把 Symbol 顶偏。
 */
import { LengthMetrics, SymbolGlyphModifier } from '@kit.ArkUI';
import { BlurStrategy, DividerMode, HdsTabs } from '@kit.UIDesignKit';
import { fnHdsImmersiveTabsFloatingStyle } from '../common/FnUiCommon';

interface GalleryVideoSpeedOption {
  label: string;
  rate: number;
}

const GALLERY_VIDEO_SPEED_OPTIONS: GalleryVideoSpeedOption[] = [
  { label: '0.25X', rate: 0.25 },
  { label: '0.5X', rate: 0.5 },
  { label: '1.0X', rate: 1.0 },
  { label: '1.5X', rate: 1.5 },
  { label: '2.0X', rate: 2.0 }
];

const OVERLAY_PILL_HEIGHT_VP: number = 36;
const OVERLAY_SPEED_WIDTH_VP: number = 60;
const OVERLAY_TIME_WIDTH_VP: number = 124;
const OVERLAY_LANDSCAPE_SIZE_VP: number = 36;
const OVERLAY_PLAY_SIZE_VP: number = 72;

@Component
struct GalleryOverlayHdsCapsule {
  @Prop widthValue: number = OVERLAY_LANDSCAPE_SIZE_VP;
  @Prop heightValue: number = OVERLAY_PILL_HEIGHT_VP;
  @Prop radiusValue: number = OVERLAY_PILL_HEIGHT_VP / 2;
  @Prop blockHit: boolean = false;
  @BuilderParam label: () => void;
  onBarClick: () => void = () => {};
  enableBarClick: boolean = false;

  @Builder
  private chromeBar() {
    Row()
      .width('100%')
      .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      HdsTabs({ index: 0 }) {
        TabContent() {
          Column()
            .width('100%')
            .height('100%')
        }
        .tabBar(this.chromeBar)
      }
      .width(this.widthValue)
      .height(this.heightValue)
      .barHeight(this.heightValue)
      .barOverlap(true)
      .vertical(false)
      .barPosition(BarPosition.End)
      .barWidth(this.widthValue)
      // @SuppressWarnings compatibility
      .barFloatingStyle(fnHdsImmersiveTabsFloatingStyle(
        this.heightValue,
        this.widthValue,
        $r('app.color.gallery_material_surface_bg')
      ))
      .scrollable(false)
      .divider({ mode: DividerMode.NONE })
      .barBackgroundColor(Color.Transparent)
      .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: this.heightValue })
      .blurStrategy(BlurStrategy.ADAPTIVE)
      .borderRadius(this.radiusValue)
      .clip(true)
      .hitTestBehavior(HitTestMode.None)
      .onContentWillChange((_currentIndex: number, _comingIndex: number): boolean => {
        return false;
      })

      Row() {
        this.label()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(this.blockHit ? HitTestMode.None : HitTestMode.Default)
      .onClick((): void => {
        if (this.enableBarClick) {
          this.onBarClick();
        }
      })
    }
    .width(this.widthValue)
    .height(this.heightValue)
    .borderRadius(this.radiusValue)
    .clip(true)
    .hitTestBehavior(this.blockHit ? HitTestMode.None : HitTestMode.Default)
  }
}

@Component
export struct GalleryVideoOverlayChrome {
  @Prop visible: boolean = true;
  @Prop showCenterPlay: boolean = true;
  @Prop landscape: boolean = false;
  @Prop speedText: string = '1.0X';
  @Prop speedRate: number = 1.0;
  @Prop currentText: string = '00:00';
  @Prop durationText: string = '00:00';
  @Prop progress: number = 0;
  @Prop bottomPadding: number = 0;
  onPlay: () => void = () => {};
  onSelectSpeed: (rate: number) => void = (_rate: number) => {};
  onQuality: () => void = () => {};
  onFullscreen: () => void = () => {};
  onInteract: () => void = () => {};
  onSeekStart: () => void = () => {};
  onSeekRatio: (ratio: number) => void = (_: number) => {};
  onSeekEnd: () => void = () => {};
  onSeekCancel: () => void = () => {};
  onSeekTapRatio: (ratio: number) => void = (_: number) => {};
  onSingleTap: () => void = () => {};
  onDoubleTap: () => void = () => {};
  onHoldSpeedStart: () => void = () => {};
  onHoldSpeedEnd: () => void = () => {};
  onVerticalAdjustStart: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onVerticalAdjustUpdate: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onVerticalAdjustEnd: () => void = () => {};

  @State private barW: number = 1;
  @State private speedMenuOpen: boolean = false;
  private dragStartRatio: number = 0;

  private fillPercent(): number {
    return Math.round(Math.max(0, Math.min(1, this.progress)) * 100);
  }

  private isCurrentSpeed(rate: number): boolean {
    return Math.abs(this.speedRate - rate) < 0.01;
  }

  private fullscreenSymbol(): Resource {
    return this.landscape ? $r('sys.symbol.exit_full_screen') : $r('sys.symbol.full_screen');
  }

  private speedCheckIcon(rate: number): SymbolGlyphModifier {
    const color: ResourceColor = this.isCurrentSpeed(rate) ?
      $r('app.color.icon_primary') : Color.Transparent;
    return new SymbolGlyphModifier($r('sys.symbol.checkmark'))
      .fontSize(18)
      .fontColor([color]);
  }

  @Builder
  private speedMenu() {
    Menu() {
      ForEach(GALLERY_VIDEO_SPEED_OPTIONS, (opt: GalleryVideoSpeedOption) => {
        MenuItem({
          content: opt.label,
          symbolEndIcon: this.speedCheckIcon(opt.rate)
        })
          .onClick((): void => {
            this.speedMenuOpen = false;
            this.onSelectSpeed(opt.rate);
          })
      }, (opt: GalleryVideoSpeedOption) => `${opt.rate}`)
    }
    .radius(22)
    .menuItemDivider({
      strokeWidth: LengthMetrics.vp(0.5),
      color: '#1A000000',
      startMargin: LengthMetrics.vp(12),
      endMargin: LengthMetrics.vp(12)
    })
  }

  @Builder
  private speedLabel() {
    Text(this.speedText)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.icon_primary'))
      .textAlign(TextAlign.Center)
      .width('100%')
      .height('100%')
  }

  @Builder
  private timeLabel() {
    Text(`${this.currentText} | ${this.durationText}`)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.icon_primary'))
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .width('100%')
      .height('100%')
  }

  @Builder
  private landscapeLabel() {
    SymbolGlyph(this.fullscreenSymbol())
      .fontSize(18)
      .fontColor([$r('app.color.icon_primary')])
      .width(18)
      .height(18)
  }

  @Builder
  private playLabel() {
    SymbolGlyph($r('sys.symbol.play_fill'))
      .fontSize(30)
      .fontColor([$r('app.color.icon_primary')])
      .width(30)
      .height(30)
  }

  build() {
    Stack() {
      if (this.visible && this.showCenterPlay) {
        Stack({ alignContent: Alignment.Center }) {
          GalleryOverlayHdsCapsule({
            widthValue: OVERLAY_PLAY_SIZE_VP,
            heightValue: OVERLAY_PLAY_SIZE_VP,
            radiusValue: OVERLAY_PLAY_SIZE_VP / 2,
            enableBarClick: true,
            onBarClick: (): void => {
              this.onPlay();
            },
            label: (): void => {
              this.playLabel();
            }
          })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      if (this.visible) {
        Stack({ alignContent: Alignment.Bottom }) {
          Column({ space: 10 }) {
            Stack({ alignContent: Alignment.Center }) {
            Row() {
              GalleryOverlayHdsCapsule({
                widthValue: OVERLAY_SPEED_WIDTH_VP,
                heightValue: OVERLAY_PILL_HEIGHT_VP,
                radiusValue: OVERLAY_PILL_HEIGHT_VP / 2,
                enableBarClick: true,
                onBarClick: (): void => {
                  this.onInteract();
                  this.speedMenuOpen = true;
                },
                label: (): void => {
                  this.speedLabel();
                }
              })
                .bindMenu(this.speedMenuOpen, this.speedMenu, {
                  placement: Placement.TopLeft,
                  onDisappear: (): void => {
                    this.speedMenuOpen = false;
                  }
                })
                .gesture(
                  LongPressGesture({ repeat: false })
                    .onAction((): void => {
                      this.onQuality();
                    })
                )

              Blank()
                .layoutWeight(1)
                .hitTestBehavior(HitTestMode.None)

              GalleryOverlayHdsCapsule({
                widthValue: OVERLAY_LANDSCAPE_SIZE_VP,
                heightValue: OVERLAY_LANDSCAPE_SIZE_VP,
                radiusValue: OVERLAY_LANDSCAPE_SIZE_VP / 2,
                enableBarClick: true,
                onBarClick: (): void => {
                  this.onInteract();
                  this.onFullscreen();
                },
                label: (): void => {
                  this.landscapeLabel();
                }
              })
            }
            .width('100%')
            .height(OVERLAY_PILL_HEIGHT_VP)
            .alignItems(VerticalAlign.Center)

            GalleryOverlayHdsCapsule({
              widthValue: OVERLAY_TIME_WIDTH_VP,
              heightValue: OVERLAY_PILL_HEIGHT_VP,
              radiusValue: OVERLAY_PILL_HEIGHT_VP / 2,
              blockHit: true,
              label: (): void => {
                this.timeLabel();
              }
            })
          }
          .width('100%')
          .height(OVERLAY_PILL_HEIGHT_VP)

          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width('100%')
              .height(3)
              .backgroundColor($r('app.color.immersive_panel_border'))
              .borderRadius(2)
            Row()
              .width(`${this.fillPercent()}%`)
              .height(3)
              .backgroundColor($r('app.color.brand_primary'))
              .borderRadius(2)
          }
          .width('100%')
          .height(22)
          .onAreaChange((_old, area): void => {
            const w = area.width as number;
            this.barW = w > 1 ? w : 1;
          })
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionStart((): void => {
                this.dragStartRatio = this.progress;
                this.onSeekStart();
              })
              .onActionUpdate((ev: GestureEvent): void => {
                const r = this.dragStartRatio + (this.barW > 0 ? ev.offsetX / this.barW : 0);
                this.onSeekRatio(Math.max(0, Math.min(1, r)));
              })
              .onActionEnd((): void => {
                this.onSeekEnd();
              })
              .onActionCancel((): void => {
                this.onSeekCancel();
              })
          )
          .onTouch((ev: TouchEvent): void => {
            if (ev.type !== TouchType.Up) {
              return;
            }
            const ts = ev.touches;
            if (ts === undefined || ts.length < 1) {
              return;
            }
            this.onSeekTapRatio(Math.max(0, Math.min(1, ts[0].x / this.barW)));
          })
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          bottom: 8 + this.bottomPadding
        })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Default)
    .onGestureJudgeBegin((info: GestureInfo, event: BaseGestureEvent): GestureJudgeResult => {
      if (info.type !== GestureControl.GestureType.PAN_GESTURE) {
        return GestureJudgeResult.CONTINUE;
      }
      const pan = event as PanGestureEvent;
      if (Math.abs(pan.offsetX) > Math.abs(pan.offsetY)) {
        return GestureJudgeResult.REJECT;
      }
      return GestureJudgeResult.CONTINUE;
    })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ direction: PanDirection.Vertical, distance: 16 })
          .onActionStart((event: GestureEvent): void => {
            this.onVerticalAdjustStart(event);
          })
          .onActionUpdate((event: GestureEvent): void => {
            this.onVerticalAdjustUpdate(event);
          })
          .onActionEnd((): void => {
            this.onVerticalAdjustEnd();
          })
          .onActionCancel((): void => {
            this.onVerticalAdjustEnd();
          }),
        LongPressGesture({ repeat: false })
          .onAction((): void => {
            this.onHoldSpeedStart();
          })
          .onActionEnd((): void => {
            this.onHoldSpeedEnd();
          })
          .onActionCancel((): void => {
            this.onHoldSpeedEnd();
          }),
        TapGesture({ count: 2 })
          .onAction((): void => {
            this.onDoubleTap();
          }),
        TapGesture({ count: 1 })
          .onAction((): void => {
            this.onSingleTap();
          })
      )
    )
  }
}
