import { test } from "node:test";
import assert from "node:assert/strict";
import { ArenaCache, SqliteCachePersistence } from "../src/cache/cache.ts";
import { Database } from "../src/db/database.ts";
import { migrate } from "../src/db/schema.ts";

test("cache set/get/delete and stats", () => {
  const cache = new ArenaCache({ defaultTtlMs: 1000 });
  cache.set("a", 1);
  assert.equal(cache.get("a"), 1);
  assert.equal(cache.get("missing"), undefined);
  cache.delete("a");
  assert.equal(cache.get("a"), undefined);

  const stats = cache.stats();
  assert.equal(stats.hits, 1);
  assert.equal(stats.misses, 2); // "missing" + the post-delete lookup
});

test("cache honors TTL expiry", () => {
  let clock = 0;
  const cache = new ArenaCache({ now: () => clock });
  cache.set("temp", "v", 100);
  clock = 50;
  assert.equal(cache.get("temp"), "v");
  clock = 150;
  assert.equal(cache.get("temp"), undefined);
});

test("cache evicts least recently used beyond maxEntries", () => {
  const cache = new ArenaCache({ maxEntries: 2 });
  cache.set("k1", 1);
  cache.set("k2", 2);
  assert.equal(cache.get("k1"), 1); // k1 now most recently used
  cache.set("k3", 3); // evicts k2
  assert.equal(cache.get("k2"), undefined);
  assert.equal(cache.get("k1"), 1);
  assert.equal(cache.get("k3"), 3);
  assert.equal(cache.stats().evictions, 1);
});

test("sqlite persistence survives a fresh cache instance", () => {
  const db = new Database(":memory:");
  migrate(db);
  const persistence = new SqliteCachePersistence(db);

  const first = new ArenaCache({ persistence, defaultTtlMs: 60_000 });
  first.set("durable", { hello: "world" });

  const second = new ArenaCache({ persistence, defaultTtlMs: 60_000 });
  assert.deepEqual(second.get("durable"), { hello: "world" });

  second.delete("durable");
  assert.equal(new ArenaCache({ persistence }).get("durable"), undefined);
  db.close();
});

test("default TTL applies when none is given", () => {
  let clock = 1000;
  const cache = new ArenaCache({ defaultTtlMs: 100, now: () => clock });
  cache.set("x", "y");
  clock = 1099;
  assert.equal(cache.get("x"), "y");
  clock = 1101;
  assert.equal(cache.get("x"), undefined);
});
