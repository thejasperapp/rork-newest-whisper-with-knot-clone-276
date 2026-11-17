/** Allowlisted layout only. Never reads chat, captions, Jasper, health cards or note text. */
export type MeetingStageCell = { id: string; x: number; y: number; w: number; h: number; fit: "contain" | "cover"; radius: number; avatarURL: string | null; avatarSize: number; focused: boolean; clip: { x: number; y: number; w: number; h: number } };
export type MeetingStageSnapshot = { width: number; height: number; background: string; cells: MeetingStageCell[] };

/** Read live tile bounds and clipping, including docks outside the centered main stage. */
export function readMeetingStage(root: HTMLElement | null): MeetingStageSnapshot | null {
  const stage = root?.querySelector<HTMLElement>("[data-recording-stage]");
  if (!root || !stage || !root.isConnected) return null;
  const rect = stage.getBoundingClientRect(), rootRect = root.getBoundingClientRect();
  const style = getComputedStyle(stage);
  const left = rect.left + (parseFloat(style.paddingLeft) || 0), top = rect.top + (parseFloat(style.paddingTop) || 0);
  const width = rect.width - (parseFloat(style.paddingLeft) || 0) - (parseFloat(style.paddingRight) || 0);
  const height = rect.height - (parseFloat(style.paddingTop) || 0) - (parseFloat(style.paddingBottom) || 0);
  if (width < 20 || height < 20) return null;
  for (let parent: HTMLElement | null = root; parent; parent = parent.parentElement) {
    const css = getComputedStyle(parent);
    if (css.display === "none" || css.visibility === "hidden" || css.opacity === "0") return null;
  }
  const cells: MeetingStageCell[] = [];
  let minX = left, maxX = left + width;
  for (const element of root.querySelectorAll<HTMLElement>("[data-recording-stage] [data-recording-peer], [data-recording-dock] [data-recording-peer]")) {
    const id = element.dataset.recordingPeer, box = element.getBoundingClientRect(), css = getComputedStyle(element);
    if (!id || box.width < 2 || box.height < 2 || css.visibility === "hidden" || css.display === "none" || css.opacity === "0") continue;
    const dock = !!element.closest("[data-recording-dock]");
    let x1 = Math.max(dock ? rootRect.left : left, box.left), y1 = Math.max(top, box.top);
    let x2 = Math.min(dock ? rootRect.right : left + width, box.right), y2 = Math.min(top + height, box.bottom);
    let hidden = false;
    for (let parent = element.parentElement; parent && parent !== root; parent = parent.parentElement) {
      const parentStyle = getComputedStyle(parent), bounds = parent.getBoundingClientRect();
      if (parentStyle.display === "none" || parentStyle.visibility === "hidden" || parentStyle.opacity === "0") { hidden = true; break; }
      if (/(auto|scroll|hidden|clip)/.test(parentStyle.overflowX)) { x1 = Math.max(x1, bounds.left); x2 = Math.min(x2, bounds.right); }
      if (/(auto|scroll|hidden|clip)/.test(parentStyle.overflowY)) { y1 = Math.max(y1, bounds.top); y2 = Math.min(y2, bounds.bottom); }
    }
    if (hidden || x2 <= x1 || y2 <= y1) continue;
    minX = Math.min(minX, x1); maxX = Math.max(maxX, x2);
    cells.push({ id, x: box.left, y: box.top - top, w: box.width, h: box.height, fit: element.dataset.recordingFit === "contain" ? "contain" : "cover", radius: parseFloat(css.borderTopLeftRadius) || 18, avatarURL: element.dataset.recordingAvatar || null, avatarSize: Number(element.dataset.recordingAvatarSize) || 68, focused: element.dataset.recordingFocused === "true", clip: { x: x1, y: y1 - top, w: x2 - x1, h: y2 - y1 } });
  }
  return { width: maxX - minX, height, background: getComputedStyle(root).backgroundColor || "#202124", cells: cells.map((cell) => ({ ...cell, x: cell.x - minX, clip: { ...cell.clip, x: cell.clip.x - minX } })) };
}

/** Present the local shared feed large, retaining only the other visible tiles and their framing. */
export function localShareStage(stage: MeetingStageSnapshot, peerId: string): MeetingStageSnapshot {
  const others = stage.cells.filter((cell) => cell.id !== peerId).slice(0, 24);
  const gap = 8, mainWidth = others.length ? stage.width * 0.72 - gap : stage.width;
  const scale = others.length ? (stage.width - mainWidth - gap) / stage.width : 1;
  const dx = mainWidth + gap, dy = (stage.height - stage.height * scale) / 2;
  const share: MeetingStageCell = { id: peerId, x: 0, y: 0, w: mainWidth, h: stage.height, fit: "contain", radius: 18, avatarURL: null, avatarSize: 68, focused: false, clip: { x: 0, y: 0, w: mainWidth, h: stage.height } };
  return { ...stage, cells: [share, ...others.map((cell) => ({ ...cell, x: dx + cell.x * scale, y: dy + cell.y * scale, w: cell.w * scale, h: cell.h * scale, radius: cell.radius * scale, avatarSize: cell.avatarSize * scale, clip: { x: dx + cell.clip.x * scale, y: dy + cell.clip.y * scale, w: cell.clip.w * scale, h: cell.clip.h * scale } }))] };
}
