#!/bin/sh
# Run by the "Create HotCodePush binary" phase that the plugin's hook adds to the app target.
# Writes hotcodepush.json into the built app's www and, in a store build, creates the binary.
set -e

PROJECT_ROOT="$SRCROOT/../.."
# An archive installs the product outside the configuration's build directory, so the path follows TARGET_BUILD_DIR.
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/www"

# Xcode sets DEPLOYMENT_POSTPROCESSING for an archive, which is the store build.
# The processed Info.plist holds the version and build that the device reports.
if [ "$DEPLOYMENT_POSTPROCESSING" = "YES" ]; then
  INFO_PLIST="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
  BINARY_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
  BINARY_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
  set -- binary create --binary-version "$BINARY_VERSION" --binary-build "$BINARY_BUILD"
else
  set -- resource-file write
fi

has_node() {
  command -v node > /dev/null 2>&1
}

# HOMEBREW_PREFIX overrides the default prefixes of Apple silicon and Intel Macs.
homebrew_paths() {
  for HOMEBREW in ${HOMEBREW_PREFIX:-/opt/homebrew /usr/local}; do
    echo "$HOMEBREW/$1"
  done
}

# Tries Homebrew, then nvm, fnm, Volta and asdf in turn, where a Mac's Node usually comes from.
find_node() {
  for NODE_DIRECTORY in $(homebrew_paths bin); do
    if use_node_directory "$NODE_DIRECTORY"; then return; fi
  done
  NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  for NVM_SCRIPT in "$NVM_DIR/nvm.sh" $(homebrew_paths opt/nvm/nvm.sh); do
    if [ -s "$NVM_SCRIPT" ]; then
      export NVM_DIR
      . "$NVM_SCRIPT" --no-use
      nvm use >/dev/null 2>&1 || nvm use default >/dev/null 2>&1 || true
      if has_node; then return; fi
      break
    fi
  done
  for FNM in "$(command -v fnm || true)" "$HOME/.fnm/fnm" "$HOME/Library/Application Support/fnm/fnm" $(homebrew_paths bin/fnm); do
    if [ -x "$FNM" ]; then
      eval "$("$FNM" env --shell bash)"
      if has_node; then return; fi
      break
    fi
  done
  for NODE_DIRECTORY in "${VOLTA_HOME:-$HOME/.volta}/bin" "${ASDF_DATA_DIR:-$HOME/.asdf}/shims"; do
    if use_node_directory "$NODE_DIRECTORY"; then return; fi
  done
}

use_node_directory() {
  [ -x "$1/node" ] || return 1
  PATH="$1:$PATH"
}

cd "$PROJECT_ROOT"

# Xcode's PATH has no Node. As in React Native, .xcode.env names it and .xcode.env.local overrides that.
NODE_BINARY=$(command -v node || true)
if [ -f "$SRCROOT/.xcode.env" ]; then . "$SRCROOT/.xcode.env"; fi
if [ -f "$SRCROOT/.xcode.env.local" ]; then . "$SRCROOT/.xcode.env.local"; fi
if [ -n "$NODE_BINARY" ]; then
  PATH="$(dirname "$NODE_BINARY"):$PATH"
else
  find_node
fi
export PATH
if ! has_node; then
  echo "error: HotCodePush found no Node for its build step; name it in $SRCROOT/.xcode.env: export NODE_BINARY=/path/to/node" >&2
  exit 1
fi

npx hotcodepush "$@" \
  --platform ios \
  --embedded-bundle-path "$SRCROOT/www" \
  --resource-file-path "$DEST/hotcodepush.json"
