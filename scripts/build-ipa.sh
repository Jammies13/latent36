#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -version
xcodebuild -project Latent36.xcodeproj -scheme Latent36 -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build
python3 scripts/package-ipa.py
