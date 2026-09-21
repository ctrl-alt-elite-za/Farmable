import { fireEvent, render } from '@testing-library/react-native';
import { StyleSheet } from 'react-native';
import { CropOverlay } from '../overlay';
import type { Track } from '../types';

const track: Track = {
  id: 1,
  missedFrames: 0,
  label: 'tomato',
  rawLabel: 'tomato fruit',
  confidence: 0.9,
  box: { x: 0.99, y: 0.99, width: 0.01, height: 0.01 },
};
test.each([
  [375, 200],
  [667, 160],
  [48, 48],
])('controls stay within %s by %s with 48-unit targets', async (width, height) => {
  const onTrackPress = jest.fn();
  const view = await render(
    <CropOverlay tracks={[track]} width={width} height={height} onTrackPress={onTrackPress} />,
  );
  const control = view.getByRole('button', { name: 'tomato crop 1, recorded fixture' });
  const style = StyleSheet.flatten(control.props.style);
  expect(style.width).toBe(48);
  expect(style.height).toBe(48);
  expect(style.left).toBeGreaterThanOrEqual(0);
  expect(style.top).toBeGreaterThanOrEqual(0);
  expect(style.left + 48).toBeLessThanOrEqual(width);
  expect(style.top + 48).toBeLessThanOrEqual(height);
  await fireEvent.press(control);
  expect(onTrackPress).toHaveBeenCalledWith(track);
});
test.each([
  [47, 200],
  [200, 0],
  [NaN, 200],
])('no clipped interactive targets for invalid viewport %s by %s', async (width, height) => {
  const view = await render(
    <CropOverlay tracks={[track]} width={width} height={height} onTrackPress={jest.fn()} />,
  );
  expect(view.queryByRole('button')).toBeNull();
});
test('no enabled-looking controls when no action is supplied', async () => {
  const view = await render(<CropOverlay tracks={[track]} width={375} height={200} />);
  expect(view.queryByRole('button')).toBeNull();
  expect(view.getByTestId('crop-box-1')).toBeTruthy();
});
