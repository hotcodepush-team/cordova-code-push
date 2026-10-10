import { execFileSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// The check that the plugin compiles and its build step lands: a fresh Cordova app in a temporary directory, the
// platform at the version this repository pins or the one named, the plugin added from this checkout, both restored by
// `cordova prepare` as on a fresh clone of the app, a debug build, and hotcodepush.json in the built app's www; a
// stand-in for the CLI writes the file.
// Usage: node scripts/build-test-app.mjs android|ios [platform version]

const APP_NAME = 'Verify';

const PLATFORMS = ['android', 'ios'];
const pluginDirectory = join(dirname(fileURLToPath(import.meta.url)), '..');
const cordova = join(pluginDirectory, 'node_modules', '.bin', 'cordova');
const [platform, platformVersion] = process.argv.slice(2);

if (!PLATFORMS.includes(platform)) {
  console.error(
    'Usage: node scripts/build-test-app.mjs android|ios [platform version]',
  );
  process.exit(2);
}

const { devDependencies } = JSON.parse(
  readFileSync(join(pluginDirectory, 'package.json'), 'utf8'),
);
const appDirectory = join(
  mkdtempSync(join(tmpdir(), 'hotcodepush-cordova-')),
  'app',
);

// The CLI as the build step finds it through npx: it writes an empty resource file where it is told to.
const CLI_STAND_IN = `#!/usr/bin/env node
const { mkdirSync, writeFileSync } = require('node:fs');
const { dirname } = require('node:path');
const resourceFilePath = process.argv[process.argv.indexOf('--resource-file-path') + 1];
mkdirSync(dirname(resourceFilePath), { recursive: true });
writeFileSync(resourceFilePath, '{}');
`;

function run(args, cwd) {
  execFileSync(cordova, args, { cwd, stdio: 'inherit' });
}

/**
 * The oldest deployment target a current Xcode builds an app for; the plugin's own floor is in Package.swift.
 */
function raiseIosDeploymentTarget() {
  const configPath = join(appDirectory, 'config.xml');
  writeFileSync(
    configPath,
    readFileSync(configPath, 'utf8').replace(
      '</widget>',
      '    <preference name="deployment-target" value="15.0" />\n</widget>',
    ),
  );
}

/**
 * The app in the state a fresh clone of it is in: platforms and plugins are not committed, so the first
 * `cordova prepare`, naming no platform, restores them from package.json.
 */
function restoreAsFreshClone() {
  for (const directoryName of ['platforms', 'plugins']) {
    rmSync(join(appDirectory, directoryName), { recursive: true });
  }
  run(['prepare'], appDirectory);
}

function installCliStandIn() {
  const binDirectory = join(appDirectory, 'node_modules', '.bin');
  mkdirSync(binDirectory, { recursive: true });
  writeFileSync(join(binDirectory, 'hotcodepush'), CLI_STAND_IN, {
    mode: 0o755,
  });
}

function isResourceFileBuilt() {
  if (platform === 'ios') {
    return existsSync(
      join(
        appDirectory,
        'platforms/ios/build/Debug-iphonesimulator',
        `${APP_NAME}.app`,
        'www/hotcodepush.json',
      ),
    );
  }
  const apkPath = join(
    appDirectory,
    'platforms/android/app/build/outputs/apk/debug/app-debug.apk',
  );
  return execFileSync('unzip', ['-Z1', apkPath], { encoding: 'utf8' })
    .split('\n')
    .includes('assets/www/hotcodepush.json');
}

try {
  run(['create', appDirectory, 'com.hotcodepush.verify', APP_NAME]);
  if (platform === 'ios') {
    raiseIosDeploymentTarget();
  }
  run(
    [
      'platform',
      'add',
      `${platform}@${platformVersion ?? devDependencies[`cordova-${platform}`]}`,
    ],
    appDirectory,
  );
  run(['plugin', 'add', pluginDirectory], appDirectory);
  restoreAsFreshClone();
  installCliStandIn();
  // `compile`, not `build`: a build prepares the platform again, which would hide a build step the restore missed.
  run(
    [
      'compile',
      platform,
      '--debug',
      ...(platform === 'ios' ? ['--emulator'] : []),
    ],
    appDirectory,
  );
  if (!isResourceFileBuilt()) {
    console.error(`The ${platform} build has no www/hotcodepush.json.`);
    process.exitCode = 1;
  }
} finally {
  rmSync(dirname(appDirectory), { force: true, recursive: true });
}
