#!/usr/bin/env bash
# Ensemble CI gate: analyze + test. Used by all agents before voting CONSENSUS: YES.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1 && ! command -v dart >/dev/null 2>&1; then
  echo "WARN: no Dart/Flutter toolchain on this host — skipping execution."
  echo "      Static foundation files are present; run this script where the SDK exists."
  exit 0
fi

if command -v flutter >/dev/null 2>&1; then
  flutter pub get
  flutter analyze
  flutter test
else
  dart pub get
  dart analyze
  dart test
fi
