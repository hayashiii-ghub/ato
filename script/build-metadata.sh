#!/usr/bin/env bash
# Sourced by build.sh before building or modifying dist.
APP_VERSION="${APP_VERSION-0.1.0}"
APP_BUILD="${APP_BUILD-1}"
CONFIGURATION="${CONFIGURATION-release}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY--}"
SOURCE_REVISION="${SOURCE_REVISION-$(git rev-parse HEAD)}"

metadata_error() { printf 'Build metadata: %s\n' "$1" >&2; exit 1; }
[[ "$APP_VERSION" =~ ^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})$ ]] || \
  metadata_error 'APP_VERSION must have three numeric components (for example 0.1.1).'
[[ "$APP_BUILD" =~ ^[1-9][0-9]{0,3}$ ]] || \
  metadata_error 'APP_BUILD must be an integer from 1 to 9999.'
[[ "$CONFIGURATION" == release || "$CONFIGURATION" == debug ]] || \
  metadata_error 'CONFIGURATION must be release or debug.'
source "$(dirname "${BASH_SOURCE[0]}")/sparkle.sh"
usage_load_sparkle_configuration "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" "$CONFIGURATION" || exit 1
[[ "$SOURCE_REVISION" =~ ^[0-9a-fA-F]{40}$ ]] || \
  metadata_error 'SOURCE_REVISION must be the full 40-character HEAD commit hash.'
SOURCE_REVISION="$(printf '%s' "$SOURCE_REVISION" | tr '[:upper:]' '[:lower:]')"
[[ "$SOURCE_REVISION" == "$(git rev-parse HEAD)" ]] || \
  metadata_error 'SOURCE_REVISION must match the checked-out HEAD.'
SOURCE_DIRTY=false
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] || SOURCE_DIRTY=true

SIGNING_ARGS=(--force --sign "$CODE_SIGN_IDENTITY")
if [[ "$CODE_SIGN_IDENTITY" != - ]]; then
  [[ "$CODE_SIGN_IDENTITY" =~ ^[0-9a-fA-F]{40}$ ]] || \
    metadata_error 'CODE_SIGN_IDENTITY must be - or an installed Developer ID Application SHA-1 hash.'
  CODE_SIGN_IDENTITY="$(printf '%s' "$CODE_SIGN_IDENTITY" | tr '[:lower:]' '[:upper:]')"
  security find-identity -p codesigning -v | \
    awk -v identity="$CODE_SIGN_IDENTITY" '$2 == identity && /"Developer ID Application:/ { found=1 } END { exit !found }' || \
    metadata_error 'The selected valid Developer ID Application signing identity is not installed.'
  SIGNING_ARGS=(--force --sign "$CODE_SIGN_IDENTITY" --options runtime --timestamp)
fi
