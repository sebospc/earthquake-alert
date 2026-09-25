// devices.json and the other stores: merged writes, nothing lost, never half a file.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { pathToFileURL } from "node:url";

import { createJsonFile } from "../src/server.js";

const SERVER_URL = pathToFileURL(new URL("../src/server.js", import.meta.url).pathname).href;

async function tempDir(t) {
  const directory = await mkdtemp(join(tmpdir(), "relay-store-"));
  t.after(() => rm(directory, { recursive: true, force: true, maxRetries: 5 }));
  return directory;
}

test("persist calls made during a write share one next write, and none loses its change", async t => {
  const file = join(await tempDir(t), "devices.json");
  const store = createJsonFile(file, {});

  store.data.first = 1;
  const running = store.persist();
  const queued = [];
  for (let index = 0; index < 20; index += 1) {
    store.data[`phone${index}`] = index;
    queued.push(store.persist());
  }

  assert.equal(new Set(queued).size, 1, "a write per call: 20 full copies of the store queued");
  assert.notEqual(queued[0], running);
  await running;
  await queued[0];
  const onDisk = JSON.parse(await readFile(file, "utf8"));
  assert.deepEqual(onDisk, store.data, "a change made during the running write was lost");
  store.data.late = true;
  await store.persist();
  assert.equal(JSON.parse(await readFile(file, "utf8")).late, true, "a later call reused a finished write");
});

test("a failed write rejects its callers, and the next call writes again", async t => {
  const directory = join(await tempDir(t), "not-yet");
  const store = createJsonFile(join(directory, "devices.json"), {});

  store.data.phone = 1;
  await assert.rejects(store.persist(), /ENOENT/);
  await mkdir(directory);
  store.data.other = 2;
  await store.persist();

  assert.deepEqual(JSON.parse(await readFile(join(directory, "devices.json"), "utf8")), { phone: 1, other: 2 });
});

test("a process killed while writing leaves a whole devices.json, old or new", async t => {
  const directory = await tempDir(t);
  const file = join(directory, "devices.json");
  const writer = join(directory, "writer.mjs");
  // A few MB, so a write takes long enough to be killed in the middle of it.
  await writeFile(writer, `
    import { createJsonFile } from ${JSON.stringify(SERVER_URL)};
    const store = createJsonFile(${JSON.stringify(file)}, {});
    for (let round = 0; ; round += 1) {
      for (let index = 0; index < 20000; index += 1) store.data["ab".repeat(32) + index] = { round, sensor_ids: ["chaparral"] };
      await store.persist();
      if (round === 0) console.log("written");
    }
  `);

  for (let attempt = 0; attempt < 8; attempt += 1) {
    const child = spawn(process.execPath, [writer], { stdio: ["ignore", "pipe", "inherit"] });
    await new Promise(resolve => child.stdout.once("data", resolve));
    await new Promise(resolve => setTimeout(resolve, 5 + attempt * 13));
    child.kill("SIGKILL");
    await new Promise(resolve => child.once("exit", resolve));
    const text = await readFile(file, "utf8");
    assert.doesNotThrow(() => JSON.parse(text), `half a file after a kill (attempt ${attempt})`);
    assert.equal(Object.keys(JSON.parse(text)).length, 20000);
  }
});
