#!/usr/bin/env node
// The binary size of a prepared demo variant: the release APK, signed with the debug keystore the demo's build.json
// names, and the Release simulator `.app`, each in bytes, printed as JSON. `--android-only` skips the Xcode build on a
// runner without one.
import { execFileSync } from 'node:child_process';
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const [target, ...flags] = process.argv.slice(2);
if (!target) {
  console.error('usage: measure-size.mjs <prepared demo> [--android-only]');
  process.exit(2);
}

// A benchmark build is never shipped: offline, the build step writes the resource file without a channel and the
// release build creates no binary, whether or not the machine holds a HotCodePush token.
const env = { ...process.env, HOTCODEPUSH_OFFLINE: '1' };

const sizes = {};
// Cordova's release build is an app bundle unless it is asked for the APK the baseline weighs.
build(['android', '--release', '--', '--packageType=apk']);
sizes.android = {
  releaseApkBytes: statSync(
    join(
      target,
      'platforms/android/app/build/outputs/apk/release/app-release.apk',
    ),
  ).size,
};
if (!flags.includes('--android-only')) {
  build(['ios', '--release', '--emulator']);
  sizes.ios = {
    simulatorAppBytes: directorySize(
      join(
        target,
        'platforms/ios/build/Release-iphonesimulator/HotCodePush Demo.app',
      ),
    ),
  };
}
console.log(JSON.stringify(sizes));

function build(args) {
  execFileSync('npx', ['cordova', 'build', ...args], {
    cwd: target,
    env,
    stdio: ['ignore', 'ignore', 'inherit'],
  });
}

function directorySize(directory) {
  return readdirSync(directory, { withFileTypes: true }).reduce(
    (total, entry) => {
      const path = join(directory, entry.name);
      return (
        total +
        (entry.isDirectory() ? directorySize(path) : statSync(path).size)
      );
    },
    0,
  );
}
