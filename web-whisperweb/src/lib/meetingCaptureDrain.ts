/** Retains final speech work from replaced/paused captures until meeting finalization. */
export class MeetingCaptureDrain {
  private readonly pending = new Set<Promise<void>>();
  retire(capture: { stop: () => Promise<void> }): void {
    const work = capture.stop();
    this.pending.add(work);
    void work.finally(() => this.pending.delete(work)).catch(() => undefined);
  }
  /** A UI deadline does not cancel account-bound background work. */
  async finishWithin(milliseconds: number): Promise<boolean> {
    let timer: ReturnType<typeof setTimeout> | undefined;
    try { return await Promise.race([this.finish().then(() => true), new Promise<boolean>((resolve) => { timer = setTimeout(() => resolve(false), milliseconds); })]); }
    finally { clearTimeout(timer); }
  }
  async finish(): Promise<void> {
    while (this.pending.size) await Promise.allSettled([...this.pending]);
  }
}
