import { BOTH_MODES_MESSAGE } from '../../testmode/source';
import { ScanScreen } from '../ScanScreen';

jest.mock('../../config', () => ({ DEMO_MODE: true, TEST_MODE: true }));
jest.mock('../LiveCamera', () => ({ LiveCamera: () => null }));
jest.mock('../overlay', () => ({ CropOverlay: () => null }));

test('a demo build refuses recorded test detections before mounting a scan', () => {
  // The build guard must throw before any React hooks or native resources exist.
  expect(() => ScanScreen()).toThrow(BOTH_MODES_MESSAGE);
});
