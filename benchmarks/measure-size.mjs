#!/usr/bin/env node
// Measures the release APK and the Release simulator app of a prepared demo variant.
// Prints both sizes in bytes as JSON.
import { execFileSync } from 'node:child_process';
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const [target] = process.argv.slice(2);
if (!target) {
  console.error('usage: measure-size.mjs <prepared demo>');
  process.exit(2);
}

// A benchmark build is never shipped. Offline, the build step writes no channel and creates no binary,
// even if the machine holds a HotCodePush token.
const env = { ...process.env, HOTCODEPUSH_OFFLINE: '1' };

const sizes = {};
// The baseline weighs an APK, and a Cordova release build makes an app bundle by default.
build(['android', '--release', '--', '--packageType=apk']);
sizes.android = {
  releaseApkBytes: statSync(
    join(
      target,
      'platforms/android/app/build/outputs/apk/release/app-release.apk',
    ),
  ).size,
};
build(['ios', '--release', '--emulator']);
sizes.ios = {
  simulatorAppBytes: directorySize(
    join(
      target,
      'platforms/ios/build/Release-iphonesimulator/HotCodePush Demo.app',
    ),
  ),
};
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
