#!/bin/sh
# Xcode Cloud post-clone hook for Meshline.
# Trusts the project's SwiftPM plugins/macros so non-interactive builds don't
# stop at the validation prompt, and prints the toolchain for build logs.
set -eu
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
xcodebuild -version
