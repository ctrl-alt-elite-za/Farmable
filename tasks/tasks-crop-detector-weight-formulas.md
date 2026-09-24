# Tasks: Crop detector and weight formulas

**Source:** Farmable issue #16 and the local `docs/PRD-issue-16-crop-detection-and-weight-formulas.md`  
**Status:** Implementation checklist; all tasks are open  
**Repository path for vision work:** `apps/ml-service/vision/`

## Tasks

- [ ] **0.0 Create feature branch**
  - [ ] 0.1 Review the current branch and working-tree changes so the existing local PRD and `.gitignore` edit are preserved.
  - [ ] 0.2 Create a dedicated branch from the intended base, such as `feat/issue-16-crop-detector-weight-formulas`.
  - [ ] 0.3 Confirm the branch name and record the starting commit for the implementation notes.

- [ ] **1.0 Establish the field capture, privacy, annotation, and private dataset protocol**
  - [ ] 1.1 Confirm plot ownership or filming permission, private bucket location, access owners, and retention rules before collection.
  - [ ] 1.2 Define a capture log with stable `session_id`, crop, date, light condition, distance band, and permission status; treat continuous or near-duplicate footage as one session.
  - [ ] 1.3 Extend `LABELLING.md` with the fixed YOLO class order, box rules, difficult cases, reviewer steps, and privacy checks.
  - [ ] 1.4 Add approved example photos or private links with annotation overlays for cabbage, tomato, spinach, and `check_suggested`; keep raw image bytes out of Git.
  - [ ] 1.5 Verify ignore rules for private images, training runs, model artifacts, and credentials before importing data.

- [ ] **2.0 Collect, review, label, and version the cabbage, tomato, and spinach image dataset**
  - [ ] 2.1 Film at least 300 usable images per crop across morning, midday, and overcast light at 0.3–1.5 m; log coverage by crop and condition.
  - [ ] 2.2 Blur or discard frames with identifiable people or number plates before upload or annotation.
  - [ ] 2.3 Annotate all accepted images in Label Studio or CVAT with `plant`, `crop_head_or_fruit`, and `check_suggested` as applicable; do not label spinach leaves as fruit or infer disease.
  - [ ] 2.4 Have a second reviewer inspect a sample from every filming session, resolve disagreements, and record the review outcome.
  - [ ] 2.5 Export YOLO images and labels plus `image_sessions.csv`; check unique image-to-session/crop mapping and freeze a versioned private dataset snapshot.
  - [ ] 2.6 Upload originals, reviewed exports, and the manifest to the private bucket; record dataset version and checksum or immutable storage reference.

- [ ] **3.0 Enforce session-based dataset splits and validate the YOLO export against the issue criteria**
  - [ ] 3.1 Assign whole filming sessions to train and final test sets; derive validation only from training-side sessions and keep the final test set untouched during model selection.
  - [ ] 3.2 Update `check_split.py` to enforce at least 300 labelled images **per crop** while checking annotation-class support separately; its current default of 300 images per class does not match issue #16.
  - [ ] 3.3 Validate every image and YOLO label file, class ID, box range, manifest entry, and nonoverlapping train/test session set; reject ambiguous or missing mappings.
  - [ ] 3.4 Add regression tests for overlapping sessions, duplicate or missing manifest entries, malformed labels, insufficient crop counts, and valid data with sparse `check_suggested` examples.
  - [ ] 3.5 Run the split checker against the frozen dataset and retain its successful output with the dataset version.

- [ ] **4.0 Train the all-crop detector, evaluate each class and crop, and export versioned phone artifacts**
  - [ ] 4.1 Confirm the issue #2 training environment is available and install the pinned Colab dependencies; record source revision, dependency versions, seed, and run settings.
  - [ ] 4.2 Train one detector for all three crops on the frozen training dataset; use only training-side validation data for tuning.
  - [ ] 4.3 Evaluate once on held-out filming sessions and write `reports/<version>.json` with per-class precision, recall, `map50`, train/test sessions, crop image counts, and dataset/model versions.
  - [ ] 4.4 Add separate held-out cabbage, tomato, and spinach evaluation results; report unsupported metrics as null and identify weak classes or crop slices.
  - [ ] 4.5 Export the trained model to TFLite. If the iOS app uses Core ML, convert the same trained weights and record both format-specific artifact hashes under the same model version.
  - [ ] 4.6 Add tests for report schema, class-ID mapping, crop-specific support, version metadata, artifact hashes, and refusal to present the provisional YOLOE demo as a measured model.
  - [ ] 4.7 Review the real run and report before publishing the approved JSON report; keep weights, source photos, and training mosaics private.

- [ ] **5.0 Collect real cabbage and tomato measurements, fit weight ranges, and validate held-out coverage**
  - [ ] 5.1 Weigh and measure at least 20 distinct cabbages and 20 distinct tomatoes; retain sample IDs in collection records and fill the two CSVs with actual `diameter_cm,weight_g,date` values.
  - [ ] 5.2 Check units, positive finite values, dates, duplicate samples, and the observed diameter range before fitting.
  - [ ] 5.3 Fit each crop's formula using training measurements only and evaluate a fixed, untouched holdout; record held-out count, inside count, coverage, and supported diameter range.
  - [ ] 5.4 Require at least 80% held-out coverage for each crop; if it fails, collect additional real samples or revise the method without tuning on the held-out samples.
  - [ ] 5.5 Version the passing formula payloads and define scan behavior for diameters outside the measured range; do not produce a per-plant spinach formula.
  - [ ] 5.6 Extend evaluator tests for invalid data, deterministic splitting, coverage calculation, range bounds, and versioned output.

- [ ] **6.0 Register the production detector and weight formulas through the backend ORM**
  - [ ] 6.1 Upload the approved phone artifact to private artifact storage and verify its SHA-256 against the export manifest.
  - [ ] 6.2 Add a repeatable registration command or service that validates the report and stores model version, URI, hash, and metrics in `detector_models` using SQLAlchemy ORM operations.
  - [ ] 6.3 Register cabbage and tomato formula versions and payloads in `weight_formulas`; reject unsupported crops, incomplete formulas, and conflicting versions.
  - [ ] 6.4 Add unit and database integration tests for registration, duplicates, rollback on failure, and retrieval by version; preserve migration/ORM parity if a schema change is needed.
  - [ ] 6.5 Run `python -m app.scripts.detector_model_exists <version>` in the configured backend environment and verify the stored artifact identity.

- [ ] **7.0 Integrate the detector and formula versions into phone scans and measure physical-device performance**
  - [ ] 7.1 Bundle the registered trained artifact and its class/format manifest in an iOS development build; connect the camera path to real detector inference without blocking the UI thread.
  - [ ] 7.2 Replace the self-test's “no detector model is bundled” placeholder with timing from actual inference; keep unavailable or invalid measurements as failures.
  - [ ] 7.3 Define and implement scan provenance so every detection records its model version and every cabbage/tomato weight estimate records its crop-specific formula version; coordinate scan API/schema work with #18 and #19.
  - [ ] 7.4 Present `check_suggested` as an inspection prompt and suppress or qualify weight estimates beyond the measured diameter range.
  - [ ] 7.5 Add mobile and backend tests for manifest loading, version propagation, missing formula behavior, self-test pass/fail logic, and scan persistence or payloads.
  - [ ] 7.6 Run the exact release build on a physical iPhone 12 Pro and save a self-test showing `detector_ms` ≤ 20, with build SHA, model version/hash, device, and measurement method.

- [ ] **8.0 Review acceptance evidence, weak classes, privacy controls, and release readiness**
  - [ ] 8.1 Check all issue #16 acceptance criteria against the real report, 300-image-per-crop manifest, disjoint sessions, two 20-row measurement CSVs, coverage results, registry check, and iPhone self-test.
  - [ ] 8.2 Review weak or unmeasured classes and crop slices; narrow demo claims or capture more data and retrain where necessary.
  - [ ] 8.3 Verify that the public diff contains no private photos, model weights, training runs, bucket credentials, or unapproved media references.
  - [ ] 8.4 Run `make lint`, `make typecheck`, `make test`, and relevant integration and mobile tests; run `make check-no-raw-sql` for backend changes.
  - [ ] 8.5 Record artifact/report/formula versions, test commands, physical-device evidence, and remaining limitations in the implementation handoff before marking issue #16 complete.

## Relevant Files

Paths marked **new** are proposed locations; choose their final names when the corresponding implementation starts. Private data and generated model artifacts are evidence, not public source files.

- `.gitignore` — confirm private dataset, run, and model-artifact exclusions.
- `apps/ml-service/vision/LABELLING.md` — annotation contract, examples, and review rules.
- `apps/ml-service/vision/README.md` and `apps/ml-service/vision/MOBILE_DEPLOYMENT.md` — training, export, versioning, and phone handoff instructions.
- `apps/ml-service/vision/data/<version>/` **private/generated** — versioned images, labels, dataset YAML, and `image_sessions.csv`; must remain ignored and stored in the private bucket.
- `apps/ml-service/vision/check_split.py` — crop counts, manifest and annotation validation, session isolation.
- `apps/ml-service/vision/train.py` and `apps/ml-service/vision/requirements-colab.txt` — reproducible training and evaluation report generation.
- `apps/ml-service/vision/export.py` — existing provisional YOLOE exporter; keep its unmeasured status clear when adding a production export path.
- `apps/ml-service/vision/export_trained.py` **new** — possible trained-weight TFLite/Core ML export and artifact manifest.
- `apps/ml-service/vision/reports/<version>.json` **generated** — reviewed model metrics and split evidence.
- `apps/ml-service/vision/models/<version>.*` **private/generated** — exported phone artifacts and hashes; do not commit model weights.
- `apps/ml-service/vision/eval_weights.py`, `apps/ml-service/vision/weights/cabbage.csv`, and `apps/ml-service/vision/weights/tomato.csv` — measurement validation and held-out formula evaluation.
- `apps/ml-service/vision/weights/weight_formulas.json` **generated** — formula output; extend or rename for explicit version and supported diameter range.
- `apps/backend/src/farmable_backend/models.py` and `migrations/versions/0002_vision_artifacts.py` — existing detector/formula ORM and migration contract; add a new migration if schema changes are required.
- `apps/backend/src/farmable_backend/scripts/register_vision_artifacts.py` **new** — possible ORM registration command for approved model and formulas.
- `apps/backend/src/farmable_backend/scripts/detector_model_exists.py` — existing version-existence acceptance check.
- `apps/backend/src/farmable_backend/schemas.py` and scan handler/model files **new if needed** — versioned scan request and persistence contract, coordinated with #18/#19.
- `apps/mobile/app.config.ts`, `apps/mobile/App.tsx`, and `apps/mobile/src/native/detector.ts` **new** — bundle and load the trained model and expose live detections.
- `apps/mobile/src/native/probes.ts`, `apps/mobile/src/selftest/report.ts`, and `apps/mobile/src/screens/SelfTestScreen.tsx` — measure real inference and report the detector budget.
- `apps/mobile/src/screens/ScanScreen.tsx` **new** — possible scan UI and versioned result display, coordinated with #18/#19.
- `packages/api-client/openapi.json` and `packages/api-client/src/schema.d.ts` **generated if API changes** — regenerate with `make client`; never hand-edit.
- `scripts/tests/test_vision_tools.py` and `scripts/tests/test_vision_training.py` — split, export, formula, training, and report regression tests.
- `apps/backend/tests/test_vision_schema.py`, `apps/backend/tests/integration/test_stack.py`, and `apps/backend/tests/test_vision_registry.py` **new** — ORM/migration parity, registration, and database tests.
- `apps/backend/tests/test_scan_provenance.py` **new** — scan version persistence or payload tests if scan integration lands in this issue.
- `apps/mobile/src/native/__tests__/probes.test.ts`, `apps/mobile/src/native/__tests__/detector.test.ts` **new**, and `apps/mobile/src/selftest/__tests__/report.test.ts` — detector adapter and self-test tests.
- `apps/mobile/src/screens/__tests__/ScanScreen.test.tsx` **new** — scan result and version display tests if the scan screen is added here.

## Notes

- The PRD and phase 1 draft live in the gitignored `docs/` directory. This task file in `/tasks/` is intended to be reviewable in Git; its acceptance criteria are restated here so it can stand alone.
- Field capture, annotation, weighing, private bucket access, Colab training, and iPhone timing require people, permissions, or hardware. Code tests cannot substitute for those artifacts.
- The current report contains per-class metrics and crop image counts, but issue #16 needs separate crop results. The current split CLI's default minimum is per annotation class, while the issue minimum is per crop.
- Keep the provisional YOLOE demo separate from the trained, measured model. Do not mark an acceptance item complete using placeholder data or a manually entered timing value.
- Follow `AGENTS.md`: use the SQLAlchemy ORM, add tests for backend behavior, do not commit secrets, and validate the issue's acceptance criteria before closure.
