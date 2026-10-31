#!/usr/bin/env node
// Measures the cold start of a prepared demo variant, from launch to the first paint the demo logs.
// Prints the median of N fresh-install launches per platform as JSON.
import { execFileSync, spawn } from 'node:child_process';
import { join } from 'node:path';

const args = process.argv.slice(2);
const target = args[0];
const option = name => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
};
const runs = Number(option('--runs') ?? 5);
const androidSerial = option('--android');
const iosUdid = option('--ios');
if (!target || (!androidSerial && !iosUdid)) {
  console.error(
    'usage: measure-cold-start.mjs <prepared demo> [--android <serial>] [--ios <udid>] [--runs 5]',
  );
  process.exit(2);
}
const bundleId = 'com.hotcodepush.demo.cordova';
// A benchmark build is never shipped: offline, the build step writes the resource file without a channel.
const env = { ...process.env, HOTCODEPUSH_OFFLINE: '1' };
const marker = /\[baseline\] first paint (\d+)/;

const result = {};
if (androidSerial) result.android = await measureAndroid();
if (iosUdid) result.ios = await measureIos();
console.log(JSON.stringify(result));

async function measureAndroid() {
  const apk = join(
    target,
    'platforms/android/app/build/outputs/apk/debug/app-debug.apk',
  );
  build(['android', '--debug']);
  // A fresh install: state an earlier install left would make the first launch reload the embedded bundle.
  adb('uninstall', bundleId);
  adb('install', apk);
  const samples = [];
  for (let run = 0; run < runs; run++) {
    adb('shell', 'am', 'force-stop', bundleId);
    await waitFor(() => adb('shell', 'pidof', bundleId).trim() === '');
    adb('logcat', '-c');
    await sleep(1500);
    adb('shell', 'am', 'start', '-n', `${bundleId}/.MainActivity`);
    const lines = await waitForLog(
      () => adb('logcat', '-d', '-v', 'epoch'),
      marker,
    );
    const started = epochOf(
      lines.find(line =>
        /ActivityTaskManager: START u0 .*cmp=com\.hotcodepush\.demo\.cordova/.test(
          line,
        ),
      ),
    );
    samples.push(Math.round(paintedAtOf(lines.join('\n')) - started));
  }
  return summarize(samples);
}

async function measureIos() {
  // Debug builds send the web view console to the process output.
  // The launch reads it through a pseudo-terminal, because a pipe buffers the output until the process exits.
  build(['ios', '--debug', '--emulator']);
  simctl('uninstall', iosUdid, bundleId);
  simctl(
    'install',
    iosUdid,
    join(
      target,
      'platforms/ios/build/Debug-iphonesimulator/HotCodePush Demo.app',
    ),
  );
  const samples = [];
  for (let run = 0; run < runs; run++) {
    simctl('terminate', iosUdid, bundleId);
    await sleep(1500);
    const launchedAt = Date.now();
    const console = spawn('xcrun', [
      'simctl',
      'launch',
      '--console-pty',
      iosUdid,
      bundleId,
    ]);
    let output = '';
    let paintedAt = null;
    const read = chunk => {
      output += chunk;
      if (paintedAt === null && marker.test(output)) {
        paintedAt = paintedAtOf(output);
      }
    };
    console.stdout.on('data', read);
    console.stderr.on('data', read);
    await waitFor(() => paintedAt !== null);
    console.kill();
    samples.push(paintedAt - launchedAt);
  }
  simctl('terminate', iosUdid, bundleId);
  return summarize(samples);
}

function build(buildArgs) {
  execFileSync('npx', ['cordova', 'build', ...buildArgs], {
    cwd: target,
    env,
    stdio: ['ignore', 'ignore', 'inherit'],
  });
}

function summarize(samples) {
  const sorted = [...samples].sort((a, b) => a - b);
  return { medianMs: sorted[Math.floor(sorted.length / 2)], runsMs: samples };
}

function adb(...commandArgs) {
  try {
    return execFileSync('adb', ['-s', androidSerial, ...commandArgs], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'inherit'],
      timeout: 60_000,
    });
  } catch (error) {
    // `pidof` exits with 1 when no process runs, and `uninstall` fails when the app is missing.
    // Both are the state the caller waits for.
    if (commandArgs[1] === 'pidof' || commandArgs[0] === 'uninstall') return '';
    throw error;
  }
}

function simctl(...commandArgs) {
  try {
    return execFileSync('xcrun', ['simctl', ...commandArgs], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    return '';
  }
}

// The simulator shares the host clock, so this time compares with `Date.now()`.
function paintedAtOf(text) {
  const match = marker.exec(text);
  if (!match) throw new Error('the first paint was not logged');
  return Number(match[1]);
}

function epochOf(line) {
  if (!line) throw new Error('the expected log line did not appear');
  return Number(line.trim().split(/\s+/)[0]) * 1000;
}

async function waitForLog(read, pattern) {
  for (let attempt = 0; attempt < 80; attempt++) {
    const text = read();
    if (pattern.test(text)) return text.split('\n');
    await sleep(500);
  }
  throw new Error(`no line matching ${pattern} within 40 seconds`);
}

async function waitFor(predicate) {
  for (let attempt = 0; attempt < 120; attempt++) {
    if (predicate()) return;
    await sleep(250);
  }
  throw new Error('the first paint did not appear within 30 seconds');
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
