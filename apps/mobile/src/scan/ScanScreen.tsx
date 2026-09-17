import { useEffect, useMemo, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { DEMO_MODE } from '../config';
import {
  currentBuildModeFlags,
  loadSimulatedFrames,
  resolveCameraSource,
} from '../testmode/source';
import { CropOverlay } from './overlay';
import { CropTracker } from './tracker';
import type { Track } from './types';
import { createCropDetector } from './models';
import { LiveCamera } from './LiveCamera';
import { FrameSampler } from './framePolicy';

export function ScanScreen() {
  // Refuse invalid build flags before creating any camera or replaying fixtures.
  const source = resolveCameraSource(currentBuildModeFlags);
  const [tracks, setTracks] = useState<Track[]>([]);
  const [viewport, setViewport] = useState({ width: 1, height: 1 });
  const tracker = useMemo(() => new CropTracker(), []);
  const detector = useMemo(() => createCropDetector('crop-detector-1'), []);

  useEffect(() => {
    if (source.kind !== 'simulated') return;
    const frames = loadSimulatedFrames();
    const sampler = new FrameSampler();
    let recordedFrame = 0;
    const timer = setInterval(() => {
      // A real frame processor applies the same sampling policy on-device.
      if (sampler.shouldProcess()) {
        setTracks(
          tracker.update(detector.detect(frames[recordedFrame % frames.length].detections)),
        );
        recordedFrame += 1;
      }
    }, 33);
    return () => clearInterval(timer);
  }, [detector, source.kind, tracker]);

  return (
    <View style={styles.screen}>
      <View
        style={styles.camera}
        testID="scan-camera"
        onLayout={(event) => setViewport(event.nativeEvent.layout)}
      >
        {source.kind === 'device' && <LiveCamera />}
        {source.kind === 'simulated' ? (
          <Text style={styles.mode}>Test scan</Text>
        ) : (
          <Text style={styles.mode}>
            Live detection unavailable: detector model and adapter pending (#16/#18).
          </Text>
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
