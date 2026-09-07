import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createSnapshot, funds, readSnapshot, writeSnapshot } from './fetch-mufg.mjs';

// Audited against already-downloaded official CSVs on 2026-09-07, without fetching
// history again: every saved value through 2026-09-04 equals the ordinary NAV.
// This is a migration of this exact edition, never a general reinvested -> NAV conversion.
export const verifiedVersion = 'mufg-20260904-6c4cf880560d';
export const verifiedHashes = {
    'all-country': '20277ded02e488fb01ad2aa873e46a8eca1d53764d6f69e371237e243ef91118',
    sp500: 'a051e6051d70650bf3988b034beb322ddba4b0a199621b809d6e5e5b5c9d6f3b'
};

export function migratedSnapshot(snapshot) {
    assert(snapshot, '保存済みの履歴がありません');
    if (snapshot.series.every(s => s.valueBasis === 'nav')) return snapshot;
    assert.equal(snapshot.manifest.datasetVersion, verifiedVersion, '通常基準価額と一致することを未確認の版です');
    const histories = funds.map(fund => {
        const series = snapshot.series.find(s => s.fundId === fund.id);
        assert.equal(series.valueBasis, 'reinvestedIndex');
        const text = series.observations.map(o => `${o.date}:${o.value}\n`).join('');
        assert.equal(createHash('sha256').update(text).digest('hex'), verifiedHashes[fund.id],
            '確認済みの通常基準価額と履歴が一致しません');
        return { observations: series.observations };
    });
    return createSnapshot(histories);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        assert.equal(process.argv.length, 2, 'このコマンドは引数を取りません');
        const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
        const previous = await readSnapshot(root);
        const snapshot = await writeSnapshot(migratedSnapshot(previous), root);
        console.log(`Migrated ${snapshot.manifest.datasetVersion}: dates and NAVs unchanged. No network requests or deployment.`);
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
