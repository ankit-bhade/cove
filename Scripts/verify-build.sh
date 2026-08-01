#!/bin/zsh

# Everything that can be checked without a person watching the app run.
# Cove is a personal app — there is no store submission, no archive, and no
# signing gate. What is left is what actually protects the vault: the app
# stays offline, it never logs the user's own content, both platforms build
# clean, and the suite passes.
#
# For runtime behavior (the parts a build cannot prove), use the `verify`
# skill, which launches the real app on the Simulator and on macOS.

set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
derived_data=${TMPDIR:-/tmp}/cove-verify

cd "$repo_root"

fail() {
  print -u2 "Verification failed: $1"
  exit 1
}

# A gate that cannot run has to fail, not pass. `if grep ...; then` treats a
# missing binary's 127 exactly like "no matches", so an absent tool would
# turn every content check below into a silent success and still print
# "passed" at the end. This script used to call `rg`, which exists on this
# machine only as an interactive shell function and was therefore never
# actually running in a script. Everything below uses POSIX grep instead.
for tool in grep plutil xcodebuild xcrun; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done
xcrun swift-format --version >/dev/null 2>&1 \
  || fail "swift-format is unavailable through xcrun"

# `status` is read-only in zsh (it aliases `?`), hence `rc`.
# grep exits 1 for "no matches" and 2 for a real error; only 1 is a pass.
scan() {
  local description=$1
  shift
  local output rc
  output=$(grep "$@") && rc=0 || rc=$?
  case $rc in
    0)
      print -r -- "$output"
      fail "$description"
      ;;
    1) ;;
    *) fail "the $description scan could not run (grep exit $rc)" ;;
  esac
}

plutil -lint \
  Info.plist \
  CoveWidgets-Info.plist \
  Cove/Cove.entitlements \
  Cove/Cove-iOS.entitlements \
  CoveWidgets/CoveWidgets.entitlements

# `--strict` is what makes this a gate. Without it swift-format reports its
# findings as warnings and still exits 0, so the step printed a wall of
# complaints and passed anyway — 28 of them had accumulated, unnoticed,
# because every other check in this script fails hard and this one only
# looked like it did.
xcrun swift-format lint --strict --configuration .swift-format \
  --recursive Cove CoveWidgets Tests

# The filesystem is the source of truth and nothing leaves the device. That
# is a fixed rule, so it is worth enforcing mechanically rather than trusting
# that nobody reached for URLSession during a debugging session.
network_pattern='URLSession|URLRequest|NSURLConnection|CFNetwork|NWConnection|import[[:space:]]+Network|WKWebView|SFSafariViewController|socket[(]|connect[(]|getaddrinfo[(]|https?://|websocket|Firebase|Crashlytics|Sentry|Mixpanel|Amplitude|telemetry|analytics'
scan "application networking, analytics, or telemetry reference found" \
  -rEn -i --include='*.swift' "$network_pattern" Cove CoveWidgets

# Filenames and note text are the user's own content. `.public` puts them in
# the system log, where other processes on the machine can read them.
scan "public log interpolation found; Cove requires private/default log privacy" \
  -rEn --include='*.swift' 'privacy:[[:space:]]*[.]public' Cove CoveWidgets

scan "network entitlement found" \
  -En 'com[.]apple[.]security[.]network[.](client|server)' \
  Cove/Cove.entitlements Cove/Cove-iOS.entitlements \
  CoveWidgets/CoveWidgets.entitlements

xcodebuild \
  -project Cove.xcodeproj \
  -scheme Cove \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data/macos-tests" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  test

# The widget only compiles on iOS, and it compiles a different subset of
# `Cove/` than the app does. A shared file that gains a dependency the widget
# target doesn't have breaks here and nowhere else, so the macOS build above
# is not evidence this one works.
xcodebuild \
  -project Cove.xcodeproj \
  -scheme Cove \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data/ios-release" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  build

xcodebuild \
  -project Cove.xcodeproj \
  -scheme Cove \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data/macos-release" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  build

print "Verification passed."
