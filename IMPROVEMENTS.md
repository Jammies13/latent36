# Film library reliability

## Scope

Protect existing photographs during library startup failures while retaining the bundle identifier, compatibility with existing roll libraries, and the 24-hour development rule.

## Changes

- Refuse initialization when the index is absent but encrypted frame files remain. The previous code generated and wrote a replacement key in this case.
- Reuse an existing valid key when initialization stopped before the first index write, and write an empty index on successful first launch.
- Validate roll identity, frame identity, frame paths, capacity, development state, and the single active roll before accepting loaded state.
- Keep partially loaded metadata out of the actor's live state and reject access or development until loading succeeds.
- Use specific library errors instead of reporting a capture-processing failure for damaged storage.
- Add isolated vault regression fixtures and run them in the existing macOS build workflow.
- Add per-roll Off, Fine, Classic and Heavy grain with a backward-compatible default, shared preview/capture rendering, stock-specific cluster sizes and highlight bloom.
- Generate deterministic monochrome texture with bounded single-channel scratch, neutral overlay blending and cancellation checks.
- Add Photos export progress and cooperative stopping after an in-flight save completes.
- Add numerical texture regressions, full-resolution detail crops, and a Heavy grain simulator screenshot.
- Add a 3x sample-detail toggle with matching Film/Original crops for inspecting grain before loading.

## Validation

- Local whitespace and patch checks: `git diff --check`.
- Builds and Swift tests run through GitHub Actions on macOS. The first run caught a case-insensitive object filename collision between Vault.swift and vault.swift; renaming the test to VaultChecks.swift fixed the collision. Final run results will be recorded after validation.
- No real photo library is accessed by the regression suite. It creates and removes only a uniquely named temporary fixture directory.

## Limits

These changes preserve files when opening fails. They do not recover a missing index or key. A valid-length but incorrect key is still detected by authenticated decryption when a developed photograph is opened. Missing individual frame files remain per-photo errors so other developed frames stay accessible.
