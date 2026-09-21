import { LatestFrameProcessor, type OwnedFrame } from '../frameProcessor';

const tick = async () => {
  for (let i = 0; i < 8; i++) await Promise.resolve();
};
function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
const frame = (sequence: number, sessionId = 1) => ({
  sessionId,
  sequence,
  capturedAt: sequence,
  dispose: jest.fn(),
});

test('one in-flight frame and only the newest pending frame; all handles released once', async () => {
  const gate = deferred();
  const process = jest.fn(async (f: OwnedFrame) => {
    if (f.sequence === 7) await gate.promise;
    return f.sequence;
  });
  const result = jest.fn();
  const runner = new LatestFrameProcessor(1, process, result);
  const frames = [7, 8, 9, 10].map((id) => frame(id));
  frames.forEach((f) => runner.submit(f));
  expect(process.mock.calls.map(([f]) => f.sequence)).toEqual([7]);
  expect(frames[0].dispose).not.toHaveBeenCalled();
  expect(frames[1].dispose).toHaveBeenCalledTimes(1);
  expect(frames[2].dispose).toHaveBeenCalledTimes(1);
  gate.resolve();
  await tick();
  expect(process.mock.calls.map(([f]) => f.sequence)).toEqual([7, 10]);
  expect(result.mock.calls.map(([value]) => value)).toEqual([7, 10]);
  runner.dispose();
  frames.forEach((f) => expect(f.dispose).toHaveBeenCalledTimes(1));
});

test('disposal releases waiting/new frames, but waits to release active handle and drops late result', async () => {
  const gate = deferred();
  const result = jest.fn();
  const runner = new LatestFrameProcessor(1, async () => gate.promise, result);
  const a = frame(1),
    b = frame(2),
    c = frame(3);
  runner.submit(a);
  runner.submit(b);
  runner.dispose();
  runner.dispose();
  runner.submit(c);
  expect(a.dispose).not.toHaveBeenCalled();
  expect(b.dispose).toHaveBeenCalledTimes(1);
  expect(c.dispose).toHaveBeenCalledTimes(1);
  gate.resolve();
  await tick();
  expect(a.dispose).toHaveBeenCalledTimes(1);
  expect(result).not.toHaveBeenCalled();
});

test('background/resume fences late results without starting concurrent processing', async () => {
  const gate = deferred();
  const result = jest.fn();
  const process = jest.fn(async (f: OwnedFrame) => {
    if (f.sequence === 1) await gate.promise;
    return f.sequence;
  });
  const runner = new LatestFrameProcessor(1, process, result);
  const a = frame(1),
    b = frame(2),
    c = frame(3),
    d = frame(4);
  runner.submit(a);
  runner.submit(b);
  runner.setActive(false);
  runner.submit(c);
  runner.setActive(true);
  runner.submit(d);
  expect(process).toHaveBeenCalledTimes(1);
  gate.resolve();
  await tick();
  expect(result.mock.calls.map(([value]) => value)).toEqual([4]);
  [a, b, c, d].forEach((f) => expect(f.dispose).toHaveBeenCalledTimes(1));
});

test('processing, observer and release errors cannot wedge the queue or escape', async () => {
  const error = jest.fn(() => {
    throw new Error('observer failed');
  });
  const seen: number[] = [];
  const runner = new LatestFrameProcessor(
    1,
    async (f: OwnedFrame) => {
      seen.push(f.sequence);
      if (f.sequence === 1) throw new Error('inference failed');
      return f.sequence;
    },
    () => {
      throw new Error('result failed');
    },
    error,
  );
  const a = frame(1),
    b = frame(2);
  a.dispose.mockImplementation(() => {
    throw new Error('release failed');
  });
  runner.submit(a);
  runner.submit(b);
  await tick();
  expect(seen).toEqual([1, 2]);
  expect(error).toHaveBeenCalledTimes(3);
  expect(a.dispose).toHaveBeenCalledTimes(1);
  expect(b.dispose).toHaveBeenCalledTimes(1);
});

test('rejects wrong sessions, stale identities, invalid timestamps, and duplicate ownership', async () => {
  const process = jest.fn(async () => undefined);
  const runner = new LatestFrameProcessor(1, process, jest.fn());
  const a = frame(2),
    stale = frame(1),
    wrong = frame(3, 2),
    invalid = frame(4);
  invalid.capturedAt = NaN;
  runner.submit(a);
  runner.submit(a);
  runner.submit(stale);
  runner.submit(wrong);
  runner.submit(invalid);
  await tick();
  expect(process).toHaveBeenCalledTimes(1);
  [a, stale, wrong, invalid].forEach((f) => expect(f.dispose).toHaveBeenCalledTimes(1));
});

test.each(['dispose', 'background'] as const)(
  'late failures after %s do not notify the old UI',
  async (event) => {
    let reject!: (reason: Error) => void;
    const failure = new Promise<void>((_resolve, fail) => {
      reject = fail;
    });
    const error = jest.fn();
    const result = jest.fn();
    const runner = new LatestFrameProcessor(1, async () => failure, result, error);
    const handle = frame(1);
    handle.dispose.mockImplementation(() => {
      throw new Error('late release failure');
    });
    runner.submit(handle);
    if (event === 'dispose') runner.dispose();
    else {
      runner.setActive(false);
      runner.setActive(true);
    }
    reject(new Error('late native failure'));
    await tick();
    expect(error).not.toHaveBeenCalled();
    expect(result).not.toHaveBeenCalled();
    expect(handle.dispose).toHaveBeenCalledTimes(1);
  },
);
