import assert from 'node:assert/strict';

// A real browser session, without mocking flutter/navigation or history APIs.
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
    if (data.error) task.reject(data.error);
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
  const snapshot = () => evaluate(`typeof routeHistorySnapshot === 'function' ? {
    ...JSON.parse(routeHistorySnapshot()),
    url: ${hash ? "location.hash.slice(1) || '/'" : 'location.pathname + location.search'},
    length: history.length
  } : null`);
  const sequence = [];
  const at = async (label, route) => {
    const state = await until(snapshot, s => s?.route === route && s.url === route, label);
    // Allow Navigator's removal callback and frame reporting to settle.
    await pause(350);
    const settled = await snapshot();
    assert.equal(settled.route, route, label);
    assert.equal(settled.url, route, label);
    sequence.push({step: label, ...settled});
    return state;
  };
  const act = action => evaluate(`routeHistoryAction(${JSON.stringify(action)})`);
  const traverse = async direction => {
    await evaluate(`new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Missing popstate')), 5000);
      addEventListener('popstate', () => { clearTimeout(timer); setTimeout(resolve, 100); }, {once:true});
      history.${direction}();
    })`);
  };
  try {
    await send('Page.enable');
    await send('Page.addScriptToEvaluateOnNewDocument', {
      source: `globalThis.routeHistoryHash = ${hash};`,
    });
    await send('Page.navigate', {url: origin + (hash ? '/#' : '') + initial});
    const initialState = await at('initial', initial);
    await test({at, act, traverse, initialState});
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
};
let failed = 0;
for (const hash of [false, true]) {
  for (const [name, test] of Object.entries(cases)) {
    try {
      await scenario(hash, '/', test);
      console.log(`PASS ${hash ? 'hash' : 'path'}: ${name}`);
    } catch (error) {
      failed++;
      console.error(`FAIL ${hash ? 'hash' : 'path'}: ${name}: ${error.stack}`);
    }
  }
  try {
    await scenario(hash, '/posts/edit/1?authorId=7', async ({at, act, initialState}) => {
      await act('pop');
      const state = await at('deep link parent pop', list);
      assert.deepEqual(state.results, []);
      // No owned predecessor: replace the initial entry instead of leaving.
      assert.equal(state.length, initialState.length);
    });
    console.log(`PASS ${hash ? 'hash' : 'path'}: initial deep link`);
  } catch (error) {
    failed++;
    console.error(`FAIL initial deep link: ${error.stack}`);
  }
}
assert.equal(failed, 0, `${failed} real browser history scenarios failed`);
