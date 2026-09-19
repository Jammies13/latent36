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
- Builds and Swift tests run through GitHub Actions on macOS. The first run caught a case-insensitive object filename collision between Vault.swift and vault.swift; renaming the test to VaultChecks.swift fixed the collision.
- [Actions run 35459699492](https://github.com/Jammies13/latent36/actions/runs/35459699492) passed for application source commit `21f373c75baaa4552da15795a1e5cc8a826322b1`: sample privacy, roll rules and persistence, all 40 sample/stock renders, vault recovery safety, grain/bloom checks, Release iPhone build, IPA packaging, and simulator launches/screenshots.
- Visually reviewed the default film picker, Heavy grain detail, Original comparison, camera layout and Options screenshots. Reviewed Amber Off/Classic/Heavy and Noir Heavy detail crops and the Daylight river render. Camera capture itself is unavailable in the simulator; the screenshot's camera error is not device-capture validation.
- Version 1.2, build 4 IPA downloaded to `build/Latent36.ipa` (20,441,735 bytes). Independently checked the arm64 Mach-O header and byte-identical copies of all four bundled sample photos. SHA-256: `75f7be787cbf8d3c2f30c7c5684a8ba327ef1877869adcf9801f9b67862ff0aa`.
- Real iPhone camera capture, Photos export/Stop behavior, and LiveContainer execution still require the device checks in PHONE-TEST.md.
- No real photo library is accessed by the regression suite. It creates and removes only a uniquely named temporary fixture directory.

## Limits

These changes preserve files when opening fails. They do not recover a missing index or key. A valid-length but incorrect key is still detected by authenticated decryption when a developed photograph is opened. Missing individual frame files remain per-photo errors so other developed frames stay accessible.
