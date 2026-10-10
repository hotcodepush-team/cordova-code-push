# CLAUDE.md

The HotCodePush Cordova SDK: `@hotcodepush/cordova-code-push`, the plugin that delivers live updates to Cordova apps on iOS and Android.
Stack: TypeScript for the JavaScript module and the types, Swift for the iOS bridge, Kotlin for the Android bridge, `cordova-ios` 8, `cordova-android` 15 and 14.

The plan is the private `handbook` repo, checked out beside this one: `../handbook/docs/`.
`sdk-api.md` is the SDK's specification — the methods, the configuration, the state keys, the wire shapes and the reason catalog; `architecture.md`'s _The device protocol_ and _Packs_ are the behaviour behind them.
When code and plan disagree, stop and surface it; never improvise.

## Layout

```
plugin.xml             the plugin: the JavaScript module, the iOS hook that adds the build phase, the Android sources and Gradle reference, the iOS Swift package
Package.swift          the iOS half as a Swift package named after the plugin's id, over Cordova and HotCodePushCore
src/hotcodepush.ts     the module Cordova clobbers onto window.HotCodePush: one native call per method, the events, the readiness signal
src/definitions.ts     the types the package exports and the global it declares
src/hotcodepush.test.mjs  the module's tests on node --test, the module loaded as Cordova's factory with cordova/exec recorded
src/ios                the Cordova plugin, the bundle loader and the scheme-task responder over HotCodePushCore
src/android            the Cordova plugin and the bundle loader over com.hotcodepush:core-android, and the Gradle reference with the build step's task per variant
scripts/add-binary-create-phase.js  the iOS hook: adds the build phase to the generated Xcode project, once, at platform add and every prepare
scripts/binary-create-xcode.sh      what the phase runs, with the Node lookup; `binary create` in an archive, `resource-file write` otherwise
scripts/*.test.mjs                  their tests on node --test
scripts/build-test-app.mjs  the compile check: a fresh Cordova app with the plugin, built for one platform
benchmarks/            the size and cold-start baseline measured on the demo, its harness, and the guard baseline.yml runs
tests/android          the Kotlin of src/android built on its own over cordova-android's framework, with its Robolectric tests of the loader's path guards
tests/ios              the XCTest target over the loader and the scheme-task responder, run on Mac Catalyst under the shared scheme in .swiftpm
```

The native cores live in `core-ios` and `core-android`, consumed at pinned commits: `Package.swift` by `revision`, the Android module from core-android's `maven` branch by full sha in `src/android/hotcodepush.gradle`; a core change lands there first and arrives here as a bump of the pin.
The plugin layer keeps the bundle loader, the readiness signal and the bridge, nothing of the protocol.

## Commands

| Command                                | Does                                                                 |
| -------------------------------------- | -------------------------------------------------------------------- |
| `npm run lint`                         | ESLint, Prettier and SwiftLint                                       |
| `npm run build`                        | the TypeScript into `dist/`, which `plugin.xml` names                |
| `npm run verify:ios`, `verify:android` | a fresh Cordova app with the plugin, built for platform              |
| `npm test`                             | the module, the hook and the script; the script's tests run on macOS |
| `npm run test:android`                 | the Kotlin's Robolectric tests, in `tests/android`                   |
| `npm run test:ios`                     | the Swift tests on Mac Catalyst, in `tests/ios`                      |

Run `npm run fmt` before every commit.
The package is CommonJS on purpose: Cordova `require`s a plugin's hook script, so the tooling's own modules are `.mjs`.

## Dependencies during the build phase

Consumers pin the preview builds pkg.pr.new publishes from `ci.yml` on every push and pull request, never npm: `cordova plugin add https://pkg.pr.new/hotcodepush-team/cordova-code-push/@hotcodepush/cordova-code-push@<sha>`.
A consumer pins a commit and bumps it deliberately — never `@main`, whose moving content breaks `npm ci` against the lockfile's integrity hash.
The shared types come from `@hotcodepush/protocol` the same way, pinned to a commit in `package.json`; a protocol change is a bump of that sha.

## Rules

- The SDK never sees an API DTO: its contract is the channel index, the bundle manifest and the events endpoint, additive only.
- Safety is on by default and cannot be switched off: the readiness gate, the local blocklist, the automatic rollback.
- Nothing a device does not need to decide lives here: rollout, conditions, revocation and the cap are evaluated from the index, never configured.
- Statuses and reasons are `SCREAMING_SNAKE_CASE` from the one catalog; a method throws a plain error only for a programming mistake.
- The plugin's id is its package name, `@hotcodepush/cordova-code-push`: Cordova restores a plugin by looking its id up among `package.json`'s dependencies, and `cordova-ios` names the Swift package and its product after it.
- A bundle is served on the app's own origin: the plugin answers Cordova's scheme handler on iOS and its asset loader on Android before Cordova does, from the bundle's directory under the store; no start page is swapped and no storage moves.
- `cordova.js`, `cordova_plugins.js` and `plugins/` are the binary's under every bundle: a request for them is never answered from a bundle's directory.
- The Swift package carries no resources: a package named after the scoped plugin id would lay its resource bundle under `@hotcodepush/` inside the app, so the plugin calls no required-reason API of its own, keeps the served bundle's key in the core's store, and leaves the privacy manifest to the core.
- The resource file is `www/hotcodepush.json`, written by the Xcode phase into the built app's `www` and by the Gradle task into the variant's generated `www` assets; the embedded bundle is the platform's `www`, addressed by the embedded manifest's hashes, without the native glue the loader serves from the binary.
- The plugin's `plugin.xml` sets `GradlePluginKotlinEnabled` and `GradlePluginKotlinVersion`, so an app adds the plugin and edits nothing; the app's own preference wins.
- A page start the plugin did not request, `location.reload()`, a navigation, iOS's recovery from a web content crash, is never reported to the core: the process start decides what runs and gates it, a release stored for the next start waits for the next launch, and only the SDK's own reloads hold `updateRolledBack` for the page that follows.

## Agent workspace

- `.mcp.json` is absent on purpose: no server covers Cordova's own documentation, and the HotCodePush server joins when it exists.
- `.claude/skills/` holds the developer skills copied from `hotcodepush-team/.github`, pinned in `skills-lock.json`.
- Commits are conventional commits; `main` is trunk, CI is the gate, and a commit that lands an issue says `Closes #<n>`.
