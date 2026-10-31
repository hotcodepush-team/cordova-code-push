import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, it } from 'node:test';

const APP_NAME = 'App.app';

// Xcode writes the processed Info.plist in binary format. The values are invented.
const PROCESSED_INFO_PLIST = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>2.4.1</string>
  <key>CFBundleVersion</key>
  <string>57</string>
</dict>
</plist>
`;

// Stands in for npx beside Node and records the arguments, one per line, instead of running the CLI.
const RECORDING_NPX =
  '#!/bin/sh\nprintf "%s\\n" "$@" > "$(dirname "$0")/arguments"\n';

const SCRIPT_PATH = join(import.meta.dirname, 'binary-create-xcode.sh');

// Xcode and PlistBuddy run only on macOS.
describe(
  'binary-create-xcode.sh',
  { skip: process.platform !== 'darwin' },
  () => {
    let appPath;
    let nodeDirectoryPath;
    let projectRoot;
    let sourceRoot;

    beforeEach(() => {
      projectRoot = mkdtempSync(join(tmpdir(), 'binary-create-xcode-'));
      sourceRoot = join(projectRoot, 'platforms', 'ios');
      mkdirSync(join(sourceRoot, 'www'), { recursive: true });
      appPath = join(sourceRoot, 'build', APP_NAME);
      mkdirSync(join(appPath, 'www'), { recursive: true });
      writeFileSync(join(appPath, 'Info.plist'), PROCESSED_INFO_PLIST);
      execFileSync('plutil', [
        '-convert',
        'binary1',
        join(appPath, 'Info.plist'),
      ]);
      nodeDirectoryPath = join(projectRoot, 'node', 'bin');
      mkdirSync(nodeDirectoryPath, { recursive: true });
      writeFileSync(join(nodeDirectoryPath, 'node'), '#!/bin/sh\n', {
        mode: 0o755,
      });
      writeFileSync(join(nodeDirectoryPath, 'npx'), RECORDING_NPX, {
        mode: 0o755,
      });
      mkdirSync(join(projectRoot, 'home'));
    });

    afterEach(() => {
      rmSync(projectRoot, { force: true, recursive: true });
    });

    it('should create the binary under the version and build of the processed Info.plist when the build is an archive', () => {
      assert.deepEqual(
        runScript({
          DEPLOYMENT_POSTPROCESSING: 'YES',
          PATH: `${nodeDirectoryPath}:/usr/bin:/bin`,
        }),
        [
          'hotcodepush',
          'binary',
          'create',
          '--binary-version',
          '2.4.1',
          '--binary-build',
          '57',
          '--platform',
          'ios',
          '--embedded-bundle-path',
          join(sourceRoot, 'www'),
          '--resource-file-path',
          join(appPath, 'www', 'hotcodepush.json'),
        ],
      );
    });

    it('should write the resource file alone when the build is not an archive', () => {
      assert.deepEqual(
        runScript({
          DEPLOYMENT_POSTPROCESSING: 'NO',
          PATH: `${nodeDirectoryPath}:/usr/bin:/bin`,
        }),
        [
          'hotcodepush',
          'resource-file',
          'write',
          '--platform',
          'ios',
          '--embedded-bundle-path',
          join(sourceRoot, 'www'),
          '--resource-file-path',
          join(appPath, 'www', 'hotcodepush.json'),
        ],
      );
    });

    it('should run the Node .xcode.env names when the PATH has none', () => {
      writeFileSync(
        join(sourceRoot, '.xcode.env'),
        `export NODE_BINARY=${join(nodeDirectoryPath, 'node')}\n`,
      );

      assert.equal(
        runScript({
          DEPLOYMENT_POSTPROCESSING: 'NO',
          PATH: '/usr/bin:/bin',
        })[0],
        'hotcodepush',
      );
    });

    it('should run the Node nvm selects when neither the PATH nor .xcode.env has one', () => {
      mkdirSync(join(projectRoot, 'home', '.nvm'));
      writeFileSync(
        join(projectRoot, 'home', '.nvm', 'nvm.sh'),
        `nvm() { PATH="${nodeDirectoryPath}:$PATH"; }\n`,
      );

      assert.equal(
        runScript({
          DEPLOYMENT_POSTPROCESSING: 'NO',
          PATH: '/usr/bin:/bin',
        })[0],
        'hotcodepush',
      );
    });

    it("should run the Node Homebrew's nvm selects on Intel, whose ~/.nvm holds no nvm.sh", () => {
      const homebrewPrefix = join(projectRoot, 'usr', 'local');
      mkdirSync(join(homebrewPrefix, 'opt', 'nvm'), { recursive: true });
      writeFileSync(
        join(homebrewPrefix, 'opt', 'nvm', 'nvm.sh'),
        `nvm() { PATH="${nodeDirectoryPath}:$PATH"; }\n`,
      );

      assert.equal(
        runScript({
          DEPLOYMENT_POSTPROCESSING: 'NO',
          HOMEBREW_PREFIX: homebrewPrefix,
          PATH: '/usr/bin:/bin',
        })[0],
        'hotcodepush',
      );
    });

    it("should run Homebrew's Node before the one nvm selects when neither the PATH nor .xcode.env has one", () => {
      const homebrewPrefix = join(projectRoot, 'opt', 'homebrew');
      mkdirSync(homebrewPrefix, { recursive: true });
      renameSync(nodeDirectoryPath, join(homebrewPrefix, 'bin'));
      nodeDirectoryPath = join(homebrewPrefix, 'bin');
      const nvmNodeDirectoryPath = join(projectRoot, 'nvm-node', 'bin');
      mkdirSync(nvmNodeDirectoryPath, { recursive: true });
      writeFileSync(join(nvmNodeDirectoryPath, 'node'), '#!/bin/sh\n', {
        mode: 0o755,
      });
      mkdirSync(join(projectRoot, 'home', '.nvm'));
      writeFileSync(
        join(projectRoot, 'home', '.nvm', 'nvm.sh'),
        `nvm() { PATH="${nvmNodeDirectoryPath}:$PATH"; }\n`,
      );

      assert.equal(
        runScript({
          DEPLOYMENT_POSTPROCESSING: 'NO',
          HOMEBREW_PREFIX: homebrewPrefix,
          PATH: '/usr/bin:/bin',
        })[0],
        'hotcodepush',
      );
    });

    function runScript(buildSettings) {
      execFileSync('/bin/sh', [SCRIPT_PATH], {
        env: {
          HOME: join(projectRoot, 'home'),
          // Keeps the machine's own Homebrew Node out of the lookup.
          HOMEBREW_PREFIX: join(projectRoot, 'no-homebrew'),
          INFOPLIST_PATH: join(APP_NAME, 'Info.plist'),
          SRCROOT: sourceRoot,
          TARGET_BUILD_DIR: join(sourceRoot, 'build'),
          UNLOCALIZED_RESOURCES_FOLDER_PATH: APP_NAME,
          ...buildSettings,
        },
      });
      return readFileSync(join(nodeDirectoryPath, 'arguments'), 'utf8')
        .trimEnd()
        .split('\n');
    }
  },
);
