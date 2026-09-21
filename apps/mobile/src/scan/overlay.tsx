import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { Track } from './types';

export const TOUCH_TARGET = 48;
export function controlPosition(track: Track, width: number, height: number) {
  return {
    left: Math.max(0, Math.min(width - TOUCH_TARGET, track.box.x * width)),
    top: Math.max(0, Math.min(height - TOUCH_TARGET, track.box.y * height)),
  };
}

export function CropOverlay({
  tracks,
  width,
  height,
  onTrackPress,
  onControlFocus,
}: {
  tracks: readonly Track[];
  width: number;
  height: number;
  onTrackPress?: (track: Track) => void;
  onControlFocus?: () => void;
}) {
  if (
    !Number.isFinite(width) ||
    !Number.isFinite(height) ||
    width < TOUCH_TARGET ||
    height < TOUCH_TARGET
  )
    return null;
  return (
    <View pointerEvents="box-none" style={StyleSheet.absoluteFill} testID="crop-overlay">
      {tracks.map((track) => (
        <View key={track.id} pointerEvents="box-none" style={StyleSheet.absoluteFill}>
          <View
            pointerEvents="none"
            testID={`crop-box-${track.id}`}
            style={[
              styles.box,
              {
                left: track.box.x * width,
                top: track.box.y * height,
                width: track.box.width * width,
                height: track.box.height * height,
              },
            ]}
          />
          {onTrackPress && (
            <Pressable
              testID={`crop-select-${track.id}`}
              accessibilityRole="button"
              accessibilityLabel={`${track.label} crop ${track.id}, recorded fixture`}
              onPress={() => onTrackPress(track)}
              onFocus={onControlFocus}
              style={({ pressed }) => [
                styles.control,
                controlPosition(track, width, height),
                { opacity: pressed ? 0.7 : 1 },
              ]}
            >
              <Text style={styles.controlText}>{track.id}</Text>
            </Pressable>
          )}
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  box: { position: 'absolute', borderColor: '#fff', borderWidth: 3, borderRadius: 8 },
  control: {
    position: 'absolute',
    width: TOUCH_TARGET,
    height: TOUCH_TARGET,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 8,
  },
  controlText: { color: '#17251d', fontSize: 18, fontWeight: '700' },
});
