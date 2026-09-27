# Africa grounded photo prompt map

This document maps the app's photo-like surfaces, preserves the generation prompts, and records the representative images now used by the seeded demo.

## Scope and image inventory

The mobile app is Flutter. Farm and crop surfaces use `CropImagery`: deterministic `CustomPainter` scenes on account farms and representative South African photographs only on the seeded demo. The images are not presented as a specific farmer's own land. Their five JPEGs add about 1.5 MB to the app bundle.

| Image or scene | Current source | Current dimensions | Where it appears / role |
| --- | --- | --- | --- |
| Farm overview | `CropScene.farm` in `apps/mobile/lib/core/ui/crop_imagery.dart`; demo file `apps/mobile/assets/demo/farm.jpg` | Demo photo 1200 × 900 px (4:3), 307 KB; account farm uses a runtime-drawn scene. UI crops responsively, including a 16:11 home hero. | Home farm hero on the seeded demo; representative photo is excluded from account farms. |
| Cabbage field | `CropScene.cabbage`; demo file `apps/mobile/assets/demo/cabbage.jpg` | Demo photo 1200 × 900 px (4:3), 278 KB; account farm uses a runtime-drawn scene. Cards and heroes crop responsively. | Demo section/farm cards and zone hero, observation fallback, crop recommendation cards/details. |
| Tomato field | `CropScene.tomato`; demo file `apps/mobile/assets/demo/tomato.jpg` | Demo photo 1200 × 900 px (4:3), 348 KB; account farm uses a runtime-drawn scene. | Same demo crop surfaces when the crop is tomato. |
| Spinach/leafy crop field | `CropScene.spinach`; demo file `apps/mobile/assets/demo/spinach.jpg` | Demo photo 1200 × 900 px (4:3), 244 KB; account farm uses a runtime-drawn scene. Also the fallback for an unrecognised crop. | Same demo crop surfaces when the crop is spinach or an unrecognised crop. |
| Bare/unplanted plot | `CropScene.bare`; demo file `apps/mobile/assets/demo/bare.jpg` | Demo photo 1200 × 900 px (4:3), 326 KB; account farm uses a runtime-drawn scene. | Empty demo sections and crop imagery surfaces. |
| Camera self-test sample | `apps/mobile/assets/self_test/sample_field.jpg` | 640 × 480 px (4:3) | Loaded by `materializeSampleImage` in `apps/mobile/lib/data/device/object_detector.dart` for an on-device detector timing/self-test; also the recorded photo-taker sample in test mode. This is a synthetic illustration, not a field photograph or model-accuracy evidence. |
| Camera playback frames 00–07 | `apps/mobile/assets/test_mode/frame_00.jpg` … `frame_07.jpg` | Each 480 × 360 px (4:3), declared by `apps/mobile/assets/test_mode/recording.json`. | Eight-frame recorded camera preview in test mode; detection overlays are synthetic and defined in `recording.json` and `crop_scan.json`. Frames are illustrated, not photographic evidence. |
| App icons and launch images | `apps/mobile/android/app/src/main/res/` and `apps/mobile/ios/Runner/Assets.xcassets/` | Device-specific icon and launch-image sizes; these are branding assets, not photographs. | Android/iOS app launch and home screen. Do not generate photographic replacements for these. |
| Screenshots | `apps/mobile/screenshots/` | Fixed capture sizes, not source imagery. | Design, comparison, and regression documentation only; not in-app photo assets. |

Live camera captures and farmer-uploaded observation photos are user-generated, device-dependent images. They have no fixed bundled dimensions and should remain authentic captures rather than AI-generated replacements.

### In-app surfaces using crop imagery

`CropImagery` provides representative photos for the seeded demo and the existing painter for account farms. Demo photos appear on the home farm hero, section carousel and list, zone hero, observation fallback tiles, and bundled crop recommendations/details. Auth choice and onboarding artwork keep their existing compositions. All surfaces are responsive Flutter layouts, so the images are cropped with `BoxFit.cover` and use the existing text scrim.

## Shared direction for every prompt

Create documentary-quality, photorealistic photography of a plausible small-scale farm in **South Africa** (or another explicitly named African location), with locally plausible crops, soil, light, tools, irrigation, buildings, and vegetation. Show contemporary African farmers and working farms with dignity when people are present; avoid stock-photo posing, poverty imagery, safari/wildlife motifs, generic “African village” clichés, and non-African farm architecture. Use natural available light, believable camera optics, honest textures, restrained colour, and a lived-in but cared-for setting. No text, labels, logos, UI, borders, watermarks, or artificially perfect rows. Leave useful quiet space in the lower third for white UI text and keep the main subject away from crop-sensitive edges.

Unless a prompt calls for a specific camera-test frame, generate a **2048 × 1536 px, 4:3 JPEG** master. This exceeds the current 640 × 480 and 480 × 360 asset sizes and allows responsive cropping. For full-bleed interface photography, also make a **2048 × 2730 px portrait-safe crop** from the same scene or request sufficient scene width and headroom for both 4:3 and portrait crops. Do not upscale a smaller generated image to reach these sizes.

## Ready-to-use prompts

### 1. Farm overview — auth and dashboard heroes

> Photorealistic documentary photograph of a real small-scale mixed vegetable farm in rural KwaZulu-Natal, South Africa, seen from a modest rise just above the field. Show several practical growing beds with visible cabbage and leafy greens, a narrow earth access path, a modest water tank and simple irrigation hose, distant subtropical hills softened by morning haze, and a few indigenous trees. Warm early morning light after summer rain, rich but natural greens against red-brown South African soil. No people are necessary; if present, show one local farmer naturally tending a bed, not facing or posing for the camera. Eye-level elevated viewpoint, realistic 35 mm lens, foreground-to-background depth, documentary colour, fine natural texture. Compose with a clear lower-third darkened by natural shade for interface copy; keep the beds and tank legible in a 16:11 horizontal crop and leave enough width and sky for a portrait crop. No text, branding, wildlife, mountains exaggerated into a tourism postcard, or non-African farm buildings. 2048 × 1536 px, 4:3.

### 2. Cabbage plot — crop cards and section detail

> Photorealistic close-to-medium documentary photograph of a healthy, modest cabbage plot on a smallholder farm in the Eastern Cape, South Africa. Several recognisable mature green cabbage heads grow in slightly irregular, hand-worked rows in dark red-brown soil; show real leaf veins, a few imperfect outer leaves, light mulch, and subtle drip irrigation. At least one cabbage head is clearly visible near the centre, with a few plants receding behind it. Soft bright overcast daylight, true-to-life greens, camera held at plant height, realistic 50 mm lens and depth of field. Keep the main head centred and enough context around it to crop to both a wide card and a tall phone hero. Leave the bottom quarter relatively uncluttered for a dark UI gradient. No labels, plastic-looking leaves, gigantic produce, text, logo, or staged harvest props. 2048 × 1536 px, 4:3.

### 3. Tomato plot — crop cards and section detail

> Photorealistic documentary photograph of a smallholder tomato bed in Limpopo, South Africa, in the natural growing season. Show healthy tomato plants supported by simple wooden stakes and twine, clusters of real red and green tomatoes at different ripening stages, slightly irregular rows, dry grass mulch, and practical low-cost drip irrigation over warm brown soil. One recognisable tomato cluster sits close to the centre; the rest of the bed recedes naturally. Clear late-afternoon African sunlight with realistic leaf shadows, balanced exposure, documentary 50 mm lens, not a commercial greenhouse. Compose safely for a 16:11 crop and a portrait crop; leave a visually calm lower quarter for interface text. No text, signage, logos, spotless industrial rows, or oversaturated fruit. 2048 × 1536 px, 4:3.

### 4. Spinach/leafy plot — crop cards and fallback

> Photorealistic documentary photograph of a small, actively harvested spinach bed on a community-scale farm near Johannesburg, South Africa. Dense but believable dark green spinach leaves with varied sizes and a few natural imperfections fill hand-worked raised beds; show dark compost-rich soil, a simple watering line, and a hint of neighbouring vegetable rows. Camera just above leaf height, one crisp cluster centred, background leaves gradually softer, gentle morning light, natural colour and accurate leaf texture. The subject must read clearly as spinach rather than lettuce or ornamental foliage. Keep the main greens central and leave the lower quarter simple enough for a dark text gradient; support horizontal-card and vertical-hero crops. No text, labels, plastic shine, or decorative props. 2048 × 1536 px, 4:3.

### 5. Bare/unplanted section — empty plot fallback

> Photorealistic documentary photograph of a small, temporarily unplanted vegetable bed on a working farm in the Free State, South Africa. Show a clearly prepared but empty plot: realistic reddish-brown earth, shallow hand-made furrows, a few small stones and dry plant residue, an adjacent cultivated bed softly out of focus, and a simple water hose at the edge. The scene should feel seasonally between plantings and ready for use, not abandoned, barren, drought-stricken, or damaged. Low eye-level angle, gentle early morning light, restrained earthy palette and true photographic soil texture. Compose with a calm central area and crop-safe context for both a landscape card and portrait hero; lower quarter can carry white UI text over a dark gradient. No people required, no text or logos. 2048 × 1536 px, 4:3.

### 6. Detector self-test sample — replacement for `sample_field.jpg`

> Photorealistic, natural 4:3 camera photograph for a crop detector's benign on-device timing self-test. Show an ordinary South African backyard or smallholder vegetable plot, with one clearly identifiable young cabbage plant and one clearly identifiable tomato plant growing separately in the same frame, both fully visible and surrounded by enough context to recognise the leaves. Natural brown soil, a few neighbouring seedlings, soft neutral daylight, phone-camera viewpoint at plant height, realistic modest detail. Keep the two plants separated, centred, and unobstructed so a computer-vision test can inspect them; do not add disease symptoms, insects, labels, bounding boxes, or diagnostic claims. This is a demo/test image only, not evidence of detector accuracy. 640 × 480 px, 4:3 JPEG (prefer generating at 1280 × 960 and downsampling once).

### 7. Recorded camera playback — replacements for `frame_00.jpg` through `frame_07.jpg`

> Create a coherent sequence of eight photorealistic 4:3 phone-camera frames from one continuous, slow handheld pan across a smallholder vegetable bed in South Africa. Keep the same daylight, soil, background rows, camera height, focus, and colour in every frame. The scene contains a clearly visible cabbage plant and a separate simple red tomato seedling pot or marker as stable visual targets; the camera pans gently so their positions shift smoothly from frame to frame, with no sudden changes, added objects, or cuts. Realistic local garden soil and practical planting, natural imperfect leaves, neutral daylight, no people, no text, no labels, no logos, no detection boxes. Deliver eight individual frames named `frame_00.jpg` to `frame_07.jpg`, each exactly 480 × 360 px. Preserve enough separation and contrast around both targets for the app's separately supplied synthetic test overlays. These images support UI playback only; they must not be described as real detector predictions or field-validation data.

## Generation and integration notes

- Keep the current responsive UI's `BoxFit.cover` behavior in mind: review every image at 16:11, 4:3, and portrait hero crops before accepting it.
- The app applies a bottom-to-top `ImageryScrim` over photographic-looking heroes. Prompts should preserve meaningful image detail while leaving enough tonal variation for the overlay; do not bake text or a dark gradient into the generated image.
- Keep crops separate by scene. Do not use a generic farm landscape for a crop-identification surface where a cabbage, tomato, spinach, or empty plot is expected.
- The eight recorded camera frames are a single test fixture set and must remain visually continuous; update or validate their paired normalized detection boxes if the positions of plants change.
- Never substitute generated photos for a user's farm, observations, or camera captures. Clearly identify any bundled demo photography as representative imagery.
- App icons, launch images, UI screenshots, map tiles, and runtime camera/user images are inventoried above for completeness, but are not photography-generation targets.
