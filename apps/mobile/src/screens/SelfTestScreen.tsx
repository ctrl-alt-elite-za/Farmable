import * as Device from 'expo-device';
import { useState } from 'react';
import { Platform, ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';

import { APP_VERSION, BUILD_SHA } from '../config';
import { measureDetectorMs, runDeviceProbes } from '../native/probes';
import { buildSelfTestReport, CHECK_IDS, type SelfTestReport } from '../selftest/report';
import { uploadSelfTestReport, type UploadResult } from '../selftest/upload';

type Phase = 'idle' | 'running' | 'done';

export function SelfTestScreen() {
  const [phase, setPhase] = useState<Phase>('idle');
  const [report, setReport] = useState<SelfTestReport | null>(null);
  const [upload, setUpload] = useState<UploadResult | null>(null);

  async function run(): Promise<void> {
    setPhase('running');
    setReport(null);
    setUpload(null);

    const startedAt = new Date().toISOString();
    const results = await runDeviceProbes();
    const detector = await measureDetectorMs();
    const next = buildSelfTestReport(results, {
      platform: Platform.OS === 'ios' ? 'ios' : 'android',
      appVersion: APP_VERSION,
      buildSha: BUILD_SHA,
      deviceModel: Device.modelName ?? 'unknown',
      detectorMs: detector.ms,
      detectorNote: detector.note,
      startedAt,
      scanOverlayNote: 'not measured: live detector and mounted-overlay benchmark pending (#18)',
    });

    setReport(next);
    setUpload(await uploadSelfTestReport(next));
    setPhase('done');
  }

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.heading}>Self-test</Text>
      <Text style={styles.detail}>
        {APP_VERSION} - build {BUILD_SHA}
      </Text>

      <TouchableOpacity
        testID="run-self-test"
        style={styles.button}
        disabled={phase === 'running'}
        onPress={() => void run()}
      >
        <Text style={styles.buttonLabel}>
          {phase === 'running' ? 'Running...' : 'Run self-test'}
        </Text>
      </TouchableOpacity>

      {report ? (
        <View style={styles.results}>
          {CHECK_IDS.map((id) => (
            <Text key={id} testID={`check-${id}`} style={styles.row}>
              {id}: {report[id]}
            </Text>
          ))}
          <Text testID="check-detector_ms" style={styles.row}>
            detector_ms: {report.detector_ms}
          </Text>
          <Text testID="self-test-overall" style={styles.row}>
            overall: {report.overall}
          </Text>
          {report.notes.map((note) => (
            <Text key={note} style={styles.note}>
              {note}
            </Text>
          ))}
          <Text testID="self-test-upload" style={styles.row}>
            uploaded: {upload?.uploaded ? `yes (${upload.status})` : `no (${upload?.status ?? 0})`}
          </Text>
        </View>
      ) : null}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { gap: 12, padding: 24 },
  heading: { fontSize: 20, fontWeight: '600' },
  detail: { color: '#555', fontSize: 14 },
  button: { backgroundColor: '#1f6f43', borderRadius: 8, padding: 14 },
  buttonLabel: { color: '#fff', fontSize: 16, fontWeight: '600', textAlign: 'center' },
  results: { gap: 6 },
  row: { fontSize: 16 },
  note: { color: '#8a3b12', fontSize: 14 },
});
