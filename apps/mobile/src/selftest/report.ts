export type CheckId = 'camera_preview' | 'lidar_depth' | 'ar_plane' | 'mic_record';

export type CheckStatus = 'pass' | 'fail' | 'unsupported';

/** The four device checks, in the order the Self-test screen runs them. */
export const CHECK_IDS: readonly CheckId[] = [
  'camera_preview',
  'lidar_depth',
  'ar_plane',
  'mic_record',
];

/** Detector budget from issue #4's acceptance criteria. */
export const DETECTOR_MS_BUDGET = 20;

const MISSING_NOTE = 'no note recorded - add one naming the GitHub issue, e.g. #123';

export interface CheckResult {
  id: CheckId;
  status: CheckStatus;
  /** Why it did not pass. Name the GitHub issue, e.g. 'no depth camera (#31)'. */
  note?: string;
}

export interface SelfTestMeta {
  platform: 'ios' | 'android';
  appVersion: string;
  buildSha: string;
  deviceModel: string;
  detectorMs: number;
  /** Why the detector could not be measured, if it could not be (issue #16 note). */
  detectorNote?: string;
  startedAt: string;
  scanOverlayFps?: number;
  scanOverlayNote?: string;
}

/** Field names are snake_case because this object is the request body the server stores. */
export interface SelfTestReport {
  platform: 'ios' | 'android';
  app_version: string;
  build_sha: string;
  device_model: string;
  detector_ms: number;
  started_at: string;
  camera_preview: CheckStatus;
  lidar_depth: CheckStatus;
  ar_plane: CheckStatus;
  mic_record: CheckStatus;
  notes: string[];
  overall: 'pass' | 'fail';
  scan_overlay_fps?: number;
}

/**
 * A check with no result is a failure, not a silence: a probe that crashed before
 * reporting is exactly the case this screen exists to catch.
 */
export function buildSelfTestReport(results: CheckResult[], meta: SelfTestMeta): SelfTestReport {
  const statuses = {} as Record<CheckId, CheckStatus>;
  const notes: string[] = [];

  for (const id of CHECK_IDS) {
    const result = results.find((candidate) => candidate.id === id);
    if (!result) {
      statuses[id] = 'fail';
      notes.push(`${id}: not run`);
      continue;
    }
    statuses[id] = result.status;
    if (result.status !== 'pass') {
      notes.push(`${id}: ${result.note ?? MISSING_NOTE}`);
    }
  }

  if (meta.detectorNote) {
    notes.push(`detector_ms: ${meta.detectorNote}`);
  } else if (meta.detectorMs > DETECTOR_MS_BUDGET) {
    notes.push(`detector_ms: ${meta.detectorMs} ms is over the ${DETECTOR_MS_BUDGET} ms budget`);
  }

  if (meta.scanOverlayNote) {
    notes.push(`scan_overlay_fps: ${meta.scanOverlayNote}`);
  } else if (
    meta.scanOverlayFps !== undefined &&
    (!Number.isFinite(meta.scanOverlayFps) || meta.scanOverlayFps < 20)
  ) {
    notes.push('scan_overlay_fps: invalid or below the 20 fps budget (#18)');
  }

  const report: SelfTestReport = {
    platform: meta.platform,
    app_version: meta.appVersion,
    build_sha: meta.buildSha,
    device_model: meta.deviceModel,
    detector_ms: meta.detectorMs,
    started_at: meta.startedAt,
    camera_preview: statuses.camera_preview,
    lidar_depth: statuses.lidar_depth,
    ar_plane: statuses.ar_plane,
    mic_record: statuses.mic_record,
    notes,
    overall: notes.length === 0 ? 'pass' : 'fail',
  };
  if (
    meta.scanOverlayFps !== undefined &&
    Number.isFinite(meta.scanOverlayFps) &&
    meta.scanOverlayFps >= 0 &&
    !meta.scanOverlayNote
  )
    report.scan_overlay_fps = meta.scanOverlayFps;
  return report;
}
