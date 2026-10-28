# Cordova code push by HotCodePush

`@hotcodepush/cordova-code-push` is the Cordova plugin that delivers over-the-air (OTA) updates to your app: a code push reaches installed apps in seconds, without a store review.
Learn more at [hotcodepush.com/cordova-code-push](https://hotcodepush.com/cordova-code-push).

## Installation

`npx hotcodepush init` adds the plugin and writes `hotcodepush.json`.
By hand, until the package is on npm, add the preview build pkg.pr.new publishes for every commit on `main`, pinned to a commit:

```sh
cordova plugin add https://pkg.pr.new/hotcodepush-team/cordova-code-push/@hotcodepush/cordova-code-push@<sha>
```

The plugin needs `cordova-ios` 8, `cordova-android` 14 or 15 and iOS 15 or later, and it wires itself into the native builds.
The native cores, `HotCodePushCore` on iOS, the prebuilt framework of a core-ios release, and `com.hotcodepush:core-android`, resolve on their own.

Every native build writes `www/hotcodepush.json` into the app; an Xcode archive or a non-debug Android build also registers the store build in HotCodePush, so it needs `npx hotcodepush login` or `HOTCODEPUSH_TOKEN`.

## Usage

```js
document.addEventListener('deviceready', async () => {
  const result = await HotCodePush.sync();
  if (result.status === 'downloaded') {
    console.log(
      `release #${result.release.number} applies at ${result.applyStrategy}`,
    );
  }
});
```

The plugin is `window.HotCodePush` once `deviceready` has fired, every method returning a promise; a TypeScript project imports the types from the package.
With the default `checkStrategy` of `auto`, the SDK checks on start, on resume and in the foreground; `sync()` runs one cycle on demand.
Set `downloadStrategy` or `applyStrategy` to `manual` and call `downloadUpdate()` or `applyUpdate()` yourself to control when an update lands.
A bundle carries your web build, `www`; `cordova.js`, `cordova_plugins.js` and `plugins/` always come from the installed binary.

## Documentation

See [hotcodepush.com/docs/cordova](https://hotcodepush.com/docs/cordova) for the configuration, methods, events, types and reasons.

## Development

```sh
nvm use
npm ci
npm run build            # the TypeScript into dist/; run it before opening the native projects
npm run lint
npm test                 # the module, the hook and the Xcode script; the script's tests on macOS only
npm run test:ios         # the Swift tests, on an iOS simulator
npm run test:android     # the Kotlin's Robolectric tests
npm run verify:ios       # a fresh Cordova app with the plugin, built for iOS
npm run verify:android   # the same app, built for Android
npm run fmt              # run before every commit
```

The cores and their tests live in [core-ios](https://github.com/hotcodepush-team/core-ios) and [core-android](https://github.com/hotcodepush-team/core-android).
`CLAUDE.md` holds the layout and the rules.

## License

See [LICENSE](./LICENSE).
An app that ships the plugin also ships the native cores' third-party code: FreeBSD's bspatch (BSD 2-clause) on both platforms and bzip2 1.0.8 on Android. Reproduce the notices from [core-ios](https://github.com/hotcodepush-team/core-ios/blob/main/THIRD-PARTY-NOTICES) and [core-android](https://github.com/hotcodepush-team/core-android/blob/main/THIRD-PARTY-NOTICES) in your app's distribution.
