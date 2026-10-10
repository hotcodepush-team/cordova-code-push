const { realpathSync, writeFileSync } = require('node:fs');
const { join } = require('node:path');
const xcode = require('xcode');

const APP_TARGET_NAME = 'App';

// The script reads the version and build from the built app's processed Info.plist: declared as the phase's input,
// Xcode processes the plist before it runs the phase.
const INFO_PLIST_INPUT_PATH = '"$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)"';

const PHASE_MARKER = 'binary-create-xcode.sh';

const PHASE_NAME = 'Create HotCodePush binary';

// The lines of the phase as a pbxproj string carries them, the line breaks escaped. The script runs from Cordova's copy
// of the plugin, two levels above the platform's Xcode project.
const PHASE_SCRIPT = [
  'set -e',
  '',
  "# hotcodepush: writes hotcodepush.json into the app's www",
  '/bin/sh "$SRCROOT/../../plugins/@hotcodepush/cordova-code-push/scripts/binary-create-xcode.sh"',
  '',
].join('\\n');

/**
 * The build step on iOS, run by Cordova after every prepare, the one `cordova platform add` runs included: Cordova has
 * no `plugin.xml` element for a build phase, so the hook adds the phase that runs the CLI to the generated Xcode
 * project. The hook runs for every platform and acts when iOS is among the prepared ones; `opts.cordova.platforms` is
 * no guide, as a fresh checkout's first prepare lists it before restoring the platforms.
 */
module.exports = function addBinaryCreatePhaseToPlatform(context) {
  if (!context.opts.platforms.includes('ios')) {
    return;
  }
  // cordova-ios keys the project it parses by the platform's real path, as the CLI resolves it
  addBinaryCreatePhase(
    realpathSync(join(context.opts.projectRoot, 'platforms', 'ios')),
  );
};

/**
 * Appends the run-script phase to the app target after its last phase, once the app's www is copied into the app; the
 * phase already there is left alone, so the hook runs on every prepare. The phase goes into the project cordova-ios
 * parsed: it keeps that project for the whole CLI run and writes it back at a signed build's signing step, which would
 * drop a phase written to the file alone.
 */
function addBinaryCreatePhase(platformRoot) {
  const locations = {
    pbxproj: join(platformRoot, 'App.xcodeproj', 'project.pbxproj'),
    root: platformRoot,
  };
  const cordovaProjectFile = requireCordovaProjectFile(platformRoot);
  const project = cordovaProjectFile
    ? cordovaProjectFile.parse(locations)
    : parseProjectFile(locations.pbxproj);
  if (hasBinaryCreatePhase(project.xcode)) {
    return;
  }
  if (!cordovaProjectFile) {
    console.warn(
      'HotCodePush: cordova-ios cannot be loaded from platforms/ios, so the Xcode phase goes into the project file alone and a signed build in the same run may drop it; run cordova prepare before it.',
    );
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
  // the CLI writes hotcodepush.json, which carries the build's time, on every build; a phase without outputs
  // that is not marked so makes Xcode warn
  buildPhase.alwaysOutOfDate = 1;
  project.write();
}

/**
 * cordova-ios's module that parses the project once per CLI run and writes it, resolved as the platform's Api.js
 * resolves cordova-ios, so the hook shares the CLI's instance; undefined when it cannot be loaded.
 */
function requireCordovaProjectFile(platformRoot) {
  try {
    return require(
      require.resolve('cordova-ios/lib/projectFile', {
        paths: [join(platformRoot, 'cordova')],
      }),
    );
  } catch {
    return undefined;
  }
}

/**
 * The project file parsed on its own, in the shape cordova-ios's parsed project has.
 */
function parseProjectFile(projectFilePath) {
  const project = xcode.project(projectFilePath).parseSync();
  return {
    write: () => writeFileSync(projectFilePath, project.writeSync()),
    xcode: project,
  };
}

function hasBinaryCreatePhase(project) {
  return Object.values(
    project.hash.project.objects.PBXShellScriptBuildPhase ?? {},
  ).some(phase => phase.shellScript?.includes(PHASE_MARKER));
}
