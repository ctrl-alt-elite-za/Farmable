# Africa grounded photo prompt map

This document maps the app's shipped image assets and photo-like visual surfaces, then provides prompts for creating realistic African farm photography for them. It is a prompt and implementation reference; it does not add or replace image assets.

## Scope and image inventory

The mobile app is Flutter. Its farm and crop surfaces currently use `CropImagery`, a deterministic `CustomPainter` illustration, rather than photographs. This is stated in `apps/mobile/lib/core/ui/crop_imagery.dart`: farm imagery is drawn to avoid implying that stock photography depicts a farmer's actual land, and to keep the app small for users with limited data. The prompts below are therefore for a future opt-in photographic art direction or user-selected demo imagery; they should not be presented as pictures of a specific farmer's own farm.

| Image or scene | Current source | Current dimensions | Where it appears / role |
| --- | --- | --- | --- |
| Farm overview | `CropScene.farm` in `apps/mobile/lib/core/ui/crop_imagery.dart` | Runtime-drawn; no intrinsic pixel size. Home card is 16:11 (for example, 576 × 396 px at 2× for a 360 dp-wide phone); auth hero is adaptive and portrait; farm/section surfaces can use other sizes. | Auth choice hero, home farm hero, and farm-related imagery. |
| Cabbage field | `CropScene.cabbage` in `crop_imagery.dart` | Runtime-drawn; cards can be 16:11, 128 dp high, or a 38%-screen-height hero. | Section/farm cards and zone hero, observation fallback, crop recommendation cards/details. |
| Tomato field | `CropScene.tomato` in `crop_imagery.dart` | Runtime-drawn; same responsive targets as cabbage. | Same crop imagery surfaces when the crop is tomato. |
| Spinach/leafy crop field | `CropScene.spinach` in `crop_imagery.dart` | Runtime-drawn; same responsive targets as cabbage. Also the fallback for an unrecognised crop. | Same crop imagery surfaces when the crop is spinach or an unrecognised crop. |
| Bare/unplanted plot | `CropScene.bare` in `crop_imagery.dart` | Runtime-drawn; same responsive targets as cabbage. | Empty or unplanted sections and crop imagery surfaces. |
| Camera self-test sample | `apps/mobile/assets/self_test/sample_field.jpg` | 640 × 480 px (4:3) | Loaded by `materializeSampleImage` in `apps/mobile/lib/data/device/object_detector.dart` for an on-device detector timing/self-test; also the recorded photo-taker sample in test mode. This is a synthetic illustration, not a field photograph or model-accuracy evidence. |
| Camera playback frames 00–07 | `apps/mobile/assets/test_mode/frame_00.jpg` … `frame_07.jpg` | Each 480 × 360 px (4:3), declared by `apps/mobile/assets/test_mode/recording.json`. | Eight-frame recorded camera preview in test mode; detection overlays are synthetic and defined in `recording.json` and `crop_scan.json`. Frames are illustrated, not photographic evidence. |
| App icons and launch images | `apps/mobile/android/app/src/main/res/` and `apps/mobile/ios/Runner/Assets.xcassets/` | Device-specific icon and launch-image sizes; these are branding assets, not photographs. | Android/iOS app launch and home screen. Do not generate photographic replacements for these. |
| Screenshots | `apps/mobile/screenshots/` | Fixed capture sizes, not source imagery. | Design, comparison, and regression documentation only; not in-app photo assets. |

Live camera captures and farmer-uploaded observation photos are user-generated, device-dependent images. They have no fixed bundled dimensions and should remain authentic captures rather than AI-generated replacements.

### In-app surfaces using the drawn scenes

The shared scene painter is used by the auth choice hero (`features/auth/auth_choice_screen.dart`), onboarding art (`features/auth/widgets/onboarding_art.dart`), home farm hero (`features/home/widgets/farm_hero_card.dart`), farm section cards (`features/farm/widgets/farm_sections.dart`), zone cards and zone detail hero (`features/home/widgets/zone_card.dart`, `features/zone/widgets/zone_hero.dart`), observation fallback tiles (`features/zone/widgets/observation_list.dart`), and recommendation cards/details (`features/recommendations/widgets/recommendation_card.dart`, `features/recommendations/recommendation_detail_screen.dart`). All are responsive Flutter layouts, so a generated image needs a clean central subject, safe crops at portrait and landscape ratios, and no text or important detail at the edges.

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
