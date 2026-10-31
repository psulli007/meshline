#!/bin/sh
# Xcode Cloud: stamp CFBundleVersion with the Xcode Cloud build number so every
# TestFlight upload is unique and increasing.
set -eu
if [ -n "${CI_BUILD_NUMBER:-}" ]; then
  sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER}/" "$CI_PRIMARY_REPOSITORY_PATH/Configs/Release.xcconfig"
  grep CURRENT_PROJECT_VERSION "$CI_PRIMARY_REPOSITORY_PATH/Configs/Release.xcconfig"
fi
