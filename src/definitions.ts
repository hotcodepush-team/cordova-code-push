import type {
  HotCodePushEventName,
  HotCodePushEvents,
  HotCodePushMethods,
} from '@hotcodepush/protocol';

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
  HotCodePushEventName,
  HotCodePushEvents,
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

export interface HotCodePushListenerHandle {
  remove: () => Promise<void>;
}

/**
 * The HotCodePush Cordova plugin. Its methods and their option, result and event types come from `@hotcodepush/protocol`.
 */
export interface HotCodePushPlugin extends HotCodePushMethods {
  addListener<EventName extends HotCodePushEventName>(
    eventName: EventName,
    listener: (event: HotCodePushEvents[EventName]) => void,
  ): Promise<HotCodePushListenerHandle>;
}

declare global {
  /**
   * The plugin, available once `deviceready` has fired.
   */
  var HotCodePush: HotCodePushPlugin;
}
