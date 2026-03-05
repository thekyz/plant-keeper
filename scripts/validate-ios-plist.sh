#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_PLIST="$ROOT_DIR/Config/iOS/AppBundleTemplate.plist"
STATIC_PLIST="$ROOT_DIR/Config/iOS/Info.plist"
REQUIRED_KEYS=(
  "NSCameraUsageDescription"
  "NSPhotoLibraryUsageDescription"
  "NSLocationWhenInUseUsageDescription"
)

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

read_plist_value() {
  local plist_path="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null
}

validate_plist() {
  local plist_path="$1"
  local label="$2"
  local errors=0

  if ! plutil -lint "$plist_path" >/dev/null; then
    echo "ERROR: $label is not a valid plist: $plist_path"
    return 1
  fi

  for key in "${REQUIRED_KEYS[@]}"; do
    local value
    value="$(read_plist_value "$plist_path" "$key" || true)"
    value="$(trim "$value")"
    if [[ -z "$value" ]]; then
      echo "ERROR: $label is missing a non-empty '$key'."
      errors=1
    fi
  done

  return "$errors"
}

if ! validate_plist "$TEMPLATE_PLIST" "Config/iOS/AppBundleTemplate.plist"; then
  exit 1
fi

if ! validate_plist "$STATIC_PLIST" "Config/iOS/Info.plist"; then
  exit 1
fi

for key in "${REQUIRED_KEYS[@]}"; do
  template_value="$(trim "$(read_plist_value "$TEMPLATE_PLIST" "$key")")"
  static_value="$(trim "$(read_plist_value "$STATIC_PLIST" "$key")")"
  if [[ "$template_value" != "$static_value" ]]; then
    echo "ERROR: '$key' differs between AppBundleTemplate.plist and Info.plist."
    echo "  template: $template_value"
    echo "  info:     $static_value"
    exit 1
  fi
done

echo "iOS plist validation passed."
