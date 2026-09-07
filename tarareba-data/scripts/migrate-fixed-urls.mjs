import assert from 'node:assert/strict';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createSnapshot, funds, readSnapshot, writeSnapshot } from './fetch-mufg.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const previous = await readSnapshot(root);
assert(previous, '保存済みの履歴がありません');
assert(previous.series.every(s => s.valueBasis === 'nav'), '先に通常基準価額へ移行してください');
if (previous.manifest.schemaVersion === 2) {
    console.log('Fixed URLs are already configured. No changes.');
} else {
    const histories = funds.map(f => previous.series.find(s => s.fundId === f.id));
    const next = await writeSnapshot(createSnapshot(histories), root);
    console.log(`Migrated to fixed URLs: ${next.manifest.datasetVersion}. No prices changed, no network requests or deployment.`);
}
