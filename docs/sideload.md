# Installing Farmable on the test phones

The app uses the camera, LiDAR depth, AR planes, the microphone and an on-device
detector. None of that runs in Expo Go or on an emulator, so the only way to test
those features is a **development build** on a real phone (issue #4).

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
`EXPO_PUBLIC_API_URL`; do not use that URL for physical-device builds.

1. Open the repository's **Actions** tab and pick the most recent green **mobile** run.
2. Download the artifact for the phone you are installing on:
   - iPhone 12 Pro: `farmable-ios-unsigned-device` (contains `Farmable-unsigned.ipa`)
   - Android: `farmable-android-apk-device` (contains `app-release.apk`)

Both come from `.github/workflows/mobile.yml`.

## 2. iPhone 12 Pro, with Sideloadly and a free Apple ID

You need a Windows or macOS computer, a USB cable, and an Apple ID (a free one is
fine - do not use one with two-factor prompts you cannot answer).

1. Install **Sideloadly** from <https://sideloadly.io> and **iTunes** (Windows only,
   the Apple-website version, not the Microsoft Store version).
2. Connect the iPhone and trust the computer when the phone asks.
3. Open Sideloadly, drag `Farmable-unsigned.ipa` onto it, enter your Apple ID, and
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

1. Open the app and pick the **Self-test** tab.
2. Tap **Run self-test** and grant camera, microphone and location when asked.
3. It checks camera preview, LiDAR depth, AR planes and a 3-second microphone
   recording with playback, times the detector, and uploads the result to
   `POST /devices/self-test` (see [`api/devices-self-test.md`](api/devices-self-test.md)).

Camera passes only after a preview frame callback. LiDAR passes only after a
single captured photo returns a nonempty, valid depth buffer from a back LiDAR
video/depth device. The camera must report stopped and unmount before AR starts.
Move the phone slowly over a textured flat surface: AR passes only on a detected
plane anchor, not support detection. Permission refusal, native errors, and
observation timeouts fail explicitly. Mock tests cover this control flow, not
hardware correctness. Real-phone verification, the #16 detector model, and the
backend self-test endpoint remain separate acceptance work; do not close #4.

Read the result back from the server with:

```bash
curl "$EXPO_PUBLIC_API_URL/devices/self-test?build_sha=<sha>&platform=ios"
```

Anything that did not pass must carry a note naming a GitHub issue, so a failure is
always attached to the work that will fix it.

## Troubleshooting

**"Unable to install" in Sideloadly.** The free Apple ID limit is 3 sideloaded apps
and 10 new app IDs per 7 days. Remove an old sideloaded app and retry.

**The app installs but closes immediately.** Developer Mode is off (step 2), or the
7-day certificate has expired - re-run the Sideloadly install.

**The app shows "Offline".** That is the app working correctly with no API reachable.
Set `EXPO_PUBLIC_API_URL` for the build to a URL the phone can actually reach - not
`localhost`, which on a phone means the phone itself.
