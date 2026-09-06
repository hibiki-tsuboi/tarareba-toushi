import test from 'node:test';
import assert from 'node:assert/strict';
import { generate } from '../scripts/generate-sample.mjs';
import { day, validate } from '../scripts/contract.mjs';

test('deterministic sample includes gains, losses, plateaus and changing leaders', () => {
    const a = generate();
    assert.deepEqual(a, generate());
    assert.notDeepEqual(a, generate({ seed: 43 }));
    for (const series of a.series) {
        const deltas = series.observations.slice(1).map((o, i) => Number(o.value) - Number(series.observations[i].value));
        assert(deltas.some(d => d > 0) && deltas.some(d => d < 0) && deltas.some(d => d === 0));
    }
    const last = a.series.map(s => Number(s.observations.at(-1).value));
    const differences = a.series[0].observations.map((o, i) => last[1] / Number(a.series[1].observations[i].value) - last[0] / Number(o.value));
    assert(differences.some(d => d > 0) && differences.some(d => d < 0));
});
test('strict dates and one-day sample', () => {
    assert.throws(() => day('2025-02-30'));
    assert.throws(() => generate({ start: '2026-09-06', end: '2026-09-06' }));
    assert.equal(generate({ start: '2024-02-29', end: '2024-02-29' }).series[0].observations.length, 1);
});
test('reject corrupt or unsafe datasets', () => {
    const mutations = [
        s => s.manifest.isSample = false,
        s => s.manifest.schemaVersion = 2,
        s => s.manifest.funds[0].path = '../private.json',
        s => s.series[0].observations[0].value = '0',
        s => s.series[0].observations[0].value = '1e6',
        s => s.series[0].valueBasis = 'unknown',
        s => s.series[0].datasetVersion = 'wrong',
        s => s.series[0].observations[1].date = s.series[0].observations[0].date,
        s => s.manifest.funds[1].id = s.manifest.funds[0].id
    ];
    for (const mutate of mutations) {
        const snapshot = generate(); mutate(snapshot);
        assert.throws(() => validate(snapshot));
    }
});
