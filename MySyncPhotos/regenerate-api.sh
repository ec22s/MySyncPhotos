#!/usr/bin/env bash
# Regenerates Sources/MySyncPhotos/Generated/{Models,API}.swift from blocks.spec.json.
# Run after every backend API change:
#   (backend)  npm run spec && cp aws-blocks/blocks.spec.json ../MySyncPhotos/Sources/MySyncPhotos/
#   (ios)      ./regenerate-api.sh
set -euo pipefail

cd "$(dirname "$0")"

# Resolve the aws-blocks-swift checkout that Xcode / SwiftPM already downloaded.
PKG_DIR="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -type d -path "*SourcePackages/checkouts/aws-blocks-swift" 2>/dev/null | head -n 1)"

if [ -z "$PKG_DIR" ]; then
  echo "aws-blocks-swift checkout not found. Open the project in Xcode once so packages resolve." >&2
  exit 1
fi

mkdir -p Sources/MySyncPhotos/Generated
swift run --package-path "$PKG_DIR" swift-code-generator \
  "$PWD/Sources/MySyncPhotos/blocks.spec.json" \
  "$PWD/Sources/MySyncPhotos/Generated"

# Work around a swift-code-generator 0.1.1 bug: channel-returning methods are emitted as
#   public func getFeedChannel() async throws -> RealtimeChannel<ResultMessage>
# but the message type is nested, so it must be qualified:
#   ... -> RealtimeChannel<GetFeedChannel.ResultMessage>
# Only rewrites unqualified type arguments; a no-op once the generator is fixed.
perl -pi -e 's/public func (\w+)(\(.*?\) async throws -> RealtimeChannel<)([A-Z]\w*)>/"public func $1$2" . ucfirst($1) . ".$3>"/e' \
  "$PWD/Sources/MySyncPhotos/Generated/API.swift"
