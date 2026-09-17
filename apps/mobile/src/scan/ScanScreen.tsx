import { useEffect, useMemo, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { DEMO_MODE, TEST_MODE } from '../config';
import { loadSimulatedFrames } from '../testmode/source';
import { CropOverlay } from './overlay';
import { CropTracker } from './tracker';
import type { Track } from './types';
import { decodeDetections } from './decoder';

export function ScanScreen() {
  const [tracks, setTracks] = useState<Track[]>([]);
  const [viewport, setViewport] = useState({ width: 1, height: 1 });
  const tracker = useMemo(() => new CropTracker(), []);

  useEffect(() => {
    if (!TEST_MODE) return;
    const frames = loadSimulatedFrames();
    let frame = 0;
    const timer = setInterval(() => {
      // A real frame processor applies the same sampling policy on-device.
      if (frame % 2 === 0) {
        setTracks(tracker.update(decodeDetections(frames[frame % frames.length].detections)));
      }
      frame += 1;
    }, 33);
    return () => clearInterval(timer);
  }, [tracker]);

  return (
    <View style={styles.screen} onLayout={(event) => setViewport(event.nativeEvent.layout)}>
      <View style={styles.camera} testID="scan-camera">
        {TEST_MODE ? (
          <Text style={styles.mode}>Test scan</Text>
        ) : (
          <Text style={styles.mode}>Camera scan</Text>
        )}
        <CropOverlay tracks={tracks} width={viewport.width} height={viewport.height} />
      </View>
      {DEMO_MODE && <Text style={styles.privacy}>Frames stay on this phone while scanning.</Text>}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  camera: { flex: 1, minHeight: 420, backgroundColor: '#17251d' },
  mode: { color: '#fff', padding: 16, fontSize: 16 },
  privacy: { padding: 12, color: '#345' },
});
