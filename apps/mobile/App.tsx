import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { SafeAreaView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';

import { HealthScreen } from './src/screens/HealthScreen';
import { SelfTestScreen } from './src/screens/SelfTestScreen';
import { ScanScreen } from './src/scan/ScanScreen';

type Tab = 'health' | 'selftest' | 'scan';

export default function App() {
  const [tab, setTab] = useState<Tab>('health');

  return (
    <SafeAreaView style={styles.screen}>
      <StatusBar style="auto" />
      <Text style={styles.title}>Farmable</Text>
      <View style={styles.tabs}>
        <TouchableOpacity testID="tab-health" style={styles.tab} onPress={() => setTab('health')}>
          <Text style={tab === 'health' ? styles.tabLabelActive : styles.tabLabel}>Health</Text>
        </TouchableOpacity>
        <TouchableOpacity
          testID="tab-selftest"
          style={styles.tab}
          onPress={() => setTab('selftest')}
        >
          <Text style={tab === 'selftest' ? styles.tabLabelActive : styles.tabLabel}>
            Self-test
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          testID="tab-scan"
          accessibilityRole="button"
          accessibilityLabel="Scan crops"
          accessibilityState={{ selected: tab === 'scan' }}
          style={styles.tab}
          onPress={() => setTab('scan')}
        >
          <Text style={tab === 'scan' ? styles.tabLabelActive : styles.tabLabel}>Scan</Text>
        </TouchableOpacity>
      </View>
      {tab === 'health' ? (
        <HealthScreen />
      ) : tab === 'selftest' ? (
        <SelfTestScreen />
      ) : (
        <ScanScreen />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#fff' },
  title: { fontSize: 28, fontWeight: '700', paddingHorizontal: 24, paddingTop: 16 },
  tabs: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    paddingHorizontal: 24,
    paddingVertical: 12,
  },
  tab: {
    minHeight: 48,
    minWidth: 48,
    borderColor: '#1f6f43',
    borderRadius: 8,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  tabLabel: { color: '#1f6f43', fontSize: 15 },
  tabLabelActive: { color: '#1f6f43', fontSize: 15, fontWeight: '700' },
});
