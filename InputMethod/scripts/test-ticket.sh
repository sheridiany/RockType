#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/roarkt-ticket.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  "$root/../Core/Voice/VoiceCommitTicket.swift" "$root/../Core/Voice/VoiceInsertionPolicy.swift" \
  "$root/tests/VoiceCommitTicketChecks.swift" -o "$temporary/check"
"$temporary/check"
