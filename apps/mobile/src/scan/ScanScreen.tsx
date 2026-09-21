import { Component, lazy, Suspense, useEffect, useRef, useState, type ReactNode } from 'react';
import {
  AccessibilityInfo,
  AppState,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import {
  currentBuildModeFlags,
  loadSimulatedFrames,
  resolveCameraSource,
} from '../testmode/source';
import { decodeDetections } from './decoder';
import { LatestFrameProcessor, type OwnedFrame } from './frameProcessor';
import { CropOverlay } from './overlay';
import { CropTracker } from './tracker';
import type { Track } from './types';
import { loadPreview } from './previewLoader';

class PreviewBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <Text style={styles.cameraText}>
        Camera preview unavailable in this build. Reopen Scan to retry.
      </Text>
    ) : (
      this.props.children
    );
  }
}
interface ReplayFrame extends OwnedFrame {
  detections: unknown;
}

export function ScanScreen() {
  // Refuse mixed build flags before any camera or fixture replay is created.
  const source = resolveCameraSource(currentBuildModeFlags);
  // Each visit can retry a failed native import. Loading it cannot break
  // startup, Health or Self-test, and TEST_MODE never mounts it.
  const [Preview] = useState(() => lazy(loadPreview));
  const [active, setActive] = useState(AppState.currentState === 'active');
  const [paused, setPaused] = useState(false);
  const [reducedMotion, setReducedMotion] = useState<boolean | null>(null);
  const submitFrame = useRef<(() => void) | undefined>(undefined);
  const sessionSequence = useRef(0);
  const [tracks, setTracks] = useState<Track[]>([]);
  const [selected, setSelected] = useState<Track>();
  const [error, setError] = useState(false);
  const [viewport, setViewport] = useState({ width: 0, height: 0 });
  const { height } = useWindowDimensions();

  useEffect(() => {
    let mounted = true;
    let motionEvent = false;
    const app = AppState.addEventListener('change', (state) => setActive(state === 'active'));
    const motion = AccessibilityInfo.addEventListener('reduceMotionChanged', (value) => {
      motionEvent = true;
      setReducedMotion(value);
    });
    void AccessibilityInfo.isReduceMotionEnabled()
      .then((value) => {
        if (mounted && !motionEvent) setReducedMotion(value);
      })
      .catch(() => {
        if (mounted && !motionEvent) setReducedMotion(true);
      });
    return () => {
      mounted = false;
      app.remove();
      motion.remove();
    };
  }, []);

  useEffect(() => {
    setTracks([]);
    setSelected(undefined);
    setError(false);
    if (source.kind !== 'simulated' || !active || reducedMotion === null) return;
    const tracker = new CropTracker();
    const fixtures = loadSimulatedFrames();
    const sessionId = ++sessionSequence.current;
    let sequence = 0;
    let index = 0;
    const runner = new LatestFrameProcessor<ReplayFrame, Track[]>(
      sessionId,
      async (frame) => tracker.update(decodeDetections(frame.detections)),
      (result) => {
        setTracks(result);
        setSelected(undefined);
      },
      () => {
        setError(true);
        setTracks([]);
      },
    );
    const submit = () => {
      const detections = fixtures[index % fixtures.length].detections;
      index++;
      runner.submit({
        sessionId,
        sequence: ++sequence,
        capturedAt: performance.now(),
        detections,
        dispose() {
          /* Fixtures own no native resource. */
        },
      });
    };
    submitFrame.current = submit;
    submit();
    return () => {
      submitFrame.current = undefined;
      runner.dispose();
    };
  }, [source.kind, active, reducedMotion]);

  useEffect(() => {
    if (source.kind !== 'simulated' || !active || paused || reducedMotion !== false) return;
    const timer = setInterval(() => submitFrame.current?.(), 100);
    return () => clearInterval(timer);
  }, [source.kind, active, paused, reducedMotion]);

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <Text style={styles.heading}>
        {source.kind === 'simulated' ? 'Recorded test scan' : 'Scan crops'}
      </Text>
      <Text style={styles.body}>
        {source.kind === 'simulated'
          ? 'Synthetic fixtures only — not live detections or a plant health assessment.'
          : 'Live detection unavailable: approved model and native adapter pending (#16/#18). Preview only.'}
      </Text>
      {source.kind === 'simulated' && (
        <View style={styles.controls}>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={paused ? 'Resume replay' : 'Pause replay'}
            accessibilityState={{ disabled: reducedMotion !== false }}
            disabled={reducedMotion !== false}
            onPress={() => setPaused((value) => !value)}
            style={({ pressed }) => [
              styles.button,
              { opacity: reducedMotion !== false ? 0.5 : pressed ? 0.7 : 1 },
            ]}
          >
            <Text style={styles.body}>
              {reducedMotion
                ? 'Reduced motion: replay paused'
                : paused
                  ? 'Resume replay'
                  : 'Pause replay'}
            </Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Next recorded frame"
            onPress={() => {
              setPaused(true);
              submitFrame.current?.();
            }}
            style={({ pressed }) => [styles.button, { opacity: pressed ? 0.7 : 1 }]}
          >
            <Text style={styles.body}>Next frame</Text>
          </Pressable>
        </View>
      )}
      <View
        style={[styles.camera, { height: Math.max(160, Math.min(480, height * 0.45)) }]}
        testID="scan-camera"
        onLayout={(event) => setViewport(event.nativeEvent.layout)}
      >
        {source.kind === 'device' && active && (
          <PreviewBoundary>
            <Suspense fallback={<Text style={styles.cameraText}>Opening preview…</Text>}>
              <Preview />
            </Suspense>
          </PreviewBoundary>
        )}
        {!active && <Text style={styles.cameraText}>Scan paused while app is inactive.</Text>}
        {active && (
          <CropOverlay
            tracks={tracks}
            width={viewport.width}
            height={viewport.height}
            onControlFocus={() => setPaused(true)}
            onTrackPress={(track) => {
              setPaused(true);
              setSelected(track);
            }}
          />
        )}
      </View>
      {selected && (
        <Text style={styles.body} accessibilityLiveRegion="polite">
          Recorded {selected.label} crop {selected.id}. Fixture confidence:{' '}
          {Math.round(selected.confidence * 100)}%.
        </Text>
      )}
      {error && (
        <Text style={styles.body} accessibilityRole="alert">
          Recorded scan failed. Reopen Scan to retry.
        </Text>
      )}
      <Text style={styles.body}>Frames stay on this phone while scanning.</Text>
      <Text style={styles.body}>
        Camera-to-visible-box latency: unmeasured. Native presentation and device verification are
        pending.
      </Text>
    </ScrollView>
  );
}
const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#fff' },
  content: { padding: 16, gap: 12 },
  heading: { fontSize: 22, fontWeight: '700', color: '#17251d' },
  body: { fontSize: 16, color: '#17251d' },
  camera: { backgroundColor: '#17251d', overflow: 'hidden' },
  cameraText: { color: '#fff', padding: 16, fontSize: 16 },
  controls: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  button: {
    minWidth: 48,
    minHeight: 48,
    borderWidth: 1,
    borderColor: '#1f6f43',
    borderRadius: 8,
    padding: 12,
    justifyContent: 'center',
  },
});
