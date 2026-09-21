# PR 43 production review design

## Goal

Make the pretrained detector evidence gate fail closed while keeping the PR
honest about missing physical-device evidence and mobile integration.

## Design

- Replace caller-supplied fixture aggregates with a versioned fixture set and
  separate iOS and Android runs.
- Bind every fixture to a lowercase SHA-256 and bind each platform run to the
  exact Core ML or TFLite artifact hash in the export manifest.
- Require identical fixture coverage on both platforms, at least two positive
  fixtures per required crop, at least two negative fixtures, matching crop
  labels, and zero derived negative detections.
- Validate timezone-aware benchmark creation timestamps.
- Make directory artifact hashes canonical and independent of the output
  directory name.
- Stage exports and clean up published output if an export fails, leaving no
  half-created version.
- Update tests and handoff documentation for the new evidence contract.

The release gate records evidence completeness only. It does not claim model
quality, camera-pipeline readiness, or completion of Issue 16 without real
device reports.

## Verification

Run vision tool tests plus formatting, linting, type checking, and the complete
repository verification suite.
