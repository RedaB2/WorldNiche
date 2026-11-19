import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";

export const endpoint = "/content/v1/historical-facts.json";
export const catalogFile = new URL(`../..${endpoint}`, import.meta.url);
const resources = new URL("../../../ios/WorldNiche/Resources/", import.meta.url);
const repository = fileURLToPath(new URL("../../../../", import.meta.url));
const repositoryPath = `apps/web${endpoint}`;

function readJSON(bytes) {
  assert.ok(bytes.length <= 1_048_576, "The fact catalog exceeds the app’s 1 MiB limit");
  const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  const parsed = JSON.parse(text);

  // JSON.parse keeps only the last duplicate key. Inspect object keys while
  // treating strings, including escaped quotes and literal braces, as tokens.
  const objects = [];
  for (const token of text.matchAll(/"(?:[^"\\]|\\.)*"(\s*:)?|[{}]/gu)) {
    if (token[0] === "{") objects.push(new Set());
    else if (token[0] === "}") objects.pop();
    else if (token[1]) {
      const key = JSON.parse(token[0].slice(0, -token[1].length));
      const keys = objects.at(-1);
      assert.ok(!keys.has(key), `Duplicate catalog key: ${key}`);
      keys.add(key);
    }
  }
  return parsed;
}

function checkText(value, limit, label) {
  assert.ok(typeof value === "string" && value.length > 0 && value === value.trim() &&
    !/[\p{Cc}\p{Zl}\p{Zp}]/u.test(value) && Buffer.byteLength(value) <= limit, `Invalid ${label}`);
}

export function validateCatalog(bytes, countryCodes) {
  const catalog = readJSON(bytes);
  assert.equal(catalog?.schemaVersion, 1, "Unsupported fact catalog schema");
  assert.deepEqual(Object.keys(catalog).sort(), ["countries", "revision", "schemaVersion"], "Unexpected catalog fields");
  assert.ok(Number.isSafeInteger(catalog.revision) && catalog.revision > 0, "Invalid catalog revision");
  assert.ok(catalog.countries && !Array.isArray(catalog.countries), "Expected a country dictionary");
  assert.deepEqual(Object.keys(catalog.countries).sort(), [...countryCodes].sort(), "Country coverage mismatch");
  const ids = new Set();
  const bodies = new Set();
  for (const [code, facts] of Object.entries(catalog.countries)) {
    assert.ok(Array.isArray(facts) && facts.length <= 5, `${code} needs an array of up to five facts`);
    for (const fact of facts) {
      assert.ok(fact && typeof fact === "object", `${code}: expected a fact`);
      assert.deepEqual(Object.keys(fact).sort(), ["body", "id", "sourceName", "sourceURL", "title"],
        `${code}: unexpected fact fields`);
      checkText(fact.id, 100, `${code} fact ID`);
      assert.ok(fact.id.startsWith(code.toLowerCase() + "-") && /^[a-z]{2}-[a-z0-9-]+$/.test(fact.id),
        `${code}: invalid fact ID`);
      checkText(fact.title, 200, `${fact.id} title`);
      checkText(fact.body, 1500, `${fact.id} body`);
      checkText(fact.sourceName, 240, `${fact.id} publisher`);
      checkText(fact.sourceURL, 2048, `${fact.id} source URL`);
      const url = new URL(fact.sourceURL);
      const authority = fact.sourceURL.slice("https://".length).split(/[/?#]/u, 1)[0];
      assert.ok(/^https:\/\//i.test(fact.sourceURL) && !/[\s\\]/u.test(fact.sourceURL) &&
        url.protocol === "https:" && url.hostname && authority && !authority.includes("@") && url.pathname !== "/",
        `${fact.id}: expected an item-level HTTPS source URL`);
      assert.ok(!ids.has(fact.id), `Duplicate fact ID: ${fact.id}`);
      assert.ok(!bodies.has(fact.body), `Duplicate fact text: ${fact.id}`);
      ids.add(fact.id);
      bodies.add(fact.body);
    }
  }
  return catalog;
}

export function checkRevision(current, previous) {
  assert.ok(current.revision >= previous.revision, "Catalog revisions cannot decrease");
  if (current.revision === previous.revision) {
    assert.ok(isDeepStrictEqual(current.countries, previous.countries),
      "Increment the catalog revision when facts, countries or fact order change");
  }
  for (const [code, facts] of Object.entries(current.countries)) {
    const oldIDs = new Map((previous.countries[code] ?? []).map(fact => [fact.body, fact.id]));
    for (const fact of facts) {
      assert.ok(!oldIDs.has(fact.body) || oldIDs.get(fact.body) === fact.id,
        `Keep the stable ID for the existing fact: ${fact.id}`);
    }
  }
}

export async function readPublishedCatalog(baseCommit, { production = false } = {}) {
  const destinations = JSON.parse(await readFile(new URL("countries.json", resources)));
  const codes = new Set(destinations.map(country => country.id));
  assert.equal(codes.size, 195, "Expected the 195 destinations supported by v1");
  const bytes = await readFile(catalogFile);
  const current = validateCatalog(bytes, codes);
  const bundled = validateCatalog(await readFile(new URL("historical-facts.json", resources)), codes);
  checkRevision(current, bundled);

  if (baseCommit && baseCommit !== "0".repeat(40)) {
    assert.match(baseCommit, /^[0-9a-f]{40}$/, "Expected a full target commit SHA");
    const git = (...args) => execFileSync("git", args, { cwd: repository });
    if (git("ls-tree", "--name-only", baseCommit, "--", repositoryPath).length) {
      const previous = readJSON(git("show", `${baseCommit}:${repositoryPath}`));
      checkRevision(current, previous);
    }
  }
  if (production) {
    // Vercel deploys independently of GitHub Actions. Check the public revision
    // even when the build has a shallow checkout or is redeploying an old SHA.
    const response = await fetch(new URL(endpoint, "https://worldniche.app"), {
      redirect: "error", cache: "no-store", signal: AbortSignal.timeout(15000),
    });
    if (response.status === 404) {
      assert.equal(current.revision, 1, "Only the first catalog can bootstrap a missing endpoint");
    } else {
      assert.ok(response.ok, `Could not verify the published catalog (HTTP ${response.status})`);
      checkRevision(current, validateCatalog(Buffer.from(await response.arrayBuffer()), codes));
    }
  }
  return { bytes, revision: current.revision };
}
