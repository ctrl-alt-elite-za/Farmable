import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { SafeAreaView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';

import { HealthScreen } from './src/screens/HealthScreen';
import { SelfTestScreen } from './src/screens/SelfTestScreen';

type Tab = 'health' | 'selftest';

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
      </View>
      {tab === 'health' ? <HealthScreen /> : <SelfTestScreen />}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  title: { fontSize: 28, fontWeight: '700', paddingHorizontal: 24, paddingTop: 16 },
  tabs: { flexDirection: 'row', gap: 8, paddingHorizontal: 24, paddingVertical: 12 },
  tab: {
    borderColor: '#1f6f43',
    borderRadius: 8,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  tabLabel: { color: '#1f6f43', fontSize: 15 },
  tabLabelActive: { color: '#1f6f43', fontSize: 15, fontWeight: '700' },
});
