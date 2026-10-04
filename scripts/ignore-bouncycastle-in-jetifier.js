const { existsSync } = require('node:fs');
const { dirname, join } = require('node:path');

const BOUNCY_CASTLE_JAR = 'bcprov-jdk18on';
const IGNORE_LIST_PROPERTY = 'android.jetifier.ignorelist';

/**
 * Cordova turns Jetifier on in every Android project, and Jetifier cannot read the classes BouncyCastle carries for
 * recent Java versions, so the build fails on the jar the core verifies signatures with. Run by Cordova when the
 * plugin is installed into the Android platform: puts that jar on Jetifier's ignore list in the project's Gradle
 * properties, an entry every later prepare keeps. Jetifier has nothing to rewrite in the jar.
 */
module.exports = function ignoreBouncyCastleInJetifier(context) {
  const { projectRoot } = context.opts;
  const propertiesPath = join(
    projectRoot,
    'platforms',
    'android',
    'gradle.properties',
  );
  const propertiesParser = requireCordovaPropertiesParser(projectRoot);
  // A platform restored by `cordova prepare` gets its plugins before Cordova writes the file.
  const gradleProperties = existsSync(propertiesPath)
    ? propertiesParser.createEditor(propertiesPath)
    : propertiesParser.createEditor();
  const ignoredJars = (gradleProperties.get(IGNORE_LIST_PROPERTY) ?? '')
    .split(',')
    .filter(Boolean);
  if (ignoredJars.includes(BOUNCY_CASTLE_JAR)) {
    return;
  }
  gradleProperties.set(
    IGNORE_LIST_PROPERTY,
    [...ignoredJars, BOUNCY_CASTLE_JAR].join(','),
  );
  gradleProperties.save(propertiesPath);
};

/**
 * The parser `cordova-android` itself edits the file with, resolved from the app's copy of the platform: the app
 * always has it, under every package manager's layout.
 */
function requireCordovaPropertiesParser(projectRoot) {
  const cordovaAndroidDirectory = dirname(
    require.resolve('cordova-android/package.json', { paths: [projectRoot] }),
  );
  return require(
    require.resolve('properties-parser', { paths: [cordovaAndroidDirectory] }),
  );
}
