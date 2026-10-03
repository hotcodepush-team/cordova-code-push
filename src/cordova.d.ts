/**
 * Cordova's bridge as its module system hands it to a plugin's JavaScript module.
 */
declare module 'cordova/exec' {
  function exec(
    success: (result: never) => void,
    failure: (message: string) => void,
    service: string,
    action: string,
    args: unknown[],
  ): void;
  export = exec;
}
