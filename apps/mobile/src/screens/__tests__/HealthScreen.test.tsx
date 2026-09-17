import { render, screen, waitFor } from '@testing-library/react-native';

import { HealthScreen } from '../HealthScreen';

describe('HealthScreen', () => {
  it('shows Offline when the API cannot be reached', async () => {
    const fetchImpl = jest.fn().mockRejectedValue(new Error('Network request failed'));

    await render(<HealthScreen apiUrl="http://api.test" fetchImpl={fetchImpl} />);

    await waitFor(() => {
      expect(screen.getByTestId('api-status')).toHaveTextContent('Offline');
    });
  });

  it('shows Online when the API answers', async () => {
    const fetchImpl = jest.fn().mockResolvedValue({ ok: true });

    await render(<HealthScreen apiUrl="http://api.test" fetchImpl={fetchImpl} />);

    await waitFor(() => {
      expect(screen.getByTestId('api-status')).toHaveTextContent('Online');
    });
  });
});
