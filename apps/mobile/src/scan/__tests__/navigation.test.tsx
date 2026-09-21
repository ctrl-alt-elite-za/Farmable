import { fireEvent, render } from '@testing-library/react-native';
import { Text as MockText } from 'react-native';
import App from '../../../App';
const mockUnmount = jest.fn();
jest.mock('../../screens/HealthScreen', () => ({
  HealthScreen: () => <MockText>Existing health</MockText>,
}));
jest.mock('../../screens/SelfTestScreen', () => ({
  SelfTestScreen: () => <MockText>Existing self-test</MockText>,
}));
jest.mock('../ScanScreen', () => ({
  ScanScreen: function ScanMock() {
    const React = jest.requireActual('react');
    React.useEffect(() => () => mockUnmount(), []);
    return <MockText>Scan addition</MockText>;
  },
}));
test('preserves health/self-test and unmounts scan when leaving its tab', async () => {
  const view = await render(<App />);
  expect(view.getByText('Existing health')).toBeTruthy();
  await fireEvent.press(view.getByTestId('tab-selftest'));
  expect(view.getByText('Existing self-test')).toBeTruthy();
  await fireEvent.press(view.getByTestId('tab-scan'));
  expect(view.getByText('Scan addition')).toBeTruthy();
  await fireEvent.press(view.getByTestId('tab-health'));
  expect(view.getByText('Existing health')).toBeTruthy();
  expect(mockUnmount).toHaveBeenCalledTimes(1);
});
