# Installing Farmable on the test phones

The app uses the camera, LiDAR depth, AR planes, the microphone and an on-device
detector. None of that can be proved on an emulator, so the only way to test those
features is a release build on a real phone (issue #4).

Nothing below needs a paid Apple Developer account, and CI never sees an Apple
credential: the workflow builds an **unsigned** `.ipa` and you sign it yourself, on
your own machine, with a free Apple ID.

## 1. Get the build

Set the repository **variable** `MOBILE_API_URL` to your phone-reachable HTTPS
API base URL, or supply `api_url` when manually dispatching the mobile workflow.
It is public configuration, never a secret: do not include credentials, query
tokens, or fragments. Loopback and Android-emulator addresses are rejected.
Validation checks URL shape, not server availability; verify health on the phone.
Without a configured URL, CI still checks compilation but produces artifacts
ending in `-compile-only`, bundled with `https://api.invalid`. These intentionally
stay offline and cannot satisfy device/upload acceptance. Use `-device` artifacts
for the steps below. Local emulator development can explicitly set its separate
`--dart-define=API_URL`; do not use that URL for physical-device builds.

1. Open the repository's **Actions** tab and pick the most recent green **mobile** run.
2. Download the artifact for the phone you are installing on:
   - iPhone 12 Pro: `almanac-ios-unsigned-device` (contains `Almanac-unsigned.ipa`)
   - ARM64 Android phone: `almanac-android-arm64-apk-device` (contains `app-release.apk`)

Both come from `.github/workflows/mobile.yml`.
The Android artifact targets ARM64 phones only. CI separately builds an x86_64
release APK for the emulator, avoiding four-architecture native builds within
the 30-minute job budget.

## 2. iPhone 12 Pro, with Sideloadly and a free Apple ID

You need a Windows or macOS computer, a USB cable, and an Apple ID (a free one is
fine - do not use one with two-factor prompts you cannot answer).

1. Install **Sideloadly** from <https://sideloadly.io> and **iTunes** (Windows only,
   the Apple-website version, not the Microsoft Store version).
2. Connect the iPhone and trust the computer when the phone asks.
3. Open Sideloadly, drag `Almanac-unsigned.ipa` onto it, enter your Apple ID, and
   press **Start**. Sideloadly re-signs the app with your Apple ID and installs it.
4. On the phone: **Settings > General > VPN & Device Management**, tap your Apple ID
   under _Developer App_, then **Trust**.

### Developer Mode (iOS 16 and later)

1. **Settings > Privacy & Security > Developer Mode**, switch it on.
2. The phone restarts and asks you to confirm. Confirm.

Without Developer Mode the app installs but refuses to launch.

### Re-sign every 7 days

A free Apple ID signs apps with a certificate that **expires after 7 days**. On day 8
the app stops launching until you repeat step 3 above (your data survives; a reinstall
over the top is enough).

After every install, record it in [`devices.json`](devices.json):

- `installed_at` - today's date, ISO-8601, e.g. `"2026-09-17"`
- `build_sha` - the commit the build came from (shown on the Self-test screen)

The nightly check added in #6 reads that file and warns **2 days before** the 7 days
are up, so the phone is never dead on demo morning.

## 3. Android phone

1. On the phone: **Settings > About phone**, tap **Build number** seven times to turn
   on developer options, then turn on **USB debugging**.
2. From the computer: `adb install -r app-release.apk`
3. Confirm the phone can run AR: `bash scripts/check-arcore-device.sh`
   - `PASS` - ARCore is installed.
   - `FAIL` - the phone is not on Google's list
     (<https://developers.google.com/ar/devices>); use a different phone.
   - `SKIP` (exit 2) - no `adb`, or no phone attached.

Android has no LiDAR, so `lidar_depth` is reported `unsupported` there. That is
expected, not a defect.

## 4. Run the self-test

The app needs **iOS 15.5 or later** (Google ML Kit's minimum) and **Android 7.0
(API 24) or later**.

1. Open the app. It opens on Home and asks for nothing.
2. Reach the self-test: from the **Status** screen tap **Device self-test**, or
   build with `--dart-define=INITIAL_ROUTE=/self-test` so the app opens on it.
3. Tap **Run self-test**. Permissions are asked for one at a time, as the check
   that needs each one starts — camera first, then microphone, then location —
   and the screen says what each is for before any prompt appears. Grant them.
4. Follow the instruction on screen at each step:
   - **Camera preview** — a live preview shows for two seconds.
   - **Depth sensor** and **AR surface detection** — point the phone at the floor
     or ground and move it slowly for up to 20 seconds. A textured surface in good
     light finds a plane fastest.
   - **Microphone** — say something during the 3-second recording; it is played
     straight back. Note whether you heard yourself.
   - **Detector timing** — runs ML Kit on a bundled sample picture: one cold run,
     then three warm runs; the median warm run is `detector_ms`.
   - **Location** — one GPS fix, shown on a map (the map tiles need a network).
5. Every row ends in **Pass**, **Fail** (with the reason) or **Not supported on
   this phone**. Not supported is a correct answer: Android and non-Pro iPhones
   have no LiDAR, so their depth row reads Not supported, and that does not fail
   the phone.
6. Tap **Copy report** and paste the JSON into the issue as evidence, with a
   screenshot of the screen.

The report has the shape in [`api/devices-self-test.md`](api/devices-self-test.md).
**It is not uploaded yet**: the server side of `POST /devices/self-test` is backend
issue #11 and does not exist. Every run is saved on the phone instead, under the
app's documents directory at `self_test/latest.json` plus one file per run.

What each check proves, and what it does not:

- Camera passes only once a frame arrives from the image stream.
- AR passes only on a detected plane anchor — not on "ARKit/ARCore is supported".
- Depth passes only when a depth frame arrives: LiDAR `sceneDepth` on iOS, an
  ARCore Depth API image on Android.
- The camera is released before AR starts; only one client may hold it.
- Permission refusal, native errors and timeouts fail explicitly, with a reason.
- Widget tests cover this control flow against fake hardware. Whether the
  hardware itself works is exactly what only a real phone can show.

## Troubleshooting

**"Unable to install" in Sideloadly.** The free Apple ID limit is 3 sideloaded apps
and 10 new app IDs per 7 days. Remove an old sideloaded app and retry.

**The app installs but closes immediately.** Developer Mode is off (step 2), or the
7-day certificate has expired - re-run the Sideloadly install.

**The app shows "Offline".** That is the app working correctly with no API reachable.
Build with `--dart-define=API_URL=` set to a URL the phone can actually reach - not
`localhost`, which on a phone means the phone itself.

**AR says "Google Play Services for AR is missing or out of date".** Install or
update *Google Play Services for AR* from the Play Store and run the test again.

**A row says permission was refused.** The phone remembers a refusal. Allow the
permission in the phone's Settings for Almanac and run the test again.
