#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Latent36.xcodeproj -scheme Latent36 -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/Simulator \
  CODE_SIGNING_ALLOWED=NO build > build/simulator-build.log 2>&1 || { tail -80 build/simulator-build.log; exit 1; }
xcrun simctl list devices available -j > build/devices.json
SIM_ID=$(python3 - <<'PY'
import json
data=json.load(open('build/devices.json'))
devices=[d for values in data['devices'].values() for d in values if 'iPhone' in d['name'] and d.get('isAvailable',False)]
assert devices, 'No iPhone simulator available'
preferred=next((d for d in devices if d['name']=='iPhone 16 Pro'), devices[0])
print(preferred['udid'])
PY
)
xcrun simctl boot "$SIM_ID" || true
xcrun simctl bootstatus "$SIM_ID" -b
xcrun simctl install "$SIM_ID" build/Simulator/Build/Products/Debug-iphonesimulator/Latent36.app
xcrun simctl launch "$SIM_ID" com.jammies13.latent36
sleep 5
mkdir -p build/screenshots
xcrun simctl io "$SIM_ID" screenshot build/screenshots/camera-simulator.png
xcrun simctl terminate "$SIM_ID" com.jammies13.latent36
xcrun simctl launch "$SIM_ID" com.jammies13.latent36 --show-film-picker
sleep 4
xcrun simctl io "$SIM_ID" screenshot build/screenshots/film-picker-simulator.png
xcrun simctl terminate "$SIM_ID" com.jammies13.latent36
echo 'Simulator launches completed. A physical camera/LiveContainer test is still required.'
