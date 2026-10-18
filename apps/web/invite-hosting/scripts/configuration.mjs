import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

// Production values live in ignored local files, outside public source.
export async function readConfiguration(root, name) {
  try {
    return JSON.parse(await readFile(resolve(root, `${name}.local.json`), "utf8"));
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    return JSON.parse(await readFile(resolve(root, `${name}.example.json`), "utf8"));
  }
}
