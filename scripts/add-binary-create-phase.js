const { realpathSync } = require('node:fs');
const { join } = require('node:path');

const APP_TARGET_NAME = 'App';

// The script reads the version and build from the processed Info.plist.
// As the phase's input, Xcode processes the plist before it runs the phase.
const INFO_PLIST_INPUT_PATH = '"$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)"';

const PHASE_MARKER = 'binary-create-xcode.sh';

const PHASE_NAME = 'Create HotCodePush binary';

// A pbxproj string escapes its line breaks.
// Cordova copies the plugin to `plugins/`, two levels above the platform's Xcode project.
const PHASE_SCRIPT = [
  'set -e',
  '',
  "# hotcodepush: writes hotcodepush.json into the app's www",
  '/bin/sh "$SRCROOT/../../plugins/@hotcodepush/cordova-code-push/scripts/binary-create-xcode.sh"',
  '',
].join('\\n');

// `plugin.xml` has no element for a build phase, so this hook adds it after every prepare.
// It checks `opts.platforms`, because a fresh checkout's first prepare lists `opts.cordova.platforms` before restoring them.
module.exports = function addBinaryCreatePhaseToPlatform(context) {
  if (!context.opts.platforms.includes('ios')) {
    return;
  }
  // cordova-ios keys the parsed project by the platform's real path, as the CLI resolves it.
  addBinaryCreatePhase(
    realpathSync(join(context.opts.projectRoot, 'platforms', 'ios')),
  );
};

// The phase goes last, after Cordova copies www into the app.
// It goes into the project cordova-ios parsed, because cordova-ios writes that project back when it signs a build.
function addBinaryCreatePhase(platformRoot) {
  const locations = {
    pbxproj: join(platformRoot, 'App.xcodeproj', 'project.pbxproj'),
    root: platformRoot,
  };
  const project = requireCordovaProjectFile(platformRoot).parse(locations);
  if (hasBinaryCreatePhase(project.xcode)) {
    return;
  }
  const { buildPhase } = project.xcode.addBuildPhase(
    [],
    'PBXShellScriptBuildPhase',
    PHASE_NAME,
    project.xcode.findTargetKey(APP_TARGET_NAME),
    {
      inputPaths: [INFO_PLIST_INPUT_PATH],
      shellPath: '/bin/sh',
      shellScript: PHASE_SCRIPT,
    },
  );
  // The CLI writes hotcodepush.json with the build time on every build.
  // Xcode warns about a phase without outputs unless it is marked so.
  buildPhase.alwaysOutOfDate = 1;
  project.write();
}

// Resolved from the platform, as its Api.js resolves cordova-ios, so the hook shares the CLI's parsed project.
function requireCordovaProjectFile(platformRoot) {
  return require(
    require.resolve('cordova-ios/lib/projectFile', {
      paths: [join(platformRoot, 'cordova')],
    }),
  );
}

function hasBinaryCreatePhase(project) {
  return Object.values(
    project.hash.project.objects.PBXShellScriptBuildPhase ?? {},
  ).some(phase => phase.shellScript?.includes(PHASE_MARKER));
}
