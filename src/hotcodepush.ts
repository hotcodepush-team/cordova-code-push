import type {
  HotCodePushApi,
  HotCodePushEventName,
} from '@hotcodepush/protocol';
import exec = require('cordova/exec');

type Listener = (event: unknown) => void;

interface NativeEvent {
  data: unknown;
  eventName: HotCodePushEventName;
}

/**
 * The events held until the web layer listens: a rollback is reported by the start that follows it,
 * before the reloaded app has added its listener.
 */
const RETAINED_EVENT_NAMES: ReadonlySet<HotCodePushEventName> = new Set([
  'updateRolledBack',
]);

const SERVICE = 'HotCodePush';

/**
 * The options each method takes, checked before the call reaches the native side, so both platforms refuse any other
 * shape alike: a programming mistake, which rejects with the plain error.
 */
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
      (isRecord(options) &&
        Object.keys(options).length === 1 &&
        (typeof options.id === 'string' || typeof options.name === 'string')),
  },
  setRestartAllowed: {
    description: '{ allowed: boolean }',
    matches: (options: unknown) =>
      isRecord(options) &&
      Object.keys(options).length === 1 &&
      typeof options.allowed === 'boolean',
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

const retainedEventsByName = new Map<HotCodePushEventName, unknown>();

/**
 * The plugin as Cordova clobbers it onto `window.HotCodePush`: every method is one call into the native core.
 */
const hotCodePush: HotCodePushApi = {
  addListener: (eventName, listener) => {
    const listeners = listenersByEventName.get(eventName) ?? new Set();
    listeners.add(listener as Listener);
    listenersByEventName.set(eventName, listeners);
    if (retainedEventsByName.has(eventName)) {
      (listener as Listener)(retainedEventsByName.get(eventName));
      retainedEventsByName.delete(eventName);
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

/** An object of the named keys alone, each absent or a string. */
function isRecordOfOptionalStrings(
  value: unknown,
  keys: readonly string[],
): boolean {
  return (
    isRecord(value) &&
    Object.entries(value).every(
      ([key, entry]) =>
        keys.includes(key) &&
        (entry === undefined || typeof entry === 'string'),
    )
  );
}

function dispatchNativeEvent({ data, eventName }: NativeEvent): void {
  const listeners = listenersByEventName.get(eventName);
  if (listeners === undefined || listeners.size === 0) {
    if (RETAINED_EVENT_NAMES.has(eventName)) {
      retainedEventsByName.set(eventName, data);
    }
    return;
  }
  for (const listener of listeners) {
    listener(data);
  }
}

/**
 * The one callback the native side keeps for the life of the page and answers every event on.
 */
function listenToNativeEvents(): void {
  exec(dispatchNativeEvent, () => undefined, SERVICE, 'listen', []);
}

/**
 * The readiness signal `render`: the first frame the app paints after the bundle loaded.
 */
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
