const { spawnSync } = require('node:child_process');

const PLATFORMS = ['android', 'ios'];

/**
 * The build step, run by Cordova after every prepare: `npx hotcodepush binary create` once per prepared platform,
 * which writes the resource file the SDK reads into the platform's `www` and creates the store build, the binary.
 * A failing step fails the prepare, so a build never ships without its resource file.
 */
module.exports = function createBinary(context) {
  const preparedPlatforms = context.opts.platforms.filter(platform =>
    PLATFORMS.includes(platform),
  );
  for (const platform of preparedPlatforms) {
    const result = spawnSync(
      'npx',
      ['hotcodepush', 'binary', 'create', '--platform', platform],
      {
        cwd: context.opts.projectRoot,
        shell: process.platform === 'win32',
        stdio: 'inherit',
      },
    );
    if (result.status !== 0) {
      throw new Error(
        `hotcodepush binary create failed for ${platform}; run "npx hotcodepush doctor" in the project.`,
      );
    }
  }
};
