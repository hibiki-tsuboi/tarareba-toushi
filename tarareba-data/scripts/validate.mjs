import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import assert from 'node:assert/strict';
import { validate, validateManifest } from './contract.mjs';
import { verifyNoDataFiles } from './verify-app-data.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = async path => {
    const bytes = await readFile(path);
    assert(bytes.length <= 2 * 1024 * 1024, 'Response exceeds 2 MiB');
    return JSON.parse(bytes);
};
for (const mode of ['sample', 'live']) {
    const manifest = await read(resolve(root, `public/${mode}/manifest.json`));
    validateManifest(manifest, mode);
    const series = [];
    for (const fund of manifest.funds) {
        series.push(await read(resolve(root, `public/${mode}`, fund.path)));
    }
    validate({ manifest, series }, mode);
    console.log(`Validated ${manifest.datasetVersion}: schema, dates, values, common dates and paths.`);
}
await verifyNoDataFiles(resolve(root, '../ios/TararebaToushi'));
console.log('Verified: the app source tree contains no JSON/CSV data resources.');
