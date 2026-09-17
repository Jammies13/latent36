# Latent 36

A small, ad-free film camera for iPhone. Load a film stock, shoot 36 photographs, then press **Develop**. The entire roll stays hidden for **24 hours from that button press**. Afterward, open the Darkroom contact sheet and save individual photos or the entire roll to Photos. You can shoot a new roll while others develop.

## Camera and film

- Real AVFoundation capture with available physical main, ultra-wide, telephoto and selfie cameras.
- Tap to focus/meter, auto exposure with EV compensation, manual ISO and shutter, manual focus, manual white balance, digital zoom, flash, thirds grid, 3/10-second timer.
- Hardware capabilities determine available controls; switching lenses resets controls. Flash is disabled during manual exposure so the chosen exposure is respected.
- Four original Core Image recipes: Daylight 200 (soft/warm), Amber 400 (warm highlights/cool shadows), Chrome 100 (saturated/contrasty), Silver 400 (monochrome/grain).
- Natural viewfinder; processed film photographs are revealed only after development. Recipe numbers are creative names, not a forced sensor ISO or licensed commercial stock simulation.
- Capture prefers approximately 12 MP where supported; rendered JPEGs are capped at 4096 pixels on the longest edge to bound memory. No RAW, video, or Live Photos.
- Portrait interface with orientation-aware landscape photo capture.

## LiveContainer first, direct SideStore fallback

Import `Latent36.ipa` into an up-to-date official LiveContainer build and launch normally **full-screen**. No JIT, paid signing membership, special entitlements, extensions, background service, or notifications are required. The current official LiveContainer declares guest camera and photo-library usage descriptions.

Allow camera access when asked. Inside LiveContainer, the permission may appear under the host's name. If the viewfinder stays black: check **Settings → Privacy & Security → Camera → LiveContainer**, close other camera apps, and reopen the guest full-screen. Export asks for Photos add access only when needed; check the host's Photos permission if export fails.

If camera capture still fails, import the **same IPA directly in SideStore**. Direct installation gives the app independent permissions and lifecycle, at the cost of a free-account app slot and normal signing refreshes. LiveContainer saves a separate slot but adds host-specific compatibility constraints. The binary is built for both routes; an actual iPhone/LiveContainer test remains necessary, especially on iOS betas.

**Libraries are separate.** Switching installation methods does not transfer rolls. Keep the original installation and its container until the rolls have developed and you have exported the photos. Deleting either app/container destroys its local library.

Official reference: https://github.com/LiveContainer/LiveContainer

## Storage and development

JPEGs are processed and AES-GCM-encrypted in private Application Support storage. Keys are stored in the same private installation rather than relying on shared keychain entitlements. Nothing is uploaded. File sharing is disabled. Counts change only after a successful photo write and atomic metadata save; failures do not consume an exposure. Existing unreadable libraries are not silently reset.

The wait uses a persisted local timestamp and survives relaunch/reboot without background execution. Keep automatic date/time enabled. This is an offline film ritual, **not a tamper-proof time lock** against changing the clock or extracting app data. Encryption prevents casual viewing of frame files; it is not intended to protect photos from the device owner or a privileged host. No previews or early-development bypass are shipped.

## Free builds

The public repository builds with standard `macos-15` GitHub Actions runners. The job explicitly skips private repositories. No paid services, dependencies, account credentials or signing certificates are used in CI.

1. Open **Actions → Build Latent 36**.
2. Run the workflow, or push to `main`.
3. Download **Latent36-IPA** from the completed run and extract the IPA.
4. Import into LiveContainer or SideStore; they supply signing.

On a Mac with Xcode: `bash scripts/build-ipa.sh`.

## Validation

CI executes the shared roll model against capacity limits, early-development rejection, explicit development start, the exact 24-hour boundary, extra-capture rejection, and JSON persistence, then compiles a Release iPhoneOS app. The packager checks for an arm64 Mach-O binary and correct iPhoneOS bundle before generating the IPA.

Physical camera, rendering appearance and LiveContainer execution require device testing. They cannot be verified by a Windows machine or a successful compiler result alone. See `PHONE-TEST.md` for the device checklist.
