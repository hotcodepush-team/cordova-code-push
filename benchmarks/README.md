# The size and cold-start baseline

What the plugin adds to an app, measured on the demo app and guarded from then on: the numbers are in `baseline.json`, the method is this page, the harness is the three scripts beside it.

## What is measured

| Number                     | How                                                                                                                                                                                                      |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Binary size added, Android | the unsigned release APK of the demo built with the plugin minus the same build without it, in bytes                                                                                                     |
| Binary size added, iOS     | the Release simulator app — every file summed — built with the plugin minus the same build without it, in bytes                                                                                          |
| Cold start added, Android  | from the activity's start (`ActivityTaskManager: START` in logcat) to the web view's first paint, on the Pixel_9_Pro emulator; the median of five cold launches with the plugin minus the median without |
| Cold start added, iOS      | from the launch call to the web view's first paint, on an iPhone simulator; the same medians                                                                                                             |

The first paint is the moment both variants take on their first animation frame and log as `[baseline] first paint <epoch ms>` once `deviceready` has fired: Cordova hands the web view's console to the host only after it loaded its plugins, which the first frame of an app with a plugin comes before. The line is read from logcat on Android and from the process's output on iOS through `simctl launch --console-pty`, since a pipe would buffer it until the process exits.
The cold starts are measured on debug builds of both variants, each on a fresh install, while the sizes are measured on release builds.
The "without" variant is the demo with the plugin removed — and with it its hook and its resource file — and the screen's script swapped for the same screen with nothing behind it.
The "with" variant's embed step follows a placeholder channel id, which the step takes as it is, so the measurement needs no credential and registers nothing.

## Where the bytes sit

On the current baseline the Android release APK grows by about 652 KB, nearly all of it `classes.dex`, about 1.5 MB larger before compression: the plugin's bridge and the shared core, OkHttp with Okio, and the parts of the Kotlin library and kotlinx-coroutines an app without Kotlin code of its own does not carry. Cordova's release build does not shrink code, so a project that turns R8 on carries less.
The simulator app grows by about 3.6 MB, nearly all of it in the app's binary: the plugin and the core are linked statically, and a simulator build is a two-slice fat binary, so a device build carries about half of that; the rest is the core's privacy-manifest bundle of about 5 KB, the plugin's JavaScript module and the resource file.

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

`baseline.yml` runs on every pull request to `main`: it checks the demo out at the pinned commit, packs the plugin from the pull request, prepares the "with" variant, rebuilds both sizes and fails when either grew more than 10 % over the committed number; the sizes land in the job summary. Sizes are deterministic on a runner, cold starts are not — an emulator's timing on a shared runner is noise — so the cold-start check runs locally by script, and a change that could move it reruns the script and commits the new numbers with its reason.

The same harness later measures the competitors for `/benchmarks`.
