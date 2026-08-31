/**
 * 官方图库风格视频浮层。
 * 倍速 / 清晰度走系统 bindMenu、bindContextMenu，不要自绘半模态。
 * 视频手势与控件分层，避免父级单击/长按抢走菜单。
 */
import { BlurStrategy, DividerMode, HdsTabs } from '@kit.UIDesignKit';
import {
  fnHdsBindContextMenuOptions,
  fnHdsBindMenuOptions,
  fnHdsMenuSystemMaterial
} from '../common/FnHdsOverlay';
import { fnHdsImmersiveTabsFloatingStyle } from '../common/FnUiCommon';
import {
  FN_SYSTEM_LEFT_INSET_VP_KEY,
  FN_SYSTEM_RIGHT_INSET_VP_KEY
} from '../common/FnSystemAvoidArea';
import { galleryIsVideoBrightnessVolumeZone } from './GalleryPreviewVerticalGesture';
import { playGalleryLongPressMenuHaptic } from './GallerySelectionHaptic';

const OVERLAY_PILL_HEIGHT_VP: number = 36;
const OVERLAY_SPEED_WIDTH_VP: number = 60;
const OVERLAY_LANDSCAPE_SIZE_VP: number = 36;
const OVERLAY_PLAY_SIZE_VP: number = 72;
const OVERLAY_SIDE_PAD_VP: number = 16;
/** 横屏左右边距约 70vp，躲开挖孔摄像头 */
const OVERLAY_LANDSCAPE_SIDE_EXTRA_VP: number = 54;

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
  @Prop qualityLabels: string[] = ['原始', '高清 1080p', '均衡 720p', '流畅 480p'];
  @Prop qualityIndex: number = 0;
  @Prop currentText: string = '00:00';
  @Prop durationText: string = '00:00';
  @Prop progress: number = 0;
  @Prop bottomPadding: number = 0;
  onPlay: () => void = () => {};
  onSelectSpeed: (rate: number) => void = (_rate: number) => {};
  onSelectQuality: (index: number) => void = (_index: number) => {};
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
  @State private overlayW: number = 360;
  @State private overlayH: number = 780;
  /** 官方 bindContextMenu(isShown)：长按由按钮自己触发，避免被全屏按住倍速抢走 */
  @State private qualityMenuVisible: boolean = false;
  @StorageProp(FN_SYSTEM_LEFT_INSET_VP_KEY) private systemLeftInsetVp: number = 0;
  @StorageProp(FN_SYSTEM_RIGHT_INSET_VP_KEY) private systemRightInsetVp: number = 0;
  private dragStartRatio: number = 0;

  private isBrightnessVolumeZone(localX: number, localY: number): boolean {
    return galleryIsVideoBrightnessVolumeZone(localX, localY, this.overlayW, this.overlayH);
  }

  private fillPercent(): number {
    return Math.round(Math.max(0, Math.min(1, this.progress)) * 100);
  }

  private isCurrentSpeed(rate: number): boolean {
    return Math.abs(this.speedRate - rate) < 0.01;
  }

  private fullscreenSymbol(): Resource {
    return this.landscape ? $r('sys.symbol.exit_full_screen') : $r('sys.symbol.full_screen');
  }

  private overlaySidePad(insetVp: number): number {
    if (!this.landscape) {
      return OVERLAY_SIDE_PAD_VP;
    }
    return Math.max(OVERLAY_SIDE_PAD_VP + OVERLAY_LANDSCAPE_SIDE_EXTRA_VP, insetVp + 16);
  }

  @Builder
  private speedMenu() {
    Menu() {
      MenuItem({ content: '0.25X' })
        .selected(this.isCurrentSpeed(0.25))
        .onClick((): void => {
          this.onSelectSpeed(0.25);
        })
      MenuItem({ content: '0.5X' })
        .selected(this.isCurrentSpeed(0.5))
        .onClick((): void => {
          this.onSelectSpeed(0.5);
        })
      MenuItem({ content: '1.0X' })
        .selected(this.isCurrentSpeed(1.0))
        .onClick((): void => {
          this.onSelectSpeed(1.0);
        })
      MenuItem({ content: '1.5X' })
        .selected(this.isCurrentSpeed(1.5))
        .onClick((): void => {
          this.onSelectSpeed(1.5);
        })
      MenuItem({ content: '2.0X' })
        .selected(this.isCurrentSpeed(2.0))
        .onClick((): void => {
          this.onSelectSpeed(2.0);
        })
    }
    .backgroundColor($r('app.color.gallery_menu_backdrop'))
    .backgroundBlurStyle(BlurStyle.NONE)
    // @SuppressWarnings compatibility
    .systemMaterial(fnHdsMenuSystemMaterial())
  }

  @Builder
  private qualityMenu() {
    Menu() {
      ForEach(this.qualityLabels, (label: string, idx: number) => {
        MenuItem({ content: label })
          .selected(idx === this.qualityIndex)
          .onClick((): void => {
            this.qualityMenuVisible = false;
            this.onSelectQuality(idx);
          })
      }, (label: string, idx: number) => `q_${idx}_${label}`)
    }
    .backgroundColor($r('app.color.gallery_menu_backdrop'))
    .backgroundBlurStyle(BlurStyle.NONE)
    // @SuppressWarnings compatibility
    .systemMaterial(fnHdsMenuSystemMaterial())
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
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.icon_primary'))
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .width('100%')
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

  @Builder
  private videoGestureLayer() {
    Column()
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Default)
      .onAreaChange((_old, area): void => {
        const w = area.width as number;
        const h = area.height as number;
        if (w > 1) {
          this.overlayW = w;
        }
        if (h > 1) {
          this.overlayH = h;
        }
      })
      .onGestureJudgeBegin((info: GestureInfo, event: BaseGestureEvent): GestureJudgeResult => {
        if (info.type === GestureControl.GestureType.LONG_PRESS_GESTURE) {
          const lp = event as BaseGestureEvent;
          const fingers = lp.fingerList;
          if (fingers !== undefined && fingers.length > 0 && this.visible) {
            // 底栏控件区（倍速/进度）不走全屏按住倍速，把长按留给清晰度菜单
            const y = fingers[0].localY;
            if (y > this.overlayH - 120 - this.bottomPadding) {
              return GestureJudgeResult.REJECT;
            }
          }
        }
        if (info.type !== GestureControl.GestureType.PAN_GESTURE) {
          return GestureJudgeResult.CONTINUE;
        }
        const pan = event as PanGestureEvent;
        if (Math.abs(pan.offsetX) > Math.abs(pan.offsetY)) {
          return GestureJudgeResult.REJECT;
        }
        const fingers = pan.fingerList;
        if (fingers !== undefined && fingers.length > 0 &&
          !this.isBrightnessVolumeZone(fingers[0].localX, fingers[0].localY)) {
          return GestureJudgeResult.REJECT;
        }
        return GestureJudgeResult.CONTINUE;
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ direction: PanDirection.Vertical, distance: 8 })
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
              playGalleryLongPressMenuHaptic();
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

  build() {
    Stack() {
      this.videoGestureLayer()

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
          Row() {
            Stack() {
              GalleryOverlayHdsCapsule({
                widthValue: OVERLAY_SPEED_WIDTH_VP,
                heightValue: OVERLAY_PILL_HEIGHT_VP,
                radiusValue: OVERLAY_PILL_HEIGHT_VP / 2,
                blockHit: true,
                enableBarClick: false,
                label: (): void => {
                  this.speedLabel();
                }
              })
            }
            .width(OVERLAY_SPEED_WIDTH_VP)
            .height(OVERLAY_PILL_HEIGHT_VP)
            .backgroundColor(Color.Transparent)
            .draggable(false)
            .hitTestBehavior(HitTestMode.Default)
            .priorityGesture(
              LongPressGesture({ repeat: false })
                .onAction((): void => {
                  this.onInteract();
                  playGalleryLongPressMenuHaptic();
                  this.qualityMenuVisible = true;
                })
            )
            .bindMenu(this.speedMenu, fnHdsBindMenuOptions(
              Placement.TopLeft,
              (): void => {},
              (): void => {
                this.onInteract();
              }
            ))
            .bindContextMenu(this.qualityMenuVisible, this.qualityMenu, fnHdsBindContextMenuOptions(
              Placement.TopLeft,
              (): void => {
                this.onInteract();
              },
              (): void => {
                this.qualityMenuVisible = false;
              }
            ))

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

          Column({ space: 4 }) {
            this.timeLabel()
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
          }
          .width('100%')
          .padding({
            left: this.overlaySidePad(this.systemLeftInsetVp),
            right: this.overlaySidePad(this.systemRightInsetVp),
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
  }
}
