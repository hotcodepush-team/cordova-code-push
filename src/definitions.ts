import type {
  ApplyUpdateResult,
  CheckForUpdateResult,
  DownloadUpdateOptions,
  DownloadUpdateResult,
  GetChannelResult,
  GetDeviceResult,
  GetStateResult,
  HotCodePushEventName,
  HotCodePushEvents,
  NotifyReadyResult,
  RollbackUpdateOptions,
  SetAttributesOptions,
  SetChannelOptions,
  SetRestartAllowedOptions,
  SyncOptions,
  SyncResult,
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
 * The HotCodePush Cordova plugin. Its option, result and event types come from `@hotcodepush/protocol`.
 */
export interface HotCodePushPlugin {
  /**
   * Runs one update cycle: fetch the index, evaluate it, download and verify, apply and report.
   * The SDK runs the same cycle at start, resume and interval. It stops at a `manual` strategy.
   * A second call while one runs joins the running one.
   */
  sync(options?: SyncOptions): Promise<SyncResult>;
  /** Fetches and evaluates the index without downloading, like `sync()` with `downloadStrategy: 'manual'`. */
  checkForUpdate(): Promise<CheckForUpdateResult>;
  /**
   * Downloads and verifies the update, then applies it per the apply strategies.
   * Works like `sync()` with `downloadStrategy: 'auto'`. The index check is a conditional GET.
   */
  downloadUpdate(
    options?: DownloadUpdateOptions,
  ): Promise<DownloadUpdateResult>;
  /** Applies the downloaded update now, whatever the strategy says, and reloads the app. */
  applyUpdate(): Promise<ApplyUpdateResult>;
  /** Ends the readiness gate when `readySignal` is `manual`. Safe to call at any time, on any setting. */
  notifyReady(): Promise<NotifyReadyResult>;
  /**
   * Rolls back the running release now and reloads the app.
   * Marks its bundle as failed on this device and reports `app_requested`.
   */
  rollbackUpdate(options?: RollbackUpdateOptions): Promise<void>;
  /**
   * Clears all downloaded updates and the list of failed bundles, then reloads the app.
   * Keeps the channel and the attributes.
   */
  clearUpdates(): Promise<void>;
  /**
   * Holds or allows the restart the SDK performs on its own.
   * `isAllowed: false` holds the restart after an `immediate` apply, a `next_resume` apply or a mandatory release.
   * `isAllowed: true` then runs it. Restarts from `applyUpdate()`, `rollbackUpdate()` and `clearUpdates()` are never held.
   * Not persisted: every start begins allowed.
   */
  setRestartAllowed(options: SetRestartAllowedOptions): Promise<void>;
  /** Returns a snapshot of the SDK's state. */
  getState(): Promise<GetStateResult>;
  /** Returns the channel in effect and its source. */
  getChannel(): Promise<GetChannelResult>;
  /** Switches the device to a channel by name or by id. `null` clears the runtime choice. */
  setChannel(options: SetChannelOptions): Promise<void>;
  /** Returns the facts of the device report. */
  getDevice(): Promise<GetDeviceResult>;
  /** Merges string attributes for `attribute` conditions. A `null` value removes the key. */
  setAttributes(options: SetAttributesOptions): Promise<void>;
  /** Opens the SDK's native debug screen. */
  showDebugScreen(): Promise<void>;
  addListener<EventName extends HotCodePushEventName>(
    eventName: EventName,
    listener: (event: HotCodePushEvents[EventName]) => void,
  ): Promise<HotCodePushListenerHandle>;
  removeAllListeners(): Promise<void>;
}

declare global {
  /**
   * The plugin, available once `deviceready` has fired.
   */
  var HotCodePush: HotCodePushPlugin;
}
