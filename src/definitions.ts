import type { HotCodePushApi } from '@hotcodepush/protocol';

export type {
  ApplyMoment,
  ApplyStrategy,
  ApplyUpdateResult,
  CheckForUpdateResult,
  CheckStrategy,
  ConditionType,
  DownloadProgressEvent,
  DownloadStrategy,
  DownloadUpdateOptions,
  DownloadUpdateResult,
  FailedReason,
  GetChannelResult,
  GetDeviceResult,
  GetStateResult,
  HotCodePushApi,
  HotCodePushEventName,
  HotCodePushEvents,
  HotCodePushListenerHandle,
  MandatoryApplyStrategy,
  NotifyReadyResult,
  ReadySignal,
  Release,
  RollbackReason,
  RollbackUpdateOptions,
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
  UpdateRolledBackEvent,
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
