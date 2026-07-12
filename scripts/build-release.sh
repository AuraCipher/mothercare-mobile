#!/usr/bin/env bash
# Build release APK/AAB with production API URL baked in at compile time.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFINES="${1:-$ROOT/dart_defines/production.json}"

if [[ ! -f "$DEFINES" ]]; then
  echo "Missing dart-defines file: $DEFINES"
  echo "Copy dart_defines/production.example.json → dart_defines/production.json and set API_BASE_URL."
  exit 1
fi

cd "$ROOT"
flutter pub get

echo "=== Building release App Bundle (Play Store) ==="
flutter build appbundle --release --dart-define-from-file="$DEFINES"

echo "=== Building release APK (side-load / testing) ==="
flutter build apk --release --dart-define-from-file="$DEFINES"

echo "Done."
echo "  AAB: build/app/outputs/bundle/release/app-release.aab"
echo "  APK: build/app/outputs/flutter-apk/app-release.apk"
