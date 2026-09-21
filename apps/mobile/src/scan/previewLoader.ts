/** Kept separate so tests replace the native-loading boundary, not scan logic. */
export async function loadPreview() {
  return { default: (await import('./LiveCamera')).LiveCamera };
}
