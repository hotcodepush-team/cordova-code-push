import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// The SDK version a device reports is package.json's version, written into each platform's sources by every build and
// never committed, so no release can leave it behind.

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
