import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

// Local overrides stay ignored. Delivery snapshots carry public production routing.
export async function readConfiguration(root, name) {
  for (const kind of ["local", "production", "example"]) {
    try {
      return JSON.parse(await readFile(resolve(root, `${name}.${kind}.json`), "utf8"));
    } catch (error) {
      if (error.code !== "ENOENT" || kind === "example") throw error;
    }
  }
}
