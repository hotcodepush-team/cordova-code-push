const { spawnSync } = require('node:child_process');

const PLATFORMS = ['android', 'ios'];

/**
 * The embed step, run by Cordova after every prepare: `npx hotcodepush bundle embed` once per prepared platform,
 * which writes the resource file the SDK reads into the platform's `www` and registers the store build.
 * A failing embed fails the prepare, so a build never ships without its resource file.
 */
module.exports = function embedBundle(context) {
  const preparedPlatforms = context.opts.platforms.filter(platform =>
    PLATFORMS.includes(platform),
  );
  for (const platform of preparedPlatforms) {
    const result = spawnSync(
      'npx',
      ['hotcodepush', 'bundle', 'embed', '--platform', platform],
      {
        cwd: context.opts.projectRoot,
        shell: process.platform === 'win32',
        stdio: 'inherit',
      },
    );
    if (result.status !== 0) {
      throw new Error(
        `hotcodepush bundle embed failed for ${platform}; run "npx hotcodepush doctor" in the project.`,
      );
    }
  }
};
