const { readFileSync, writeFileSync } = require('node:fs');
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
 * The build step on iOS, run by Cordova after the platform is added and after every prepare: Cordova has no
 * `plugin.xml` element for a build phase, so the hook adds the phase that runs the CLI to the generated Xcode project.
 */
module.exports = function addBinaryCreatePhaseToPlatform(context) {
  addBinaryCreatePhase(
    join(
      context.opts.projectRoot,
      'platforms',
      'ios',
      'App.xcodeproj',
      'project.pbxproj',
    ),
  );
};

/**
 * Appends the run-script phase to the app target after its last phase, once the app's www is copied into the app; the
 * phase already there is left alone, so the hook runs on every prepare.
 */
function addBinaryCreatePhase(projectFilePath) {
  if (readFileSync(projectFilePath, 'utf8').includes(PHASE_MARKER)) {
    return;
  }
  const project = xcode.project(projectFilePath).parseSync();
  const { buildPhase } = project.addBuildPhase(
    [],
    'PBXShellScriptBuildPhase',
    PHASE_NAME,
    project.findTargetKey(APP_TARGET_NAME),
    {
      inputPaths: [INFO_PLIST_INPUT_PATH],
      shellPath: '/bin/sh',
      shellScript: PHASE_SCRIPT,
    },
  );
  // the CLI writes hotcodepush.json, which carries the build's time, on every build; a phase without outputs
  // that is not marked so makes Xcode warn
  buildPhase.alwaysOutOfDate = 1;
  writeFileSync(projectFilePath, project.writeSync());
}
