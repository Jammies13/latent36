# Film library reliability

## Scope

Protect existing photographs during library startup failures while retaining the bundle identifier, JSON schema, film recipes, and 24-hour development rule.

## Changes

- Refuse initialization when the index is absent but encrypted frame files remain. The previous code generated and wrote a replacement key in this case.
- Reuse an existing valid key when initialization stopped before the first index write, and write an empty index on successful first launch.
- Validate roll identity, frame identity, frame paths, capacity, development state, and the single active roll before accepting loaded state.
- Keep partially loaded metadata out of the actor's live state and reject access or development until loading succeeds.
- Use specific library errors instead of reporting a capture-processing failure for damaged storage.
- Add isolated vault regression fixtures and run them in the existing macOS build workflow.

## Validation

- Local whitespace and patch checks: `git diff --check`.
- Swift, Apple frameworks, and Xcode are unavailable on this Windows host. The new Swift suite and iPhone build require the macOS CI run or a Mac; they have not been executed here.
- No real photo library is accessed by the regression suite. It creates and removes only a uniquely named temporary fixture directory.

## Limits

These changes preserve files when opening fails. They do not recover a missing index or key. A valid-length but incorrect key is still detected by authenticated decryption when a developed photograph is opened. Missing individual frame files remain per-photo errors so other developed frames stay accessible.
