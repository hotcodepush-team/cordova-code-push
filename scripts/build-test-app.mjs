import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// The check that the plugin compiles: a fresh Cordova app in a temporary directory, the platform at the version this
// repository pins, the plugin added from this checkout, and a debug build; the embed step is the CLI's and stays out.
// Usage: node scripts/build-test-app.mjs android|ios

const PLATFORMS = ['android', 'ios'];
const pluginDirectory = join(dirname(fileURLToPath(import.meta.url)), '..');
const cordova = join(pluginDirectory, 'node_modules', '.bin', 'cordova');
const [platform] = process.argv.slice(2);

if (!PLATFORMS.includes(platform)) {
  console.error('Usage: node scripts/build-test-app.mjs android|ios');
  process.exit(2);
}

const { devDependencies } = JSON.parse(
  readFileSync(join(pluginDirectory, 'package.json'), 'utf8'),
);
const appDirectory = join(
  mkdtempSync(join(tmpdir(), 'hotcodepush-cordova-')),
  'app',
);

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

try {
  run(['create', appDirectory, 'com.hotcodepush.verify', 'Verify']);
  if (platform === 'ios') {
    raiseIosDeploymentTarget();
  }
  run(
    [
      'platform',
      'add',
      `${platform}@${devDependencies[`cordova-${platform}`]}`,
    ],
    appDirectory,
  );
  run(['plugin', 'add', pluginDirectory], appDirectory);
  run(
    [
      'build',
      platform,
      '--debug',
      ...(platform === 'ios' ? ['--emulator'] : []),
      '--nohooks',
      'after_prepare',
    ],
    appDirectory,
  );
} finally {
  rmSync(dirname(appDirectory), { force: true, recursive: true });
}
