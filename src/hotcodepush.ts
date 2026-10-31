import type { HotCodePushEventName } from '@hotcodepush/protocol';
import exec = require('cordova/exec');
import type { HotCodePushPlugin } from './definitions';

type Listener = (event: unknown) => void;

interface NativeEvent {
  data: unknown;
  eventName: HotCodePushEventName;
}

const SERVICE = 'HotCodePush';

// Checked before the native call, so both platforms reject a wrong type alike, as a programming mistake.
// Unknown keys are ignored, as the Capacitor and React Native bridges ignore them.
const OPTIONS_SHAPES = {
  downloadUpdate: {
    description:
      '{ applyStrategy?: string, mandatoryApplyStrategy?: string } or nothing',
    matches: (options: unknown) =>
      options === undefined ||
      isRecordOfOptionalStrings(options, [
        'applyStrategy',
        'mandatoryApplyStrategy',
      ]),
  },
  rollbackUpdate: {
    description: '{ reason?: string } or nothing',
    matches: (options: unknown) =>
      options === undefined || isRecordOfOptionalStrings(options, ['reason']),
  },
  setAttributes: {
    description: 'an object of string or null values',
    matches: (options: unknown) =>
      isRecord(options) &&
      Object.values(options).every(
        value => value === null || typeof value === 'string',
      ),
  },
  setChannel: {
    description: '{ id: string }, { name: string } or null',
    matches: (options: unknown) =>
      options === null ||
      (isRecordOfOptionalStrings(options, ['id', 'name']) &&
        (options.id !== undefined || options.name !== undefined)),
  },
  setRestartAllowed: {
    description: '{ isAllowed: boolean }',
    matches: (options: unknown) =>
      isRecord(options) && typeof options.isAllowed === 'boolean',
  },
  sync: {
    description:
      '{ applyStrategy?: string, downloadStrategy?: string, mandatoryApplyStrategy?: string } or nothing',
    matches: (options: unknown) =>
      options === undefined ||
      isRecordOfOptionalStrings(options, [
        'applyStrategy',
        'downloadStrategy',
        'mandatoryApplyStrategy',
      ]),
  },
};

const listenersByEventName = new Map<HotCodePushEventName, Set<Listener>>();

// The start after a rollback reports it before the reloaded app adds its listener, so it waits here.
let retainedUpdateRolledBack: unknown;

const hotCodePush: HotCodePushPlugin = {
  addListener: (eventName, listener) => {
    const listeners = listenersByEventName.get(eventName) ?? new Set();
    listeners.add(listener as Listener);
    listenersByEventName.set(eventName, listeners);
    if (
      eventName === 'updateRolledBack' &&
      retainedUpdateRolledBack !== undefined
    ) {
      (listener as Listener)(retainedUpdateRolledBack);
      retainedUpdateRolledBack = undefined;
    }
    return Promise.resolve({
      remove: () => {
        listeners.delete(listener as Listener);
        return Promise.resolve();
      },
    });
  },
  applyUpdate: () => callNative('applyUpdate'),
  checkForUpdate: () => callNative('checkForUpdate'),
  clearUpdates: () => callNative('clearUpdates'),
  downloadUpdate: options => callNativeWithOptions('downloadUpdate', options),
  getChannel: () => callNative('getChannel'),
  getDevice: () => callNative('getDevice'),
  getState: () => callNative('getState'),
  notifyReady: () => callNative('notifyReady'),
  removeAllListeners: () => {
    listenersByEventName.clear();
    return Promise.resolve();
  },
  rollbackUpdate: options => callNativeWithOptions('rollbackUpdate', options),
  setAttributes: options => callNativeWithOptions('setAttributes', options),
  setChannel: options => callNativeWithOptions('setChannel', options),
  setRestartAllowed: options =>
    callNativeWithOptions('setRestartAllowed', options),
  showDebugScreen: () => callNative('showDebugScreen'),
  sync: options => callNativeWithOptions('sync', options),
};

function callNative<TResult>(
  action: string,
  options: unknown = null,
): Promise<TResult> {
  return new Promise((resolve, reject) => {
    exec(resolve, message => reject(new Error(message)), SERVICE, action, [
      options ?? {},
    ]);
  });
}

function callNativeWithOptions<TResult>(
  action: keyof typeof OPTIONS_SHAPES,
  options: unknown,
): Promise<TResult> {
  const shape = OPTIONS_SHAPES[action];
  if (!shape.matches(options)) {
    return Promise.reject(new Error(`${action} takes ${shape.description}`));
  }
  return callNative(action, options);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isRecordOfOptionalStrings(
  value: unknown,
  keys: readonly string[],
): value is Record<string, unknown> {
  return (
    isRecord(value) &&
    keys.every(
      key => value[key] === undefined || typeof value[key] === 'string',
    )
  );
}

function dispatchNativeEvent({ data, eventName }: NativeEvent): void {
  const listeners = listenersByEventName.get(eventName);
  if (listeners === undefined || listeners.size === 0) {
    if (eventName === 'updateRolledBack') {
      retainedUpdateRolledBack = data;
    }
    return;
  }
  for (const listener of listeners) {
    listener(data);
  }
}

function listenToNativeEvents(): void {
  exec(dispatchNativeEvent, () => undefined, SERVICE, 'listen', []);
}

// Drives the `render` readiness signal.
function notifyRenderedOnFirstFrame(): void {
  const notify = () =>
    requestAnimationFrame(
      () => void callNative('notifyRendered').catch(() => undefined),
    );
  if (document.readyState === 'complete') {
    notify();
  } else {
    window.addEventListener('load', notify, { once: true });
  }
}

listenToNativeEvents();
notifyRenderedOnFirstFrame();

export = hotCodePush;
