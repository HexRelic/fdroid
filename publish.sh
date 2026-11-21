#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 HexRelic
# Adds a released APK to this F-Droid repository, rebuilds and signs the index, and commits.
#
#   ./publish.sh /path/to/WitnessClip-0.1.0.apk /path/to/SHA256SUMS.txt
#
# The APK must be the one attached to the GitHub release: its hash is checked against the
# release's SHA256SUMS.txt, and fdroidserver refuses it unless its signing certificate is the
# one in metadata/*.yml (AllowedAPKSigningKeys).
set -euo pipefail
apk="${1:-}"; sums="${2:-}"
[ -f "$apk" ] && [ -f "$sums" ] || { echo "usage: ./publish.sh WitnessClip-x.y.z.apk SHA256SUMS.txt"; exit 2; }
cd "$(dirname "$0")"
[ -f config.yml ] || { echo "config.yml missing: run 'fdroid init' first (see README of this setup)"; exit 1; }

name="$(basename "$apk")"
want="$(awk -v n="$name" '$2 == n {print $1}' "$sums")"
have="$(sha256sum "$apk" | cut -d' ' -f1)"
[ -n "$want" ] || { echo "$name is not listed in $sums"; exit 1; }
[ "$want" = "$have" ] || { echo "Hash mismatch for $name: refusing"; exit 1; }
echo "== $name matches SHA256SUMS.txt"

cp "$apk" "repo/$name"
fdroid update --pretty

# Nothing from this machine may end up in the published files.
leak="$(grep -rIl -e "$USER" -e "$(hostname)" -e "/home/" repo/ metadata/ config/ README.md 2>/dev/null || true)"
[ -z "$leak" ] || { echo "Refusing to commit, local names found in:"; echo "$leak"; exit 1; }

sig="$(unzip -Z1 repo/entry.jar | grep -E '^META-INF/.*\.(RSA|EC|DSA)$' | head -n1)"
fp="$(unzip -p repo/entry.jar "$sig" \
      | openssl pkcs7 -inform DER -print_certs | openssl x509 -outform DER | sha256sum | cut -d' ' -f1)"
echo "== Repository fingerprint: $fp"

git add -A
TZ=UTC git commit -q -m "Publish ${name%.apk}"
git log -1 --format='== Committed %h %an %ad' --date=iso
echo "Now push: git push"
