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
  'rolledBack',
]);

const SERVICE = 'HotCodePush';

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
  downloadUpdate: () => callNative('downloadUpdate'),
  getChannel: () => callNative('getChannel'),
  getDevice: () => callNative('getDevice'),
  getState: () => callNative('getState'),
  notifyReady: () => callNative('notifyReady'),
  removeAllListeners: () => {
    listenersByEventName.clear();
    return Promise.resolve();
  },
  rollbackUpdate: options => callNative('rollbackUpdate', options),
  setAttributes: options => callNative('setAttributes', options),
  setChannel: options => callNative('setChannel', options),
  setRestartAllowed: options => callNative('setRestartAllowed', options),
  showDebugScreen: () => callNative('showDebugScreen'),
  sync: options => callNative('sync', options),
};

function callNative<TResult>(
  action: string,
  options: object | null = null,
): Promise<TResult> {
  return new Promise((resolve, reject) => {
    exec(resolve, message => reject(new Error(message)), SERVICE, action, [
      options ?? {},
    ]);
  });
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
