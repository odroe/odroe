import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

class FakeD1Statement {
  constructor(database, sql, values = []) {
    this.database = database;
    this.sql = sql;
    this.values = values;
  }

  bind(...values) {
    assert.equal(this instanceof FakeD1Statement, true, "bind lost its receiver");
    return new FakeD1Statement(this.database, this.sql, values);
  }

  run() {
    return this.database.run(this);
  }

  raw(options) {
    assert.deepEqual(options, { columnNames: true });
    return this.database.raw(this);
  }
}

class FakeD1Database {
  constructor(name) {
    this.name = name;
    this.records = [];
    this.tags = [];
    this.instanceValues = [];
    this.batchCalls = 0;
  }

  prepare(sql) {
    return new FakeD1Statement(this, sql);
  }

  async batch(statements) {
    this.batchCalls++;
    const snapshot = {
      records: [...this.records],
      tags: [...this.tags],
      instanceValues: [...this.instanceValues],
    };
    try {
      const results = [];
      for (const statement of statements) {
        results.push(await this.run(statement));
      }
      return results;
    } catch (error) {
      this.records = snapshot.records;
      this.tags = snapshot.tags;
      this.instanceValues = snapshot.instanceValues;
      throw error;
    }
  }

  async run(statement) {
    const { sql, values } = statement;
    if (sql.startsWith("CREATE TABLE records ")) {
      assert.deepEqual(values, []);
      return result(0, 0);
    }
    if (
      sql ===
      "INSERT INTO records (nullable, count, ratio, name, active, created_at, payload) VALUES (?, ?, ?, ?, ?, ?, ?)"
    ) {
      assert.equal(values.length, 7);
      assert.equal(values[0], null);
      assert.equal(values[1], 7);
      assert.equal(values[2], 1.5);
      assert.equal(values[3], "Odroe");
      assert.equal(values[4], 1);
      assert.equal(values[5], "2026-07-30T04:34:56.789Z");
      assert.ok(values[6] instanceof Uint8Array);
      assert.deepEqual([...values[6]], [0, 127, 255]);
      this.records.push({
        id: 1,
        nullable: values[0],
        count: values[1],
        ratio: values[2],
        name: values[3],
        active: values[4],
        createdAt: values[5],
        payload: new Uint8Array(values[6]),
      });
      return result(1, 1);
    }
    if (sql === "UPDATE records SET active = ? WHERE id = ?") {
      assert.deepEqual(values, [0, 1]);
      this.records[0].active = 0;
      return result(1, 0);
    }
    if (sql === "INSERT INTO tags (slug) VALUES (?)") {
      const [slug] = values;
      if (this.tags.includes(slug)) {
        throw new Error(`D1_CONSTRAINT: UNIQUE constraint failed: ${slug}`);
      }
      this.tags.push(slug);
      return result(1, this.tags.length);
    }
    if (sql === "INSERT INTO instance_values (value) VALUES (?)") {
      await new Promise((resolve) => setTimeout(resolve, this.name === "A" ? 2 : 0));
      this.instanceValues.push(values[0]);
      return result(1, this.instanceValues.length);
    }
    if (sql === "INSERT unsafe_metadata") {
      return result(1, 9007199254740992);
    }
    if (sql === "SELECT row_returning") {
      return {
        ...result(0, 0),
        results: [{ value: 1 }],
      };
    }
    throw new Error(
      `D1_ERROR: unsupported fake SQL: ${sql}; values=${values.join(",")}`,
    );
  }

  async raw(statement) {
    const { sql, values } = statement;
    if (
      sql ===
      "SELECT id, nullable, count, ratio, name, active, created_at, payload FROM records"
    ) {
      const rows = this.records.map((record) => [
        record.id,
        record.nullable,
        record.count,
        record.ratio,
        record.name,
        record.active,
        record.createdAt,
        [...record.payload],
      ]);
      return [
        ["id", "nullable", "count", "ratio", "name", "active", "created_at", "payload"],
        ...rows,
      ];
    }
    if (sql === "SELECT 1 AS id, 2 AS id, 3 AS value") {
      return [["id", "id", "value"], [1, 2, 3]];
    }
    if (sql === "SELECT '?' AS literal, ? AS value -- ?") {
      assert.deepEqual(values, [7]);
      return [["literal", "value"], ["?", 7]];
    }
    if (sql === "SELECT COUNT(*) AS count FROM tags") {
      return [["count"], [this.tags.length]];
    }
    if (sql === "SELECT invalid_number") {
      return [["value"], [Number.POSITIVE_INFINITY]];
    }
    if (sql === "SELECT instance_value") {
      return [["instance_value"], [this.instanceValues.at(-1)]];
    }
    throw new Error(`D1_ERROR: unsupported fake SQL: ${sql}`);
  }
}

function result(changes, lastRowId) {
  return {
    success: true,
    meta: {
      changes,
      last_row_id: lastRowId,
    },
    results: [],
  };
}

const bindingA = new FakeD1Database("A");
const bindingB = new FakeD1Database("B");
globalThis.self = globalThis;
globalThis.d1BindingA = bindingA;
globalThis.d1BindingB = bindingB;

let resolveSmoke;
let rejectSmoke;
const smoke = new Promise((resolve, reject) => {
  resolveSmoke = resolve;
  rejectSmoke = reject;
});
globalThis.d1SmokePassed = resolveSmoke;
globalThis.d1SmokeFailed = (message) => rejectSmoke(new Error(message));

await import(pathToFileURL(process.argv[2]).href);
let timeout;
try {
  await Promise.race([
    smoke,
    new Promise((_, reject) => {
      timeout = setTimeout(
        () => reject(new Error("D1 smoke timed out")),
        10_000,
      );
    }),
  ]);
} finally {
  clearTimeout(timeout);
}

assert.equal(bindingA.batchCalls, 2, "empty atomicWrite reached D1");
assert.equal(bindingB.batchCalls, 0);
assert.deepEqual(bindingA.instanceValues, ["first"]);
assert.deepEqual(bindingB.instanceValues, ["second"]);

console.log("database_d1 fake-binding smoke passed");
