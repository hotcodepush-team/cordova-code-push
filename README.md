# Cordova code push by HotCodePush

`@hotcodepush/cordova-code-push` is the Cordova plugin that delivers over-the-air updates to your app: a code push reaches installed apps in seconds, without a store review. Learn more at [hotcodepush.com/cordova-code-push](https://hotcodepush.com/cordova-code-push).

## Installation

Until the package is published, add the preview build pkg.pr.new publishes for every commit on `main`, pinned to a commit:

```sh
cordova plugin add https://pkg.pr.new/hotcodepush-team/cordova-code-push/@hotcodepush/cordova-code-push@<sha>
```

A consumer pins a commit and bumps it deliberately; the preview comment on each commit names its `<sha>`. `npx hotcodepush init` runs the command for you and writes `hotcodepush.json`.

The plugin needs `cordova-ios` 8 and `cordova-android` 14 or 15, and it wires itself: its `after_prepare` hook runs `npx hotcodepush binary create` on every `cordova prepare` and `cordova build`, which writes the resource file the SDK reads into each platform's `www` and creates the store build, the binary. Without a token on your machine, or with `HOTCODEPUSH_OFFLINE=1` for a build that is never shipped, the file names no channel and the build takes no updates; a pipeline without a token fails instead.

The native cores are the Swift package `HotCodePushProtocol` and the Android library `com.hotcodepush:protocol-android`, each pinned to a commit until it is published. On iOS the plugin is a Swift package: `cordova-ios` adds it to the app, and Swift Package Manager resolves the core at the pinned revision on its own, without CocoaPods. On Android the plugin switches the project's Kotlin Gradle plugin on at the version the core is compiled with, through the `GradlePluginKotlinEnabled` and `GradlePluginKotlinVersion` preferences, and adds JitPack, which builds the pinned commit, to the app module's repositories; a preference in your own `config.xml` wins over either.

On Android the core keeps its store out of device backups and transfers: its manifest sets `android:fullBackupContent` and `android:dataExtractionRules` on `<application>`, merged into the app's manifest. An app that already sets either attribute hits a manifest-merger conflict. Add `tools:replace="android:fullBackupContent"` or `tools:replace="android:dataExtractionRules"` to `<application>` with an `<edit-config>` in your `config.xml`, and put `<exclude domain="file" path="hotcodepush/" />` into your own rules, inside both `<cloud-backup>` and `<device-transfer>` for the extraction rules; otherwise the store rides along in the backup again.

## Usage

```js
document.addEventListener('deviceready', async () => {
  const result = await HotCodePush.sync();
  if (result.status === 'UPDATED') {
    console.log(
      `release #${result.release.number} installs ${result.installAt}`,
    );
  }
});
```

The plugin is `window.HotCodePush` once `deviceready` has fired, every method returning a promise. With `autoCheck` on, the default, the SDK checks on start, on resume and while the app stays in the foreground, and what follows a check is the download and install strategies' business; `sync()` is for the moment you want an update now. An app that asks before downloading sets `downloadStrategy` to `manual` and calls `downloadUpdate()` on `updateAvailable`; one that protects a flow sets `installStrategy` to `manual` and calls `applyUpdate()` when it is ready.

A TypeScript project gets the global and the result types from the package:

```ts
import type { SyncResult } from '@hotcodepush/cordova-code-push';

const result: SyncResult = await HotCodePush.sync();
```

A bundle carries your web build, `www`. `cordova.js`, `cordova_plugins.js` and `plugins/` always come from the installed binary, since they are the bridge to the native plugins compiled into it.

## Documentation

The SDK reference — configuration, methods, events, types and reasons — is at [hotcodepush.com/docs/cordova](https://hotcodepush.com/docs/cordova).

## Development

```sh
nvm use
npm ci
npm run lint
npm run build
npm run verify:ios       # a fresh Cordova app with the plugin, built for the simulator
npm run verify:android   # the same app, built for Android
```

The cores and their tests live in [protocol-ios](https://github.com/hotcodepush-team/protocol-ios) and [protocol-android](https://github.com/hotcodepush-team/protocol-android).

## License

See [LICENSE](./LICENSE).
