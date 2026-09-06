import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import assert from 'node:assert/strict';
import { validate } from './contract.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = async path => {
    const bytes = await readFile(path);
    assert(bytes.length <= 2 * 1024 * 1024, 'Response exceeds 2 MiB');
    return JSON.parse(bytes);
};
const manifest = await read(resolve(root, 'public/sample/manifest.json'));
const series = [];
for (const fund of manifest.funds) {
    assert.match(fund.path, /^funds\/demo-(all-country|sp500)\.[a-z0-9-]+\.json$/);
    series.push(await read(resolve(root, 'public/sample', fund.path)));
}
const snapshot = validate({ manifest, series });
const bundled = JSON.parse(await readFile(resolve(root, '../ios/TararebaToushi/Resources/BundledSample.json'), 'utf8'));
assert.deepEqual(snapshot, validate(bundled), 'Bundled and distributed samples differ');
console.log(`Validated ${manifest.datasetVersion}: schema, dates, values, common dates, paths and bundle parity.`);
