#!/bin/sh
# The build step of the Xcode build, run by the "Create HotCodePush binary" phase the plugin's hook adds to the app
# target: the CLI hashes the platform's www, which Cordova's prepare copied, writes hotcodepush.json into the app's www
# and, in a store build, creates the binary. The phase holds one line; what it runs lives here.
set -e

PROJECT_ROOT="$SRCROOT/../.."
# The built app's www, where the target builds its product: an archive installs it apart from the configuration's directory.
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/www"

# The store build is an archive, which Xcode marks with DEPLOYMENT_POSTPROCESSING, the setting behind "Run script only
# when installing": it creates the binary under the version and build the device reports, from the built app's processed
# Info.plist, where Cordova's version and build arrive. A Run or a plain build writes the resource file alone.
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

# The first of nvm, fnm, Volta, asdf and Homebrew that has a node, the places a Mac's Node usually comes from.
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

# Xcode's PATH has no Node. The Xcode project's .xcode.env names it, as React Native's does, .xcode.env.local over it;
# a build started from a shell has it on the PATH already.
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
