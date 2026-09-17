# First phone test

1. Import the IPA in LiveContainer and launch full-screen. Allow Camera. If denied, enable Camera for the host in iOS Settings, then reopen. If it still fails, use a direct SideStore installation before taking a real roll.
2. Load Daylight. Check preview, tap focus, available lenses, zoom, EV, manual controls, flash, and timer. Switching lenses should reset controls; unavailable hardware controls should be disabled.
3. Take one photo. Wait for sealing to finish; the counter should say 1/36, with no preview. Close/reopen: it should still say 1/36.
4. Take a landscape photo to verify its orientation after development. Finish the roll. The 37th exposure must be disabled and Develop should become available.
5. Press Develop. The timer starts at 24 hours. Close/reopen; it must continue rather than restart. Load another stock and shoot while the first roll develops.
6. After the real 24-hour wait, open the first roll in Darkroom. Check orientation and the film look. Save one photo, granting Photos access; then save the roll if wanted. Repeated exports make duplicate copies.

If something fails, report: installation route (LiveContainer or direct SideStore), versions of iOS and LiveContainer/SideStore, selected lens, exact controls, and error text. Keep any failing installation until its photographs are exported. Do not delete its data to troubleshoot.

There is intentionally no production shortcut to bypass the 24-hour wait. CI tests the boundary using synthetic dates without capturing or revealing real photographs.
