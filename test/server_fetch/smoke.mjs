import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

globalThis.self = globalThis;
await import(pathToFileURL(process.argv[2]).href);

const handler = globalThis.__odroeFetch;
assert.equal(typeof handler, "function");

const encoder = new TextEncoder();
const decoder = new TextDecoder();
Object.assign(globalThis, {
  reportCount: 0,
  reportMethod: "",
  reportPath: "",
  reportError: "",
  reportStack: "",
  reportCompleted: false,
});

function environment() {
  return {
    marker: "edge-binding",
    produced: 0,
    responseCancelled: false,
    responseCancelStarted: false,
    releaseResponseCancel: false,
  };
}

function executionContext() {
  const tasks = [];
  const context = {
    waitUntil(promise) {
      assert.equal(this, context, "ctx.waitUntil lost its receiver");
      tasks.push(promise);
    },
  };
  return { context, tasks };
}

async function invoke(request, env = environment()) {
  const { context, tasks } = executionContext();
  const response = await handler(request, env, context);
  assert.ok(response instanceof Response);
  return { response, env, tasks };
}

async function rejection(promise) {
  return promise.then(
    () => assert.fail("expected promise to reject"),
    (error) => error,
  );
}

{
  const valid = await invoke(
    new Request("https://example.test/typed-search?page=2"),
  );
  assert.equal(valid.response.status, 200);
  assert.deepEqual(await valid.response.json(), { page: 2 });

  globalThis.reportCount = 0;
  const invalid = await invoke(
    new Request("https://example.test/typed-search?page=invalid", {
      headers: { accept: "application/json" },
    }),
  );
  assert.equal(invalid.response.status, 400);
  const frame = await invalid.response.json();
  assert.equal(frame.type, "error");
  assert.equal(frame.message, 'Search parameter "page" must be an integer.');
  assert.equal(invalid.response.headers.get("vary"), "Accept");
  assert.equal(globalThis.reportCount, 0);
}

{
  const chunks = ["streamed ", "request ", "body"];
  let pulls = 0;
  const body = new ReadableStream({
    pull(controller) {
      if (pulls === chunks.length) {
        controller.close();
      } else {
        controller.enqueue(encoder.encode(chunks[pulls]));
      }
      pulls++;
    },
  });
  const { response } = await invoke(
    new Request("https://example.test/echo?mode=stream", {
      method: "POST",
      headers: { "x-request": "request-header" },
      body,
      duplex: "half",
    }),
  );

  assert.equal(response.status, 201);
  assert.equal(response.statusText, "Created by Odroe");
  assert.equal(response.headers.get("x-method"), "POST");
  assert.equal(response.headers.get("x-query"), "mode=stream");
  assert.equal(response.headers.get("x-request-header"), "request-header");
  assert.equal(response.headers.get("x-binding"), "edge-binding");
  assert.equal(response.headers.get("x-multi"), "one, two");
  assert.deepEqual(response.headers.getSetCookie(), ["a=1", "b=2"]);
  assert.equal(await response.text(), chunks.join(""));
  assert.ok(pulls >= chunks.length);
}

{
  const calls = Array.from({ length: 64 }, async (_, index) => {
    const env = environment();
    env.marker = `binding-${index}`;
    const { response } = await invoke(
      new Request(`https://example.test/echo?id=${index}`),
      env,
    );
    assert.equal(response.headers.get("x-binding"), `binding-${index}`);
    assert.equal(response.headers.get("x-query"), `id=${index}`);
    assert.equal(await response.text(), "");
  });
  await Promise.all(calls);
}

{
  let cancelled = false;
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode("first"));
      controller.enqueue(encoder.encode("unread"));
    },
    cancel() {
      cancelled = true;
    },
  });
  const { response } = await invoke(
    new Request("https://example.test/request-cancel", {
      method: "POST",
      body,
      duplex: "half",
    }),
  );

  assert.equal(await response.text(), "first");
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(cancelled, true);
}

{
  const chunks = ["lazy ", "request ", "stream"];
  let index = 0;
  const body = new ReadableStream({
    pull(controller) {
      if (index == chunks.length) {
        controller.close();
      } else {
        controller.enqueue(encoder.encode(chunks[index]));
      }
      index++;
    },
  });
  const { response } = await invoke(
    new Request("https://example.test/request-stream", {
      method: "POST",
      body,
      duplex: "half",
    }),
  );
  assert.equal(await response.text(), chunks.join(""));
}

{
  const controller = new AbortController();
  const { context } = executionContext();
  const responsePromise = handler(
    new Request("https://example.test/abort", {
      signal: controller.signal,
    }),
    environment(),
    context,
  );
  controller.abort("client disconnected");
  const response = await responsePromise;

  assert.equal(response.status, 499);
  assert.equal(await response.text(), "cancelled");
}

{
  const env = environment();
  const { response } = await invoke(
    new Request("https://example.test/stream"),
    env,
  );

  await new Promise((resolve) => setImmediate(resolve));
  assert.ok(env.produced < 5, "response was produced without backpressure");

  const reader = response.body.getReader();
  const first = await reader.read();
  assert.equal(first.done, false);
  assert.equal(decoder.decode(first.value), "0");
  await new Promise((resolve) => setImmediate(resolve));
  assert.ok(env.produced < 5, "response ignored downstream backpressure");

  await reader.cancel("client stopped reading");
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(env.responseCancelled, true);
}

{
  const env = environment();
  globalThis.reportCount = 0;
  globalThis.reportCompleted = false;
  const { response, tasks } = await invoke(
    new Request("https://example.test/error-cancel"),
    env,
  );
  const reader = response.body.getReader();
  const first = await reader.read();
  assert.equal(decoder.decode(first.value), "first");
  const terminalRead = reader.read().catch(() => null);
  while (!env.responseCancelStarted) {
    await new Promise((resolve) => setImmediate(resolve));
  }

  let downstreamCancelSettled = false;
  const downstreamCancel = reader.cancel().then(
    () => {
      downstreamCancelSettled = true;
    },
    () => {
      downstreamCancelSettled = true;
    },
  );
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(downstreamCancelSettled, false);
  env.releaseResponseCancel = true;
  await downstreamCancel;
  await terminalRead;
  await Promise.all(tasks);
  assert.equal(env.responseCancelled, true);
  assert.equal(globalThis.reportCount, 1);
  assert.equal(globalThis.reportMethod, "GET");
  assert.equal(globalThis.reportPath, "/error-cancel");
  assert.equal(globalThis.reportCompleted, true);
}

{
  const env = environment();
  const { response } = await invoke(
    new Request("https://example.test/head", { method: "HEAD" }),
    env,
  );
  assert.equal(response.status, 200);
  assert.equal(response.body, null);
  assert.equal(env.responseCancelled, true);
}

for (const status of [204, 205, 304]) {
  const env = environment();
  const { response } = await invoke(
    new Request(`https://example.test/status/${status}`),
    env,
  );
  assert.equal(response.status, status);
  assert.equal(response.body, null);
  assert.equal(env.responseCancelled, true);
}

{
  const { response, tasks } = await invoke(
    new Request("https://example.test/wait"),
  );
  assert.equal(await response.text(), "scheduled");
  assert.equal(tasks.length, 2);
  await Promise.all(tasks);
}

{
  let requestCancelled = false;
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode("unused"));
    },
    cancel() {
      requestCancelled = true;
    },
  });
  const { response } = await invoke(
    new Request("https://example.test/wait", {
      method: "POST",
      body,
      duplex: "half",
    }),
  );
  assert.equal(await response.text(), "scheduled");
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(requestCancelled, true);
}

{
  let releaseRequestCancel;
  let requestCancelStarted = false;
  const requestCancelGate = new Promise((resolve) => {
    releaseRequestCancel = resolve;
  });
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode("unused"));
    },
    cancel() {
      requestCancelStarted = true;
      return requestCancelGate;
    },
  });
  const { response } = await invoke(
    new Request("https://example.test/wait", {
      method: "POST",
      body,
      duplex: "half",
    }),
  );
  const reader = response.body.getReader();
  const first = await reader.read();
  assert.equal(decoder.decode(first.value), "scheduled");
  while (!requestCancelStarted) {
    await new Promise((resolve) => setImmediate(resolve));
  }

  let downstreamCancelSettled = false;
  const downstreamCancel = reader.cancel().then(() => {
    downstreamCancelSettled = true;
  });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(downstreamCancelSettled, false);
  releaseRequestCancel();
  await downstreamCancel;
  assert.equal(downstreamCancelSettled, true);
}

{
  let requestCancelled = false;
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode("unsupported"));
    },
    cancel() {
      requestCancelled = true;
    },
  });
  const { response } = await invoke(
    new Request("https://example.test/unknown", {
      method: "FOO",
      body,
      duplex: "half",
    }),
  );
  assert.equal(response.status, 501);
  assert.equal(await response.text(), "");
  assert.equal(requestCancelled, true);
}

{
  globalThis.reportCount = 0;
  globalThis.reportCompleted = false;
  const { response, tasks } = await invoke(
    new Request("https://example.test/invalid-response-stream"),
  );
  const failure = await rejection(response.body.getReader().read());
  assert.equal(globalThis.reportCount, 1);
  assert.equal(globalThis.reportMethod, "GET");
  assert.equal(globalThis.reportPath, "/invalid-response-stream");
  assert.equal(globalThis.reportError, "Bad state: byte conversion failed");
  assert.ok(globalThis.reportStack.length > 0);
  assert.equal(globalThis.reportStack, failure.stack);
  assert.equal(tasks.length, 2);
  await Promise.all(tasks);
  assert.equal(globalThis.reportCompleted, true);
}

{
  const env = environment();
  globalThis.reportCount = 0;
  globalThis.reportCompleted = false;
  let requestCancelled = false;
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode("invalid header"));
    },
    cancel() {
      requestCancelled = true;
    },
  });
  const { context, tasks } = executionContext();
  const failure = await rejection(
    handler(
      new Request("https://example.test/invalid-response-header", {
        method: "POST",
        body,
        duplex: "half",
      }),
      env,
      context,
    ),
  );
  assert.equal(globalThis.reportCount, 1);
  assert.equal(globalThis.reportMethod, "POST");
  assert.equal(globalThis.reportPath, "/invalid-response-header");
  assert.match(globalThis.reportError, /invalid header name/i);
  assert.ok(globalThis.reportStack.length > 0);
  assert.equal(globalThis.reportStack, failure.stack);
  assert.equal(tasks.length, 2);
  await Promise.all(tasks);
  assert.equal(globalThis.reportCompleted, true);
  assert.equal(env.responseCancelled, true);
  assert.equal(requestCancelled, true);
}

{
  const env = environment();
  globalThis.reportCount = 0;
  globalThis.reportCompleted = false;
  let requestCancelled = false;
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode("invalid"));
    },
    cancel() {
      requestCancelled = true;
    },
  });
  const { context, tasks } = executionContext();
  const failure = await rejection(
    handler(
      new Request("https://example.test/invalid-response", {
        method: "POST",
        body,
        duplex: "half",
      }),
      env,
      context,
    ),
  );
  assert.equal(globalThis.reportCount, 1);
  assert.equal(globalThis.reportMethod, "POST");
  assert.equal(globalThis.reportPath, "/invalid-response");
  assert.ok(globalThis.reportError.length > 0);
  assert.ok(globalThis.reportStack.length > 0);
  assert.equal(globalThis.reportStack, failure.stack);
  assert.equal(tasks.length, 2);
  await Promise.all(tasks);
  assert.equal(globalThis.reportCompleted, true);
  assert.equal(env.responseCancelled, true);
  assert.equal(requestCancelled, true);
}

console.log("server_fetch smoke passed");
