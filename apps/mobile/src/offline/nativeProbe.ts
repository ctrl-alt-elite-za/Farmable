/** Web/default entry: do not pull native SQLite or fake persistence into web. */
export function installOfflineProbe(): void {
  // Metro selects nativeProbe.native.ts on Android/iOS.
}
