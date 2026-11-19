import assert from "node:assert/strict";
import test from "node:test";
import { checkRevision, readPublishedCatalog, validateCatalog } from "../scripts/fact-catalog.mjs";

const fact = {
  id: "ma-craft", title: "A craft", body: "A historical detail.",
  sourceName: "Museum", sourceURL: "https://example.org/collection/1",
};
const codes = ["MA", "PE"];
const seed = { schemaVersion: 1, revision: 1, countries: { MA: [fact], PE: [] } };
const validate = value => validateCatalog(Buffer.from(JSON.stringify(value)), codes);
const edit = change => {
  const copy = structuredClone(seed);
  change(copy);
  return copy;
};

test("the editorial catalog is compatible with the bundled offline revision", async () => {
  const published = await readPublishedCatalog();
  assert.ok(published.revision >= 1);
});

test("the production gate rejects a stale publication even without a local target commit", async context => {
  const { bytes } = await readPublishedCatalog();
  const live = JSON.parse(bytes);
  live.revision++;
  const request = context.mock.method(globalThis, "fetch", async () => Response.json(live));
  await assert.rejects(readPublishedCatalog(undefined, { production: true }), /cannot decrease/);
  assert.equal(request.mock.calls[0].arguments[0].href, "https://worldniche.app/content/v1/historical-facts.json");
});

test("up to five facts can publish per country; six fails, and an empty array withdraws a country’s facts", () => {
  for (const count of [0, 1, 2, 3, 4, 5, 6]) {
    const next = edit(catalog => {
      catalog.revision++;
      catalog.countries.MA = Array.from({ length: count }, (_, i) =>
        ({ ...fact, id: `ma-topic-${i}`, body: `Another historical detail (${i}).` }));
    });
    if (count === 6) assert.throws(() => validate(next), /up to five/);
    else checkRevision(validate(next), seed);
  }
});

test("invalid catalogs cannot silently drop countries, reuse identities, or publish malformed citations", () => {
  for (const change of [
    catalog => { catalog.schemaVersion = 2; },
    catalog => { catalog.revision = 0; },
    catalog => { delete catalog.countries.PE; },
    catalog => { catalog.countries.US = []; },
    catalog => { catalog.countries.PE = null; },
    catalog => { catalog.countries.PE = [{ ...fact, id: "pe-craft" }]; },
    catalog => { catalog.countries.MA.push({ ...fact, body: "A different detail." }); },
    catalog => { catalog.countries.MA[0].id = "pe-craft"; },
    catalog => { catalog.countries.MA[0].title = "  "; },
    catalog => { catalog.countries.MA[0].sourceName = "Museum\nArchives"; },
    catalog => { catalog.countries.MA[0].body = "é".repeat(751); },
    catalog => { catalog.countries.MA[0].sourceURL = "http://example.org/object"; },
    catalog => { catalog.countries.MA[0].sourceURL = "https://example.org"; },
    catalog => { catalog.countries.MA[0].sourceURL = "https://reader@example.org/object"; },
  ]) assert.throws(() => validate(edit(change)));
  assert.throws(() => validateCatalog(Buffer.alloc(1_048_577), codes), /1 MiB/);
  const duplicate = JSON.stringify(seed).replace('"MA":', '"M\\u0041":[],"MA":');
  assert.throws(() => validateCatalog(Buffer.from(duplicate), codes), /Duplicate catalog key/);
});

test("content corrections, withdrawals and reordering require a newer revision while existing facts keep their IDs", () => {
  checkRevision(validate(seed), seed);
  const correction = edit(catalog => { catalog.countries.MA[0].body = "The corrected historical detail."; });
  assert.throws(() => checkRevision(correction, seed), /Increment/);
  correction.revision++;
  checkRevision(correction, seed);
  assert.throws(() => checkRevision(seed, correction), /cannot decrease/);
  const renamed = edit(catalog => { catalog.revision++; catalog.countries.MA[0].id = "ma-renamed"; });
  assert.throws(() => checkRevision(renamed, seed), /stable ID/);
  const pair = edit(catalog => { catalog.countries.MA.push({ ...fact, id: "ma-second", body: "Second detail." }); });
  const reordered = structuredClone(pair);
  reordered.countries.MA.reverse();
  assert.throws(() => checkRevision(reordered, pair), /Increment/);
});
