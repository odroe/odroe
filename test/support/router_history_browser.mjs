import assert from 'node:assert/strict';

// A real browser session without mocking flutter/navigation. The native go
// wrapper records calls; only explicit fault cases drop or throw one call.
const [debugPort, origin] = process.argv.slice(2);
const pause = (ms) => new Promise(resolve => setTimeout(resolve, ms));
async function until(read, predicate, label) {
  const deadline = Date.now() + 30000;
  let value;
  do {
    value = await read();
    if (predicate(value)) return value;
    await pause(50);
  } while (Date.now() < deadline);
  throw new Error(`${label}: ${JSON.stringify(value)}`);
}

async function scenario(hash, initial, test) {
  const target = await (await fetch(
    `http://127.0.0.1:${debugPort}/json/new?about:blank`, {method: 'PUT'},
  )).json();
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, {once: true});
    socket.addEventListener('error', reject, {once: true});
  });
  let id = 0;
  const pending = new Map();
  socket.addEventListener('message', event => {
    const data = JSON.parse(event.data);
    if (!data.id) return;
    const task = pending.get(data.id);
    pending.delete(data.id);
    if (data.error) task.reject(new Error(JSON.stringify(data.error)));
    else task.resolve(data.result);
  });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const key = ++id;
    pending.set(key, {resolve, reject});
    socket.send(JSON.stringify({id: key, method, params}));
  });
  const evaluate = async expression => {
    const response = await send('Runtime.evaluate', {
      expression, awaitPromise: true, returnByValue: true,
    });
    if (response.exceptionDetails) throw new Error(JSON.stringify(response.exceptionDetails));
    return response.result.value;
  };
  const contextLost = error => /Execution context was destroyed|Cannot find context with specified id/.test(error.message);
  const snapshot = () => evaluate(`({
    ...(typeof routeHistorySnapshot === 'function' ? JSON.parse(routeHistorySnapshot()) : {}),
    url: ${hash ? "location.hash.slice(1) || '/'" : 'location.pathname + location.search'},
    origin: location.origin,
    title: document.title,
    length: history.length,
    boot: performance.timeOrigin
  })`).catch(error => {
    if (contextLost(error)) return {documentChanging: true};
    throw error;
  });
  const sequence = [];
  const at = async (label, route) => {
    await until(snapshot, s => s?.route === route && s.url === route, label);
    // Allow Navigator's removal callback and frame reporting to settle.
    await pause(350);
    const settled = await snapshot();
    assert.equal(settled.route, route, label);
    assert.equal(settled.url, route, label);
    sequence.push({step: label, ...settled});
    return settled;
  };
  const act = async (action, mayUnload = false) => {
    try { return await evaluate(`routeHistoryAction(${JSON.stringify(action)})`); }
    catch (error) { if (!mayUnload || !contextLost(error)) throw error; }
  };
  const traverse = async direction => {
    await evaluate(`new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Missing popstate')), 5000);
      addEventListener('popstate', () => { clearTimeout(timer); setTimeout(resolve, 100); }, {once:true});
      history.${direction}();
    })`);
  };
  try {
    await send('Page.enable');
    // A real document on a different origin precedes every app entry. An
    // initial deep-link pop must never traverse to this unowned predecessor.
    await send('Page.navigate', {url: origin.replace('127.0.0.1', 'localhost') + '/outside'});
    await until(() => evaluate('document.title'), title => title === 'Outside', 'outside predecessor');
    await send('Page.addScriptToEvaluateOnNewDocument', {
      source: `globalThis.routeHistoryHash = ${hash};
        const nativeGo = history.go.bind(history);
        globalThis.routeHistoryNativeCalls = 0;
        globalThis.routeHistoryNativePending = false;
        addEventListener('popstate', () => { routeHistoryNativePending = false; });
        history.go = (delta) => {
          routeHistoryNativeCalls++;
          routeHistoryNativePending = true;
          const fault = globalThis.routeHistoryMoveFault;
          globalThis.routeHistoryMoveFault = null;
          if (fault === 'drop') return;
          if (fault === 'throw') throw new Error('injected native go failure');
          const result = nativeGo(delta);
          const backs = globalThis.routeHistoryBacksAfterGo || 0;
          globalThis.routeHistoryBacksAfterGo = 0;
          for (let i = 0; i < backs; i++) history.back();
          return result;
        };`,
    });
    await send('Page.navigate', {url: origin + (hash ? '/#' : '') + initial});
    const initialState = await at('initial', initial);
    const waiting = () => until(snapshot, s => s?.waiting, 'traversal gate');
    const reload = async route => {
      const before = await snapshot();
      await send('Page.reload');
      await until(snapshot, s => s.boot !== before.boot && s.route === route, 'reload');
      return at('reloaded', route);
    };
    const outside = () => until(
      () => send('Page.getFrameTree'),
      state => state.frameTree.frame.url === origin.replace('127.0.0.1', 'localhost') + '/outside',
      'explicit browser navigation outside',
    );
    await test({at, act, traverse, initialState, waiting, snapshot, reload, outside});
  } finally {
    console.log(JSON.stringify({strategy: hash ? 'hash' : 'path', sequence}));
    socket.close();
    await fetch(`http://127.0.0.1:${debugPort}/json/close/${target.id}`);
  }
}

const list = '/posts?authorId=7';
const cases = {
  async 'app pop consumes pushed entry'({at, act, traverse}) {
    await act('list');
    const before = await at('list', list);
    await act('draft');
    await act('push');
    await at('push', '/post/1');
    await act('pop');
    const popped = await at('app pop', list);
    assert.deepEqual(popped.results, ['saved']);
    assert.equal(popped.mount, before.mount);
    assert.equal(popped.draft, 1);
    await traverse('back');
    await at('browser Back', '/');
    await traverse('forward'); await at('Forward to list', list);
    await traverse('forward');
    const reopened = await at('Forward reopens detail', '/post/1');
    assert.deepEqual(reopened.results, ['saved']);
  },
  async 'browser Back and Forward restore URLs'({at, act, traverse}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await traverse('back');
    const back = await at('browser Back', list);
    assert.deepEqual(back.results, [null]);
    await traverse('back'); await at('browser Back', '/');
    await traverse('forward'); await at('browser Forward', list);
    await traverse('forward');
    const forward = await at('browser Forward', '/post/1');
    assert.deepEqual(forward.results, [null]);
  },
  async 'replace keeps one top entry'({at, act, traverse}) {
    await act('list'); await at('list', list);
    await act('push'); const pushed = await at('push', '/post/1');
    await act('replace'); const replaced = await at('replace', '/post/2');
    assert.equal(replaced.length, pushed.length);
    assert.deepEqual(replaced.results, [null]);
    await act('pop'); await at('app pop', list);
    await traverse('back'); await at('browser Back', '/');
  },
  async 'nested push preserves parent search'({at, act, traverse}) {
    await act('list'); await at('list', list);
    await act('nested'); await at('nested push', '/posts/edit/1?authorId=7');
    await act('pop'); await at('app pop', list);
    await traverse('back'); await at('browser Back', '/');
  },
  async 'shell push returns to the retained list'({at, act, traverse}) {
    await act('list'); const before = await at('list', list);
    await act('draft'); await act('shell'); await at('shell push', '/workspace/edit');
    await act('pop'); const popped = await at('shell pop', list);
    assert.equal(popped.mount, before.mount);
    assert.equal(popped.draft, 1);
    assert.deepEqual(popped.results, ['saved']);
    await traverse('back'); await at('Back', '/');
  },
  async 'same URL pushes have distinct entries'({at, act, traverse}) {
    await act('list'); await at('list', list);
    await act('push'); const first = await at('first push', '/post/1');
    await act('push'); const second = await at('same URL push', '/post/1');
    assert.equal(second.length, first.length + 1);
    await act('pop'); await at('first same URL pop', '/post/1');
    await act('pop'); const popped = await at('second same URL pop', list);
    assert.deepEqual(popped.results, ['saved', 'saved']);
    await traverse('back'); await at('Back', '/');
  },
  async 'coalesced pushes only traverse committed entries'({at, act, traverse}) {
    await act('list'); const before = await at('list', list);
    await act('batchPush'); const pushed = await at('two pushes in one frame', '/post/3');
    assert.equal(pushed.length, before.length + 1);
    await act('pop'); const middle = await at('pop unreported intermediate', '/post/1');
    assert.equal(middle.traversals, 0);
    await act('pop'); const popped = await at('pop to committed list', list);
    assert.deepEqual(popped.results, ['saved', 'saved']);
    assert.equal(popped.traversals, 1);
    await traverse('back'); await at('Back', '/');
  },
  async 'browser-pruned entries never send app pop outside'({at, act, traverse, reload}) {
    await act('list'); const before = await at('list', list);
    await act('draft');
    // Chrome limits retained history. Keep the loop bounded while exercising
    // removal of old same-document entries behind a cross-origin predecessor.
    let saturated;
    for (let i = 0; i < 55; i++) {
      await act(i % 2 ? 'pushNext' : 'push');
      saturated = await at('capacity push ' + i, i % 2 ? '/post/3' : '/post/1');
    }
    assert.ok(saturated.length < before.length + 55, 'exercise actual browser retention, without assuming its capacity');
    for (let i = 54; i >= 0; i--) {
      await act('pop');
      await at('capacity pop ' + i, i === 0 ? list : (i % 2 ? '/post/1' : '/post/3'));
    }
    const restored = await at('retained list after capacity', list);
    assert.equal(restored.mount, before.mount);
    assert.equal(restored.draft, 1);
    assert.deepEqual(restored.results, Array(55).fill('saved'));
    assert.equal(restored.traversals, 0, 'retired distances are never reused');
    await traverse('back'); await at('Back sees retained browser detail', '/post/3');
    await traverse('forward');
    const forward = await at('Forward restores URL only', list);
    assert.deepEqual(forward.results, Array(55).fill('saved'));
    await act('pushNext'); await at('new push after capacity', '/post/3');
    await act('pop');
    const popped = await at('new pop after capacity', list);
    assert.deepEqual(popped.results, Array(56).fill('saved'));
    assert.equal(popped.traversals, 0);
    const reloaded = await reload(list);
    assert.deepEqual(reloaded.results, []);
    await act('pushNext'); await at('post-reload saturated push', '/post/3');
    await act('pop'); const reloadedPop = await at('post-reload saturated pop', list);
    assert.deepEqual(reloadedPop.results, ['saved']);
    assert.equal(reloadedPop.traversals, 0);
  },
  async 'consecutive pops during asynchronous traversal'({at, act, waiting, traverse}) {
    await act('list'); await at('list', list);
    await act('push'); await at('first push', '/post/1');
    await act('pushNext'); await at('second push', '/post/3');
    await act('hold'); await act('pop'); await waiting();
    await pause(350);
    await act('pop');
    await act('release');
    const popped = await at('two pops', list);
    assert.deepEqual(popped.results, ['saved', 'saved']);
    assert.equal(popped.traversals, 2);
    await traverse('back'); await at('Back after two pops', '/');
  },
  async 'browser Back supersedes delayed Flutter notifications'({at, act, waiting, traverse}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('hold'); await act('pop'); await waiting();
    await traverse('back');
    await act('release');
    await at('release after Back', '/');
  },
  async 'a delayed custom go hook cannot submit a stale move'({at, act, traverse}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('holdGo'); await act('pop');
    const popped = await at('native move submitted without custom go', list);
    assert.equal(popped.strategyGoCalls, 0);
    await traverse('back');
    await act('release');
    await at('release never submits a late move', '/');
  },
  async 'native traversal and browser Back overlap'({at, act}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('backAfterGo'); await act('pop');
    await at('native go plus Back', '/');
  },
  async 'native traversal and two browser Backs preserve native ordering'({at, act, outside}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('twiceBackAfterGo'); await act('pop', true);
    await outside();
  },
  async 'new push survives late popstate'({at, act, waiting, traverse, snapshot}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('hold'); await act('pop'); await waiting();
    await act('pushNext');
    await until(snapshot, s => s.route === '/post/3', 'new push is immediate');
    await act('release');
    await at('new push after late popstate', '/post/3');
    await act('pop');
    const popped = await at('pop new detail', list);
    assert.deepEqual(popped.results, ['saved', 'saved']);
    await traverse('back'); await at('Back', '/');
  },
  async 'new go survives late popstate'({at, act, waiting, traverse, snapshot}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('hold'); await act('pop'); await waiting();
    await act('goNext');
    await until(snapshot, s => s.route === '/post/3', 'new go is immediate');
    await act('release');
    await at('new go after late popstate', '/post/3');
    await traverse('back'); await at('Back to prior list', list);
    await traverse('back'); await at('Back to home', '/');
  },
  async 'delegate listener can navigate during pop'({at, act, waiting, traverse}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('hold'); await act('reentrantPush'); await waiting();
    await act('release');
    const pushed = await at('reentrant push', '/post/3');
    assert.equal(pushed.requestedDuringNativeMove, true);
    await act('pop');
    const popped = await at('pop reentrant detail', list);
    assert.deepEqual(popped.results, ['saved', 'saved']);
    await traverse('back'); await at('Back', '/');
  },
  async 'reentrant go is requested before native popstate arrives'({at, act, waiting, traverse}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('hold'); await act('reentrantGo'); await waiting();
    await act('release');
    const moved = await at('reentrant go', '/post/3');
    assert.equal(moved.requestedDuringNativeMove, true);
    assert.deepEqual(moved.results, ['saved']);
    await traverse('back'); await at('Back to retained history', list);
    await traverse('back'); await at('Back to home', '/');
  },
  async 'refresh does not revive previous router ownership'({at, act, reload, traverse}) {
    await act('list'); await at('list', list);
    await act('nested'); await at('nested push', '/posts/edit/1?authorId=7');
    await reload('/posts/edit/1?authorId=7');
    await act('pop'); const popped = await at('reloaded parent pop', list);
    assert.equal(popped.traversals, 0);
    assert.deepEqual(popped.results, []);
    await traverse('back'); await at('Back to previous runtime URL', list);
    await traverse('forward'); await at('Forward after refresh', list);
    await act('pushNext'); await at('new owned push', '/post/3');
    await act('pop'); const again = await at('new owned pop', list);
    assert.equal(again.traversals, 1);
    assert.deepEqual(again.results, ['saved']);
  },
  async 'a retired notification cannot complete a new same-URL push'({at, act, traverse}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('pushNext'); await at('second push', '/post/3');
    await traverse('back'); await at('Back', '/post/1');
    await act('captureNotification');
    await act('push'); await at('fresh same-URL push', '/post/1');
    await act('replayNotification');
    const active = await at('retired notification ignored', '/post/1');
    assert.deepEqual(active.results, [null, null]);
    await act('pop'); const popped = await at('new Future still completes normally', '/post/1');
    assert.deepEqual(popped.results, [null, null, 'saved']);
  },
  async 'a native move without an event does not block queued navigation'({at, act}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('dropMove'); await act('pop'); await act('pushNext');
    await at('queued push after missing event', '/post/3');
    await act('pop'); const state = await at('recovery pop', list);
    assert.deepEqual(state.results, ['saved', 'saved']);
    assert.deepEqual(state.errors, []);
  },
  async 'a failed native move recovers without stale ownership'({at, act}) {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('failMove'); await act('pop');
    const fallback = await at('replace after failed move', list);
    assert.ok(fallback.errors.length > 0);
    await act('pushNext'); await at('next push', '/post/3');
    await act('pop'); const state = await at('next pop', list);
    assert.deepEqual(state.results, ['saved', 'saved']);
  },
};
for (const count of [1, 2]) {
  cases[`push truncates ${count} known Forward entries`] = async ({at, act, traverse}) => {
    await act('list'); await at('list', list);
    await act('push'); await at('push', '/post/1');
    await act('pushNext'); const before = await at('second push', '/post/3');
    for (let i = 0; i < count; i++) await traverse('back');
    const target = count === 1 ? '/post/1' : list;
    await at('Back before push', target);
    await act('pushNext'); const pushed = await at('push replaces Forward branch', '/post/3');
    assert.equal(pushed.length, before.length + 1 - count);
    await act('pop'); const popped = await at('known entry still traversable', target);
    assert.equal(popped.traversals, 1);
    assert.deepEqual(popped.results, [null, null, 'saved']);
    await traverse('forward'); const forward = await at('Forward to new entry', '/post/3');
    assert.deepEqual(forward.results, [null, null, 'saved']);
  };
}
for (const fault of ['failWrite', 'failWriteAfter']) {
  cases[`history write failure: ${fault}`] = async ({at, act, snapshot}) => {
    await act('list'); await at('list', list);
    await act(fault); await act('push');
    await until(snapshot, s => s.route === '/post/1' && s.errors.length > 0, 'observed write failure');
    await act('pop'); const fallback = await at('local pop after write failure', list);
    assert.equal(fallback.traversals, 0);
    assert.deepEqual(fallback.results, ['saved']);
    await act('pushNext'); await at('recovery push', '/post/3');
    await act('pop'); const recovered = await at('recovery pop', list);
    assert.equal(recovered.traversals, 1);
    assert.deepEqual(recovered.results, ['saved', 'saved']);
  };
}
let failed = 0;
for (const hash of [false, true]) {
  for (const [name, test] of Object.entries(cases)) {
    if (process.env.ODROE_HISTORY_CASE && !name.includes(process.env.ODROE_HISTORY_CASE)) continue;
    try {
      await scenario(hash, '/', test);
      console.log(`PASS ${hash ? 'hash' : 'path'}: ${name}`);
    } catch (error) {
      failed++;
      console.error(`FAIL ${hash ? 'hash' : 'path'}: ${name}: ${error.stack}`);
    }
  }
  if (process.env.ODROE_HISTORY_CASE) continue;
  try {
    await scenario(hash, '/posts/edit/1?authorId=7', async ({at, act, initialState}) => {
      await act('pop');
      const state = await at('deep link parent pop', list);
      assert.deepEqual(state.results, []);
      // No owned predecessor: replace the initial entry instead of leaving.
      assert.equal(state.length, initialState.length);
      assert.equal(state.traversals, 0);
      await act('pop');
      await at('repeated deep link pop stays in app', list);
    });
    console.log(`PASS ${hash ? 'hash' : 'path'}: initial deep link`);
  } catch (error) {
    failed++;
    console.error(`FAIL initial deep link: ${error.stack}`);
  }
}
assert.equal(failed, 0, `${failed} real browser history scenarios failed`);
