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

# Tries nvm, fnm, Volta, asdf and Homebrew in turn, where a Mac's Node usually comes from.
find_node() {
  NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh" --no-use
    nvm use > /dev/null 2>&1 || nvm use default > /dev/null 2>&1 || true
    if has_node; then return; fi
  fi
  for FNM_BINARY in "$HOME/.fnm/fnm" /opt/homebrew/bin/fnm /usr/local/bin/fnm; do
    if [ -x "$FNM_BINARY" ]; then
      eval "$("$FNM_BINARY" env)"
      if has_node; then return; fi
    fi
  done
  for NODE_DIRECTORY in "$HOME/.volta/bin" "${ASDF_DATA_DIR:-$HOME/.asdf}/shims" /opt/homebrew/bin /usr/local/bin; do
    if [ -x "$NODE_DIRECTORY/node" ]; then
      PATH="$NODE_DIRECTORY:$PATH"
      return
    fi
  done
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
