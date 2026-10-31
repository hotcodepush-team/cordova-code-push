import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Every build writes the version and the files are never committed, so no release can ship a stale version.

const pluginDirectory = join(dirname(fileURLToPath(import.meta.url)), '..');
const { version } = JSON.parse(
  readFileSync(join(pluginDirectory, 'package.json'), 'utf8'),
);
const header = '// Written from package.json by scripts/write-sdk-version.mjs.';

writeFileSync(
  join(pluginDirectory, 'src/ios/SdkVersion.swift'),
  `${header}\nlet sdkVersion = ${JSON.stringify(version)}\n`,
);
writeFileSync(
  join(pluginDirectory, 'src/android/SdkVersion.kt'),
  `${header}\npackage com.hotcodepush.cordova\n\ninternal const val SDK_VERSION = ${JSON.stringify(version)}\n`,
);
