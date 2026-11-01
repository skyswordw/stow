#!/usr/bin/env bash
# Repeated sandboxed create/verify/reopen/extract checks for #38's historical SIGTERM.
set -euo pipefail
cd "$(dirname "$0")/.."

rounds=${1:-20}
if [[ ! "$rounds" =~ ^[1-9][0-9]*$ ]] || (( rounds > 100 )); then
  echo "Usage: $0 [rounds: 1-100]" >&2
  exit 2
fi

mkdir -p build
run_dir=$(mktemp -d "$PWD/build/packing-stress.XXXXXX")
echo "Packing stress artifacts: $run_dir"
selector='StowTests/PackingTests/encryptedSplitVerifiedArchiveRoundTrips()'
common=(-project Stow.xcodeproj -scheme Stow -derivedDataPath build -destination platform=macOS)
if ! xcodebuild "${common[@]}" build-for-testing > "$run_dir/build.log" 2>&1; then
  tail -60 "$run_dir/build.log"
  exit 1
fi

# Swift Testing did not repeat this test with xcodebuild -test-iterations on the verified Xcode
# version. Use separate test runs, asserting a nonzero executed count for every result bundle.
for ((round = 1; round <= rounds; round++)); do
  result="$run_dir/round-$round.xcresult"
  if ! xcodebuild "${common[@]}" test-without-building "-only-testing:$selector" \
      -resultBundlePath "$result" > "$run_dir/round-$round.log" 2>&1; then
    tail -60 "$run_dir/round-$round.log"
    exit 1
  fi
  MIN_TESTS=1 ALLOWED_SKIPS=0 scripts/ci-assert-tests.sh "$result"
  echo "Packing round $round/$rounds passed"
done
