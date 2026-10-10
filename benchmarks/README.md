# The size and cold-start baseline

What the plugin adds to an app, measured on the demo app and guarded from then on: the numbers are in `baseline.json`, the method is this page, the harness is the three scripts beside it.

## What is measured

| Number                     | How                                                                                                                                                                                                      |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Binary size added, Android | the release APK, signed with the debug keystore the demo's `build.json` names, of the demo built with the plugin minus the same build without it, in bytes                                               |
| Binary size added, iOS     | the Release simulator app — every file summed — built with the plugin minus the same build without it, in bytes                                                                                          |
| Cold start added, Android  | from the activity's start (`ActivityTaskManager: START` in logcat) to the web view's first paint, on the Pixel_9_Pro emulator; the median of five cold launches with the plugin minus the median without |
| Cold start added, iOS      | from the launch call to the web view's first paint, on an iPhone simulator; the same medians                                                                                                             |

The first paint is the moment both variants take on their first animation frame and log as `[baseline] first paint <epoch ms>` once `deviceready` has fired: Cordova hands the web view's console to the host only after it loaded its plugins, which the first frame of an app with a plugin comes before. The line is read from logcat on Android and from the process's output on iOS through `simctl launch --console-pty`, since a pipe would buffer it until the process exits.
The cold starts are measured on debug builds of both variants, each on a fresh install, while the sizes are measured on release builds.
The "without" variant is the demo with the plugin removed — and with it its Gradle task and its Xcode phase — and the screen's script swapped for the same screen with nothing behind it.
The "with" variant's build step runs under `HOTCODEPUSH_OFFLINE=1`, so the measurement needs no credential and creates no binary; the build then names no channel, checks nothing and takes no updates.

## Where the bytes sit

On the current baseline the Android release APK grows by about 777 KB.
About 547 KB of it is `classes.dex`: the plugin's bridge and the shared core, and OkHttp with Okio; the app already carries the Kotlin library and kotlinx-coroutines, and the plugin adds fewer than thirty classes of each. The core verifies signatures with Android's own API, so no cryptography library is among them.
About 177 KB of it is `libhotcodepush_bspatch.so`, the core's native library that applies a delta pack's patches, FreeBSD's bspatch and the decompression of bzip2 1.0.8, once for each of four ABIs, of which an app bundle delivers one: 133 KB of files, and the padding that aligns each to a 16 KB page, since the APK stores them uncompressed.
About 42 KB of it is the public-suffix list OkHttp brings.
The simulator app grows by about 3.7 MB, nearly all of it in the app's binary: the plugin and the core are linked statically, and a simulator build is a two-slice fat binary, so a device build carries about half of that; the rest is the core's privacy-manifest bundle of about 5 KB, the plugin's JavaScript module and the resource file.

## Running it

```sh
npm run build && npm pack --pack-destination /tmp
node benchmarks/prepare-demo.mjs ../cordova-code-push-demo /tmp/baseline/with with /tmp/hotcodepush-cordova-code-push-0.0.0.tgz
node benchmarks/prepare-demo.mjs ../cordova-code-push-demo /tmp/baseline/without without
node benchmarks/measure-size.mjs /tmp/baseline/with
node benchmarks/measure-size.mjs /tmp/baseline/without
node benchmarks/measure-cold-start.mjs /tmp/baseline/with --android emulator-5554 --ios <udid>
node benchmarks/measure-cold-start.mjs /tmp/baseline/without --android emulator-5554 --ios <udid>
```

Start the Android emulator headless, `emulator -avd Pixel_9_Pro -no-window -gpu host`: macOS drops a windowed emulator to background priority within minutes, which inflates the load average and every cold start with it. Before each variant, press HOME and force-stop the app, so a reinstall does not relaunch it on its own.

The demo is `hotcodepush-team/cordova-code-push-demo` at the commit `baseline.json` names; a new baseline names the commit it was measured against.

## The guard

`baseline.yml` runs on every pull request to `main`: it checks the demo out at the pinned commit, packs the plugin from the pull request, creates the debug keystore the demo's `build.json` names, builds both variants through the native step, measures both sizes and fails when either grew more than 10 % over the committed number; the sizes land in the job summary. Sizes are deterministic on a runner, cold starts are not — an emulator's timing on a shared runner is noise — so the cold-start check runs locally by script, and a change that could move it reruns the script and commits the new numbers with its reason.

The same harness later measures the competitors for `/benchmarks`.
