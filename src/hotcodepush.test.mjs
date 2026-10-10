import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';
import { describe, it } from 'node:test';
import { setImmediate } from 'node:timers/promises';
import { inspect } from 'node:util';
import { compileFunction } from 'node:vm';
import { ModuleKind, ScriptTarget, transpileModule } from 'typescript';

const SERVICE = 'HotCodePush';

const UPDATE_ROLLED_BACK_EVENT = {
  from: {
    bundleId: '0f8fad5b-d9cb-469f-a165-70867728950e',
    bundleVersion: '1.4.2',
    id: '7c9e6679-7425-40de-944b-e07fc1f90ae7',
    isMandatory: false,
    number: 43,
  },
  reason: 'APP_REQUESTED',
  to: null,
};

// The module as Cordova runs it: compiled to CommonJS and called as the factory `cordova.define` wraps a plugin's
// module in, with the page's globals the module reaches handed in beside `require`.
const MODULE_PARAMETERS = [
  'require',
  'exports',
  'module',
  'document',
  'window',
  'requestAnimationFrame',
];
const MODULE_SOURCE = transpileModule(
  readFileSync(join(import.meta.dirname, 'hotcodepush.ts'), 'utf8'),
  {
    compilerOptions: {
      module: ModuleKind.CommonJS,
      target: ScriptTarget.ES2022,
    },
  },
).outputText;

const WRONG_OPTIONS = [
  ['downloadUpdate', null],
  ['downloadUpdate', { downloadStrategy: 'auto' }],
  ['downloadUpdate', { applyStrategy: 1 }],
  ['rollbackUpdate', null],
  ['rollbackUpdate', { reason: 42 }],
  ['rollbackUpdate', { cause: 'checkout' }],
  ['setAttributes', undefined],
  ['setAttributes', null],
  ['setAttributes', ['plan']],
  ['setAttributes', { plan: 3 }],
  ['setChannel', undefined],
  ['setChannel', {}],
  ['setChannel', { id: 'c1', name: 'beta' }],
  ['setChannel', { id: 7 }],
  ['setChannel', { channel: 'beta' }],
  ['setRestartAllowed', undefined],
  ['setRestartAllowed', {}],
  ['setRestartAllowed', { allowed: 'true' }],
  ['setRestartAllowed', { allowed: true, isHeld: false }],
  ['sync', null],
  ['sync', { checkStrategy: 'manual' }],
  ['sync', { applyStrategy: 2 }],
];

const ACCEPTED_OPTIONS = [
  ['downloadUpdate', undefined, {}],
  [
    'downloadUpdate',
    { applyStrategy: 'immediate', mandatoryApplyStrategy: 'next-start' },
    { applyStrategy: 'immediate', mandatoryApplyStrategy: 'next-start' },
  ],
  ['rollbackUpdate', undefined, {}],
  [
    'rollbackUpdate',
    { reason: 'checkout broke' },
    { reason: 'checkout broke' },
  ],
  [
    'setAttributes',
    { plan: 'pro', tenant: null },
    { plan: 'pro', tenant: null },
  ],
  [
    'setChannel',
    { id: '3b241101-e2bb-4255-8caf-4136c566a962' },
    { id: '3b241101-e2bb-4255-8caf-4136c566a962' },
  ],
  ['setChannel', { name: 'beta' }, { name: 'beta' }],
  ['setChannel', null, {}],
  ['setRestartAllowed', { allowed: false }, { allowed: false }],
  ['sync', undefined, {}],
  ['sync', { downloadStrategy: 'manual' }, { downloadStrategy: 'manual' }],
];

describe('hotcodepush.ts', () => {
  describe('the native calls', () => {
    it('should register the one event callback on the native side when the module loads', () => {
      const page = loadPage();

      assert.deepEqual(
        page.nativeCalls.map(({ action, args, service }) => ({
          action,
          args,
          service,
        })),
        [{ action: 'listen', args: [], service: SERVICE }],
      );
    });

    it('should call the native action named after the method with an empty object when the method takes no options', () => {
      const page = loadPage();

      void page.hotCodePush.getState();

      const { args, service } = page.findNativeCall('getState');
      assert.equal(service, SERVICE);
      assert.deepEqual(args, [{}]);
    });

    it('should resolve with what the native side answers', async () => {
      const page = loadPage();
      const state = { currentRelease: null };

      const result = page.hotCodePush.getState();
      page.findNativeCall('getState').success(state);

      assert.equal(await result, state);
    });

    it('should reject with an error carrying the native message when the native side fails', async () => {
      const page = loadPage();

      const result = page.hotCodePush.clearUpdates();
      page.findNativeCall('clearUpdates').failure('HotCodePush is off');

      await assert.rejects(result, new Error('HotCodePush is off'));
    });
  });

  describe('the options', () => {
    for (const [method, options, expectedArgument] of ACCEPTED_OPTIONS) {
      it(`should hand ${method} the native argument ${inspect(expectedArgument)} when its options are ${inspect(options)}`, () => {
        const page = loadPage();

        void page.hotCodePush[method](options);

        assert.deepEqual(page.findNativeCall(method).args, [expectedArgument]);
      });
    }

    for (const [method, options] of WRONG_OPTIONS) {
      it(`should reject ${method} with the plain error and call nothing native when its options are ${inspect(options)}`, async () => {
        const page = loadPage();

        await assert.rejects(page.hotCodePush[method](options), {
          message: new RegExp(`^${method} takes `),
          name: 'Error',
        });
        assert.equal(page.findNativeCall(method), undefined);
      });
    }
  });

  describe('the events', () => {
    it('should deliver a native event to every listener of its name and to no other', async () => {
      const page = loadPage();
      const firstListener = recordCalls();
      const secondListener = recordCalls();
      const otherListener = recordCalls();
      await page.hotCodePush.addListener('updateAvailable', firstListener);
      await page.hotCodePush.addListener('updateAvailable', secondListener);
      await page.hotCodePush.addListener('updateDownloaded', otherListener);

      page.sendNativeEvent('updateAvailable', { trigger: 'manual' });

      assert.deepEqual(firstListener.calls, [{ trigger: 'manual' }]);
      assert.deepEqual(secondListener.calls, [{ trigger: 'manual' }]);
      assert.deepEqual(otherListener.calls, []);
    });

    it('should deliver nothing to a listener when its handle removed it', async () => {
      const page = loadPage();
      const listener = recordCalls();
      const handle = await page.hotCodePush.addListener(
        'updateFailed',
        listener,
      );

      await handle.remove();
      page.sendNativeEvent('updateFailed', { reason: 'DEVICE_OFFLINE' });

      assert.deepEqual(listener.calls, []);
    });

    it('should deliver nothing to any listener when removeAllListeners ran', async () => {
      const page = loadPage();
      const listener = recordCalls();
      await page.hotCodePush.addListener('downloadProgress', listener);

      await page.hotCodePush.removeAllListeners();
      page.sendNativeEvent('downloadProgress', { progress: 0.5 });

      assert.deepEqual(listener.calls, []);
    });

    it('should hand updateRolledBack to the first listener when the event arrived before any listener', async () => {
      const page = loadPage();
      const listener = recordCalls();
      page.sendNativeEvent('updateRolledBack', UPDATE_ROLLED_BACK_EVENT);

      await page.hotCodePush.addListener('updateRolledBack', listener);

      assert.deepEqual(listener.calls, [UPDATE_ROLLED_BACK_EVENT]);
    });

    it('should hand the retained updateRolledBack to the first listener alone when a second listener follows', async () => {
      const page = loadPage();
      const secondListener = recordCalls();
      page.sendNativeEvent('updateRolledBack', UPDATE_ROLLED_BACK_EVENT);
      await page.hotCodePush.addListener('updateRolledBack', recordCalls());

      await page.hotCodePush.addListener('updateRolledBack', secondListener);

      assert.deepEqual(secondListener.calls, []);
    });

    it('should retain updateRolledBack when its only listener was removed before the event arrived', async () => {
      const page = loadPage();
      const listener = recordCalls();
      const handle = await page.hotCodePush.addListener(
        'updateRolledBack',
        recordCalls(),
      );
      await handle.remove();
      page.sendNativeEvent('updateRolledBack', UPDATE_ROLLED_BACK_EVENT);

      await page.hotCodePush.addListener('updateRolledBack', listener);

      assert.deepEqual(listener.calls, [UPDATE_ROLLED_BACK_EVENT]);
    });

    it('should drop an event other than updateRolledBack when it arrived before any listener', async () => {
      const page = loadPage();
      const listener = recordCalls();
      page.sendNativeEvent('updateAvailable', { trigger: 'start' });

      await page.hotCodePush.addListener('updateAvailable', listener);

      assert.deepEqual(listener.calls, []);
    });
  });

  describe('the first render', () => {
    it('should signal the first render at the first animation frame when the page has loaded already', () => {
      const page = loadPage({ readyState: 'complete' });
      assert.equal(page.findNativeCall('notifyRendered'), undefined);

      page.runAnimationFrames();

      assert.deepEqual(page.findNativeCall('notifyRendered').args, [{}]);
    });

    it('should signal the first render at the first animation frame after the load event when the page is still loading', () => {
      const page = loadPage({ readyState: 'loading' });
      page.runAnimationFrames();
      assert.equal(page.findNativeCall('notifyRendered'), undefined);

      page.dispatchLoad();
      page.runAnimationFrames();

      assert.deepEqual(page.findNativeCall('notifyRendered').args, [{}]);
    });

    it('should leave no rejection unhandled when the native side fails the render signal', async () => {
      const page = loadPage({ readyState: 'complete' });
      const unhandledRejections = [];
      const recordRejection = reason => unhandledRejections.push(reason);
      process.on('unhandledRejection', recordRejection);
      page.runAnimationFrames();

      page.findNativeCall('notifyRendered').failure('HotCodePush is off');
      await setImmediate();

      process.off('unhandledRejection', recordRejection);
      assert.deepEqual(unhandledRejections, []);
    });
  });
});

/**
 * A page that loaded the plugin's module, over a Cordova bridge that records every native call for the test to answer.
 */
function loadPage({ readyState = 'complete' } = {}) {
  const animationFrames = [];
  const loadListeners = [];
  const nativeCalls = [];
  const exec = (success, failure, service, action, args) =>
    nativeCalls.push({ action, args, failure, service, success });
  const module = { exports: {} };
  compileFunction(MODULE_SOURCE, MODULE_PARAMETERS)(
    id => {
      assert.equal(id, 'cordova/exec');
      return exec;
    },
    module.exports,
    module,
    { readyState },
    {
      addEventListener: (type, listener) => {
        assert.equal(type, 'load');
        loadListeners.push(listener);
      },
    },
    callback => animationFrames.push(callback),
  );
  const findNativeCall = action =>
    nativeCalls.findLast(nativeCall => nativeCall.action === action);
  return {
    dispatchLoad: () => loadListeners.splice(0).forEach(listener => listener()),
    findNativeCall,
    hotCodePush: module.exports,
    nativeCalls,
    runAnimationFrames: () =>
      animationFrames.splice(0).forEach(callback => callback()),
    sendNativeEvent: (eventName, data) =>
      findNativeCall('listen').success({ data, eventName }),
  };
}

function recordCalls() {
  const listener = event => listener.calls.push(event);
  listener.calls = [];
  return listener;
}
