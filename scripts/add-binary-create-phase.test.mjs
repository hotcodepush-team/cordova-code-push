import assert from 'node:assert/strict';
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, beforeEach, describe, it } from 'node:test';
import xcode from 'xcode';
import addBinaryCreatePhaseToPlatform from './add-binary-create-phase.js';

// The project `cordova platform add ios` generates, from the cordova-ios this repository builds against.
const TEMPLATE_PROJECT_FILE_PATH = join(
  import.meta.dirname,
  '..',
  'node_modules',
  'cordova-ios',
  'templates',
  'project',
  'App.xcodeproj',
  'project.pbxproj',
);

describe('add-binary-create-phase.js', () => {
  let projectFilePath;
  let projectRoot;

  beforeEach(() => {
    projectRoot = mkdtempSync(join(tmpdir(), 'add-binary-create-phase-'));
    projectFilePath = join(
      projectRoot,
      'platforms',
      'ios',
      'App.xcodeproj',
      'project.pbxproj',
    );
    mkdirSync(dirname(projectFilePath), { recursive: true });
    copyFileSync(TEMPLATE_PROJECT_FILE_PATH, projectFilePath);
  });

  afterEach(() => {
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
