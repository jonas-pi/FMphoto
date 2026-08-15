/**
 * 实况预览播放状态，对齐 MovingPhotoView 回调（AVPlayer 就绪/播放/停止）。
 *
 * Idle ──onPrepared──► Prepared ──onStart──► Playing
 * Playing ──onFinish/onStop/onPause──► Prepared
 * 任意态 ──onError/资源释放──► Idle
 *
 * 手势占用：Prepared 允许内置长按；Playing 时捏合需先 stopPlayback；
 * 放大后单指平移，未放大时把 Pan 让给 Swiper。
 */
export enum GalleryLivePlayState {
  Idle = 0,
  Prepared = 1,
  Playing = 2
}

export function galleryLiveIsPlaying(state: GalleryLivePlayState): boolean {
  return state === GalleryLivePlayState.Playing;
}
