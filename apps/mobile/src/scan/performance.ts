export function measureOverlayFps(durationMs = 1000): Promise<number> {
  return new Promise((resolve) => {
    const started = performance.now();
    let frames = 0;
    const tick = (now: number) => {
      frames += 1;
      if (now - started >= durationMs) {
        resolve(Math.round((frames * 1000) / Math.max(1, now - started)));
        return;
      }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  });
}
