import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

globalThis.self = globalThis;
await import(pathToFileURL(process.argv[2]).href);

const handler = globalThis.__odroeFetch;
assert.equal(typeof handler, "function");

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function environment() {
  return {
    marker: "edge-binding",
    produced: 0,
    responseCancelled: false,
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
  const env = environment();
  const { context, tasks } = executionContext();
  await assert.rejects(
    handler(
      new Request("https://example.test/invalid-response"),
      env,
      context,
    ),
  );
  await Promise.all(tasks);
  assert.equal(env.responseCancelled, true);
}

console.log("server_fetch smoke passed");
