import assert from 'node:assert/strict';
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, beforeEach, describe, it } from 'node:test';
import cordovaProjectFile from 'cordova-ios/lib/projectFile.js';
import xcode from 'xcode';
import addBinaryCreatePhaseToPlatform from './add-binary-create-phase.js';

// The cordova-ios this repository builds against, which the test app's platform resolves as an app's platform does.
const CORDOVA_IOS_PATH = join(
  import.meta.dirname,
  '..',
  'node_modules',
  'cordova-ios',
);

// The project `cordova platform add ios` generates, from that cordova-ios.
const TEMPLATE_PATH = join(CORDOVA_IOS_PATH, 'templates', 'project');

describe('add-binary-create-phase.js', () => {
  let platformRoot;
  let projectFilePath;
  let projectRoot;

  beforeEach(() => {
    projectRoot = mkdtempSync(join(tmpdir(), 'add-binary-create-phase-'));
    platformRoot = join(projectRoot, 'platforms', 'ios');
    projectFilePath = join(platformRoot, 'App.xcodeproj', 'project.pbxproj');
    for (const path of ['App.xcodeproj/project.pbxproj', 'App/config.xml']) {
      mkdirSync(dirname(join(platformRoot, path)), { recursive: true });
      copyFileSync(join(TEMPLATE_PATH, path), join(platformRoot, path));
    }
    mkdirSync(join(projectRoot, 'node_modules'));
    symlinkSync(
      CORDOVA_IOS_PATH,
      join(projectRoot, 'node_modules', 'cordova-ios'),
    );
  });

  afterEach(() => {
    cordovaProjectFile.purgeProjectFileCache(realpathSync(platformRoot));
    rmSync(projectRoot, { force: true, recursive: true });
  });

  it('should append the phase to the app target after its last phase, with the processed Info.plist as its input', () => {
    const templatePhaseNames = readPhases(projectFilePath).map(
      ({ name }) => name,
    );

    addBinaryCreatePhaseToPlatform({
      opts: { platforms: ['ios'], projectRoot },
    });

    const phases = readPhases(projectFilePath);
    assert.deepEqual(
      phases.map(({ name }) => name),
      [...templatePhaseNames, 'Create HotCodePush binary'],
    );
    const { phase } = phases.at(-1);
    assert.deepEqual(phase.inputPaths, [
      '"$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)"',
    ]);
    assert.equal(phase.alwaysOutOfDate, 1);
    assert.match(
      phase.shellScript,
      /\/bin\/sh \\"\$SRCROOT\/\.\.\/\.\.\/plugins\/@hotcodepush\/cordova-code-push\/scripts\/binary-create-xcode\.sh\\"/,
    );
  });

  it('should keep the phase when cordova-ios writes the project it parsed before the hook, as a signed build does', () => {
    // the locations cordova-ios's build parses the project at, under the platform's real path, as the CLI resolves it
    const locations = {
      pbxproj: realpathSync(projectFilePath),
      root: realpathSync(platformRoot),
    };
    // prepare parses the project before the hook runs, and a signed build's signing step writes it back after
    cordovaProjectFile.parse(locations);

    addBinaryCreatePhaseToPlatform({
      opts: { platforms: ['ios'], projectRoot },
    });
    const project = cordovaProjectFile.parse(locations);
    project.xcode.updateBuildProperty('CODE_SIGN_STYLE', 'Manual');
    project.write();

    assert.equal(
      readPhases(projectFilePath).at(-1).name,
      'Create HotCodePush binary',
    );
  });

  it('should append the phase to the project file, with a warning, when cordova-ios cannot be loaded from the platform', t => {
    rmSync(join(projectRoot, 'node_modules'), { recursive: true });
    const warn = t.mock.method(console, 'warn', () => {});

    addBinaryCreatePhaseToPlatform({
      opts: { platforms: ['ios'], projectRoot },
    });

    assert.equal(
      readPhases(projectFilePath).at(-1).name,
      'Create HotCodePush binary',
    );
    assert.equal(warn.mock.callCount(), 1);
  });

  it('should leave the project as it is when the phase is there', () => {
    addBinaryCreatePhaseToPlatform({
      opts: { platforms: ['ios'], projectRoot },
    });
    const projectWithPhase = readFileSync(projectFilePath, 'utf8');

    addBinaryCreatePhaseToPlatform({
      opts: { platforms: ['ios'], projectRoot },
    });

    assert.equal(readFileSync(projectFilePath, 'utf8'), projectWithPhase);
  });

  it('should leave the project as it is when iOS is not among the prepared platforms', () => {
    const templateProject = readFileSync(projectFilePath, 'utf8');

    addBinaryCreatePhaseToPlatform({
      opts: { platforms: ['android'], projectRoot },
    });

    assert.equal(readFileSync(projectFilePath, 'utf8'), templateProject);
  });
});

/**
 * The app target's build phases in their order, each with its name and its object.
 */
function readPhases(projectFilePath) {
  const project = xcode.project(projectFilePath).parseSync();
  const objects = project.hash.project.objects;
  const target = objects.PBXNativeTarget[project.findTargetKey('App')];
  return target.buildPhases.map(({ comment, value }) => ({
    name: comment,
    phase: Object.values(objects)
      .map(section => section[value])
      .find(phase => phase !== undefined),
  }));
}
