# Queued focus-photo diagnosis

This backend flow implements the queued diagnosis portion of #7. It does not
change the UI, automatically scan the farm, or complete frontend issue #19.
The Gemini Live path is unchanged. No live provider calls or deployment were
performed while implementing this flow.

## Client contract

Use the existing verified Farmable Bearer session. Read `GET /diagnoses/notice`
and display its versioned notice before an explicit submission. Do not infer
permission from uploading a photo or opening a section. The notice itself is
public static text; all farm data operations require authentication.

Submit `POST /farms/{farm}/sections/{section}/diagnoses` with a client UUID `id`,
the `media_id` of a **ready, cleaned** photo, an active `planting_id` in that same
section, and the displayed `consent_notice_version`. The crop comes from the
stored planting, never the client's claimed crop. The response is 202 with a
durable snapshot, not a successful diagnosis. Exact retries reuse that snapshot;
changing the inputs for an existing UUID returns 409 and never starts new work.

Poll `GET /farms/{farm}/diagnoses/{id}` or the bounded, UUID-cursor list at
`GET /farms/{farm}/diagnoses`. States are `queued`, `processing`, `ready`,
`unavailable` and `cancelled`. Results contain at most five named suggestions
with provider probabilities and an explicit warning. They are not calibrated
Farmable confidence scores or treatment prescriptions. Fake results say
`data_kind: synthetic`; clients must preserve that label. No object keys,
image bytes, provider URLs or provider credentials appear in these responses.

`POST /farms/{farm}/diagnoses/{id}/cancel` withdraws permission for this submission,
clears its saved result and prevents future publication, including a late worker
reply. Retrying or replaying the same UUID cannot regrant permission. Cancellation
cannot recall a request already sent or erase Kindwise's copy. Saved results and
receipts remain until cancellation/account deletion; they are farm records, not
30-day chat content. Owner exports include these records. Account deletion removes
them and fences in-flight publication. Other users and other farms cannot read
or cancel the submission.

## Worker and failure behaviour

The existing worker process polls the durable table every five seconds, claiming
one job at a time with a 180-second fenced lease. It reads only the cleaned photo's
recorded storage generation, checks its exact length and SHA-256, and rechecks the
farm, section, media, planting version and consent before sending and publishing.
No external I/O occurs while database locks are held.

There are at most four pending submissions and 20 submissions per owner per
rolling day. Those limits are **not** system-wide priced spend reconciliation.
Each provider POST has one adapter attempt and a 21-second outer timeout. A known
pre-call circuit refusal, storage outage, or provider 429 remains queued with
bounded backoff (at most three claims). A timeout/network error or expired
in-flight lease is `delivery_unknown`: the provider might already have billed
the request, so the worker does not silently submit it again. Jobs older than one
day stop rather than running indefinitely. Invalid/mismatched provider output is
unavailable, never a fabricated healthy result. Original photos are retained.

The client should show queued/retry status and offer manual observation when
unavailable. A new UUID is a new potentially billable submission and requires a
new explicit user action, not an automatic frontend retry.

## Enablement and schema

Apply the additive `0015` migration before deploying this API/worker revision,
even with diagnosis disabled; account export/deletion also uses its table.
It needs independent migration review. Never reuse another branch's migration
revision number when integrating migration histories. Downgrade requires stopping
submission and draining the worker; it destroys diagnosis receipts/results but
does not delete photos or provider copies.

`DIAGNOSIS_ENABLED` defaults to false on both API and worker. Enabling requires
the existing private `PHOTO_BUCKET`/`PHOTO_SIGNER_EMAIL` configuration, the
normal workload-identity storage permissions, and approved `INTEGRATIONS_MODE`
and `CROP_HEALTH_API_KEY`. Supply photo settings to both processes using the
deployment's existing photo configuration; this change does not provision a
bucket or modify IAM. Disabled submission returns 503; existing reads and
cancellation still work. Disabling/draining the worker stops new processing but
cannot retract a request already in flight. Verify provider terms and an approved
spend policy before live enablement; no arbitrary user-supplied image URL is fetched.

## Coverage and acceptance evidence

For Farmable's current crops, only tomato, onion and potato (including their
plural aliases) are admitted to the provider. Kindwise's
[published crop list](https://www.kindwise.com/crop-health) does not list cabbage
or spinach as of 2026-09-24. They return `unavailable/unsupported_crop` without a
provider request. This is not proof of crop-specific accuracy even for admitted
crops. Obtain provider confirmation or formally change the acceptance criterion;
do not claim cabbage/spinach coverage from a canned response.

Separately, the [ISRIC SoilGrids FAQ](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_02.html)
still documents REST as temporarily paused. An all-services live smoke PASS cannot
be honestly recorded against unavailable requirements. Keep the existing smoke
gate intact pending an approved alternative or formal criterion amendment.

Offline tests exercise the real queue/HTTP boundaries, tenant isolation, exact
retries, consent cancellation, account erasure, storage integrity, malformed
responses and failure handling. A selected PostgreSQL integration test races
submissions and claims across separate connections. Neither synthetic tests nor
green CI establish live provider accuracy, calibrated evaluations or staging
smoke acceptance. Those remain open, alongside invoice-backed spend reconciliation.
