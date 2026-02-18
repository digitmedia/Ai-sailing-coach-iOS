#!/bin/bash
set -euo pipefail

# Only run setup in remote (web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

echo "AI Sailing Coach - Session start hook"
echo "Project: Swift/iOS app (no external package managers)"
echo "Build requires: macOS + Xcode 15+ (not available in web sessions)"
echo "Session ready."
