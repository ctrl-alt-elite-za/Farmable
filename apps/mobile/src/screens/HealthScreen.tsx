import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { fetchApiHealth, type ApiHealth, type FetchLike } from '../api/health';
import { API_URL } from '../config';

type Displayed = ApiHealth | 'checking';

const LABELS: Record<Displayed, string> = {
  checking: 'Checking...',
  online: 'Online',
  offline: 'Offline',
};

export interface HealthScreenProps {
  apiUrl?: string;
  fetchImpl?: FetchLike;
}

export function HealthScreen({ apiUrl = API_URL, fetchImpl }: HealthScreenProps) {
  const [status, setStatus] = useState<Displayed>('checking');

  useEffect(() => {
    let cancelled = false;
    void fetchApiHealth({ apiUrl, fetchImpl }).then((next) => {
      if (!cancelled) {
        setStatus(next);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [apiUrl, fetchImpl]);

  return (
    <View style={styles.container}>
      <Text style={styles.heading}>API health</Text>
      <Text testID="api-url" style={styles.detail}>
        {apiUrl}
      </Text>
      <Text testID="api-status" style={styles.status}>
        {LABELS[status]}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { gap: 8, padding: 24 },
  heading: { fontSize: 20, fontWeight: '600' },
  detail: { color: '#555', fontSize: 14 },
  status: { fontSize: 32, fontWeight: '700' },
});
