import type { HotCodePushApi } from '@hotcodepush/protocol';

export type {
  ApplyResult,
  CheckResult,
  ConditionType,
  DownloadProgressEvent,
  DownloadResult,
  DownloadStrategy,
  FailedReason,
  GetChannelResult,
  GetDeviceResult,
  GetStateResult,
  HotCodePushApi,
  HotCodePushEventName,
  HotCodePushEvents,
  HotCodePushListenerHandle,
  InstallMoment,
  InstallStrategy,
  MandatoryInstallStrategy,
  NotifyReadyResult,
  ReadySignal,
  Release,
  RollbackReason,
  RollbackUpdateOptions,
  RolledBackEvent,
  SetAttributesOptions,
  SetChannelOptions,
  SetRestartAllowedOptions,
  SkippedReason,
  SyncOptions,
  SyncResult,
  SyncTrigger,
  UpdateAvailableEvent,
  UpdateDownloadedEvent,
  UpdateFailedEvent,
} from '@hotcodepush/protocol';

/**
 * The Cordova plugin: the one SDK surface `@hotcodepush/protocol` defines, every method returning a promise.
 */
export type HotCodePushPlugin = HotCodePushApi;

declare global {
  /**
   * The plugin, there once `deviceready` has fired; `window.HotCodePush` is the same object.
   */
  var HotCodePush: HotCodePushPlugin;
}
