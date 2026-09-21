import { probeMicRecord } from '../probes';

const mockPermission = jest.fn(async () => ({ granted: true }));
const mockMode = jest.fn(async () => undefined);
const mockRecorder = {
  prepareToRecordAsync: jest.fn(async () => undefined),
  record: jest.fn(),
  stop: jest.fn(async () => undefined),
  uri: 'file:///synthetic-recording.m4a',
  isRecording: false,
  release: jest.fn(),
};
const mockPlayer = {
  isLoaded: true,
  playing: true,
  currentTime: 1,
  play: jest.fn(),
  remove: jest.fn(),
};
const mockConstructor = jest.fn(() => mockRecorder);
const mockCreatePlayer = jest.fn(() => mockPlayer);
const mockPreset = {
  extension: '.m4a',
  sampleRate: 44100,
  numberOfChannels: 2,
  bitRate: 128000,
  ios: { outputFormat: 'aac' },
  android: { outputFormat: 'mpeg4', audioEncoder: 'aac' },
};
jest.mock('expo-audio', () => ({
  requestRecordingPermissionsAsync: mockPermission,
  setAudioModeAsync: mockMode,
  AudioModule: { AudioRecorder: mockConstructor },
  RecordingPresets: { HIGH_QUALITY: mockPreset },
  createAudioPlayer: mockCreatePlayer,
}));
const loadAudio = async () => jest.requireMock<typeof import('expo-audio')>('expo-audio');

beforeEach(() => {
  jest.useFakeTimers();
  jest.clearAllMocks();
  mockPermission.mockResolvedValue({ granted: true });
  mockCreatePlayer.mockImplementation(() => mockPlayer);
  mockPlayer.isLoaded = true;
  mockPlayer.playing = true;
  mockPlayer.currentTime = 1;
});
afterEach(() => jest.useRealTimers());

it('records for three seconds, plays actual loaded audio, and releases both native objects', async () => {
  const result = probeMicRecord(loadAudio);
  await jest.advanceTimersByTimeAsync(6000);
  expect(await result).toEqual({ id: 'mic_record', status: 'pass' });
  expect(mockConstructor).toHaveBeenCalledWith(
    expect.objectContaining({ extension: '.m4a', outputFormat: expect.any(String) }),
  );
  expect(mockRecorder.prepareToRecordAsync).toHaveBeenCalledWith(mockPreset);
  expect(mockRecorder.record).toHaveBeenCalledTimes(1);
  expect(mockRecorder.stop).toHaveBeenCalledTimes(1);
  expect(mockPlayer.play).toHaveBeenCalledTimes(1);
  expect(mockPlayer.remove).toHaveBeenCalledTimes(1);
  expect(mockRecorder.release).toHaveBeenCalledTimes(1);
  expect(mockMode).toHaveBeenLastCalledWith({ allowsRecording: false });
});

it('refused recording permission cannot pass or start recording', async () => {
  mockPermission.mockResolvedValue({ granted: false });
  expect((await probeMicRecord(loadAudio)).status).toBe('fail');
  expect(mockConstructor).not.toHaveBeenCalled();
});

it.each(['load', 'play', 'throw'])('playback failure cleans resources: %s', async (failure) => {
  if (failure === 'load') mockPlayer.isLoaded = false;
  if (failure === 'play') {
    mockPlayer.playing = false;
    mockPlayer.currentTime = 0;
  }
  if (failure === 'throw')
    mockCreatePlayer.mockImplementation(() => {
      throw new Error('synthetic player error');
    });
  const result = probeMicRecord(loadAudio);
  await jest.advanceTimersByTimeAsync(10000);
  expect((await result).status).toBe('fail');
  expect(mockRecorder.release).toHaveBeenCalledTimes(1);
  if (failure !== 'throw') expect(mockPlayer.remove).toHaveBeenCalledTimes(1);
  expect(mockMode).toHaveBeenLastCalledWith({ allowsRecording: false });
});
