#!/usr/bin/env node
// Copies the demo app into a scratch directory as one of the two variants the baseline compares:
// `with` installs the plugin tarball, `without` removes the plugin, and with it its Gradle task and its Xcode phase,
// and swaps the screen's script for the same screen with nothing behind it. Both log the moment of their first paint.
// Neither is built here: the build step runs inside the native build, which the measuring scripts start.
import { execFileSync } from 'node:child_process';
import { cpSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [source, target, variant, tarball] = process.argv.slice(2);
if (
  !source ||
  !target ||
  !['with', 'without'].includes(variant) ||
  (variant === 'with' && !tarball)
) {
  console.error(
    'usage: prepare-demo.mjs <demo> <target> with <plugin.tgz> | without',
  );
  process.exit(2);
}

const pluginName = '@hotcodepush/cordova-code-push';
const excluded = new Set([
  'node_modules',
  'www',
  '.git',
  'platforms',
  'plugins',
]);
rmSync(target, { recursive: true, force: true });
cpSync(source, target, {
  recursive: true,
  filter: path => !excluded.has(path.split('/').pop()),
});

// The moment of the first frame, logged once `deviceready` has fired: Cordova hands the console to the host only
// after it loaded its plugins, which the first frame of an app with a plugin comes before.
const firstPaintMarker =
  "requestAnimationFrame(() => { const paintedAt = Date.now(); document.addEventListener('deviceready', () => console.log(`[baseline] first paint ${paintedAt}`)); });";
const versionLine = 'versionHeading.textContent = VERSION;';
const mainPath = join(target, 'src/main.ts');
if (variant === 'with') {
  writeFileSync(
    mainPath,
    readFileSync(mainPath, 'utf8').replace(
      versionLine,
      `${versionLine}\n${firstPaintMarker}`,
    ),
  );
  run('npm', ['install', '--save-dev', tarball, '--no-audit', '--no-fund']);
} else {
  run('npm', ['uninstall', pluginName, '--no-audit', '--no-fund']);
  const packagePath = join(target, 'package.json');
  const manifest = JSON.parse(readFileSync(packagePath, 'utf8'));
  delete manifest.cordova.plugins[pluginName];
  writeFileSync(packagePath, `${JSON.stringify(manifest, null, 2)}\n`);
  writeFileSync(
    mainPath,
    `// The demo without the plugin: the same screen, nothing behind it — the baseline's control.
const VERSION = 'v1';

const versionHeading = getElement('version');
const currentReleaseText = getElement('current-release');
const deviceIdText = getElement('device-id');
const lastSyncText = getElement('last-sync');
const syncButton = getElement<HTMLButtonElement>('sync-button');

${versionLine}
syncButton.addEventListener('click', () => undefined);
${firstPaintMarker}
currentReleaseText.textContent = 'embedded';
deviceIdText.textContent = 'none';
lastSyncText.textContent = 'none yet';

function getElement<T extends HTMLElement = HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(\`Missing element #\${id}\`);
  return element as T;
}
`,
  );
}
run('npm', ['install', '--no-audit', '--no-fund']);
run('npm', ['run', 'build']);
run('npx', ['cordova', 'prepare']);
console.log(`${variant}: ${target}`);

function run(command, args) {
  execFileSync(command, args, {
    cwd: target,
    stdio: ['ignore', 'ignore', 'inherit'],
  });
}
