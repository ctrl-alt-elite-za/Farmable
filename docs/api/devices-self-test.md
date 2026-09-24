# `/devices/self-test`

The Self-test screen in `apps/mobile` runs the checks that only work on a real phone
and posts the result here, so an agent can read from the server what a person saw on
a device (issue #4).

**The Flutter client builds this report** (`SelfTestReport.toJson` in
`apps/mobile/lib/domain/device/self_test.dart`) and keeps it on the phone.
**It does not upload yet: the server side is not implemented** — that is backend
issue #11. When #11 lands, the upload is a POST of that JSON; nothing about the
report needs to change.

## POST /devices/self-test

No authentication. The request carries no credential; the report is the whole body.

```json
{
  "platform": "ios",
  "app_version": "0.1.0",
  "build_sha": "abc1234",
  "device_model": "iPhone 12 Pro",
  "detector_ms": 12,
  "started_at": "2026-09-17T08:00:00.000Z",
  "camera_preview": "pass",
  "lidar_depth": "pass",
  "ar_plane": "pass",
  "mic_record": "pass",
  "notes": [],
  "overall": "pass"
}
```

| Field                                                     | Type                                    |
| --------------------------------------------------------- | --------------------------------------- |
| `platform`                                                | `"ios"` or `"android"`                  |
| `app_version`, `build_sha`, `device_model`, `started_at`  | string (`started_at` is ISO-8601 UTC)   |
| `detector_ms`                                             | number, milliseconds; `null` if the detector did not run |
| `camera_preview`, `lidar_depth`, `ar_plane`, `mic_record` | `"pass"`, `"fail"` or `"unsupported"`   |
| `notes`                                                   | array of strings, one per non-pass item |
| `overall`                                                 | `"pass"` or `"fail"`                    |

Every entry in `notes` reads `"<field>: <why>"`, and the reason should name a GitHub
issue, e.g. `"lidar_depth: no depth camera reported (#31)"`.

Response: `201` with `{"stored": true}`. The client treats any non-2xx as a failed
upload and any network error as `{"uploaded": false, "status": 0}`; it never throws.

## GET /devices/self-test?build_sha=<sha>&platform=<ios|android>

Returns the most recent report stored for that build and platform, in exactly the
shape above, or `404` when no report has been uploaded yet.

## Why the server side is not here

`apps/backend/` is created wholesale by issue #3, which is in flight as PR #29 on a
branch of its own. Adding a second FastAPI application on this branch would duplicate
that work and conflict with it file for file. The contract above is frozen instead, so
the endpoint is a small addition on top of #3 rather than a new decision.
