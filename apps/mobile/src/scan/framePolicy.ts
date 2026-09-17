/** Camera processors may drop work when busy; they must never queue stale frames. */
export class FrameSampler {
  private frame = 0;
  constructor(private readonly every = 2) {}
  shouldProcess(): boolean {
    this.frame += 1;
    return this.frame % this.every === 0;
  }
  reset(): void {
    this.frame = 0;
  }
}
