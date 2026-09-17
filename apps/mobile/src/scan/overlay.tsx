import { Canvas, Rect } from '@shopify/react-native-skia';
import { StyleSheet, Text, View } from 'react-native';
import type { Track } from './types';

interface Props {
  tracks: readonly Track[];
  width: number;
  height: number;
}

export function CropOverlay({ tracks, width, height }: Props) {
  return (
    <View pointerEvents="box-none" style={StyleSheet.absoluteFill} testID="crop-overlay">
      <Canvas style={StyleSheet.absoluteFill}>
        {tracks.map((track) => {
          const { x, y, width: boxWidth, height: boxHeight } = track.box;
          return (
            <Rect
              key={track.id}
              x={x * width}
              y={y * height}
              width={boxWidth * width}
              height={boxHeight * height}
              color={track.label === 'check_suggested' ? '#f28c28' : '#f5f5f5'}
              style="stroke"
              strokeWidth={3}
            />
          );
        })}
      </Canvas>
      {tracks
        .filter((track) => track.label === 'check_suggested')
        .map((track) => (
          <View
            key={`warning-${track.id}`}
            testID="check-suggested-warning"
            style={[
              styles.warning,
              { left: track.box.x * width - 12, top: track.box.y * height - 12 },
            ]}
          >
            <Text style={styles.warningText}>⚠</Text>
          </View>
        ))}
    </View>
  );
}

const styles = StyleSheet.create({
  warning: {
    position: 'absolute',
    minWidth: 24,
    minHeight: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },
  warningText: { color: '#f28c28', fontSize: 20, fontWeight: '700' },
});
