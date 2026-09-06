import assert from 'node:assert/strict';

export const ids = ['demo-all-country', 'demo-sp500'];
export const liveIDs = ['all-country', 'sp500'];
export function day(value) {
    assert.match(value, /^\d{4}-\d{2}-\d{2}$/);
    const date = new Date(`${value}T12:00:00Z`);
    assert(Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value);
    assert(value >= '1900-01-01' && value <= '2200-12-31');
    return date;
}

export function validate(snapshot, mode = 'sample') {
    assert(['sample', 'live'].includes(mode));
    const isSample = mode === 'sample';
    const expectedIDs = isSample ? ids : liveIDs;
    const m = snapshot.manifest;
    assert.equal(m.schemaVersion, 1);
    assert.equal(m.isSample, isSample);
    assert.match(m.datasetVersion, /^[a-z0-9][a-z0-9-]{0,63}$/);
    assert.match(m.publishedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    day(m.publishedAt.slice(0, 10));
    assert(Number.isFinite(Date.parse(m.publishedAt)));
    assert.equal(new Date(m.publishedAt).toISOString().replace('.000Z', 'Z'), m.publishedAt);
    assert.equal(m.funds.length, 2);
    assert.deepEqual(m.funds.map(f => f.id).sort(), [...expectedIDs].sort());
    assert.equal(snapshot.series.length, 2);
    assert.deepEqual(snapshot.series.map(s => s.fundId).sort(), [...expectedIDs].sort());
    let common;
    for (const f of m.funds) {
        assert.equal(f.currency, 'JPY');
        assert(f.displayName && f.displayName.length <= 80);
        assert(isSample ? f.displayName.includes('サンプル') : !f.displayName.includes('サンプル'));
        assert.equal(f.path, `funds/${f.id}.${m.datasetVersion}.json`);
        day(f.firstDate); day(f.lastDate);
        assert(f.firstDate <= f.lastDate);
        const s = snapshot.series.find(s => s.fundId === f.id);
        assert.equal(s.schemaVersion, 1);
        assert.equal(s.isSample, isSample);
        assert.equal(s.datasetVersion, m.datasetVersion);
        assert.equal(s.currency, 'JPY');
        assert(['reinvestedIndex', 'navWithoutDistributions'].includes(s.valueBasis));
        assert.equal(s.source.kind, isSample ? 'synthetic' : 'official');
        assert(s.source.name && s.source.note);
        if (!isSample) {
            const url = new URL(s.source.url);
            assert(url.protocol === 'https:' && url.hostname && !url.username && !url.password);
        }
        assert(s.observations.length > 0 && s.observations.length <= 30_000);
        assert.equal(s.observations[0].date, f.firstDate);
        assert.equal(s.observations.at(-1).date, f.lastDate);
        let previous = '';
        for (const o of s.observations) {
            day(o.date);
            assert(o.date > previous);
            assert.match(o.value, /^(0|[1-9][0-9]{0,11})(\.[0-9]{1,6})?$/);
            assert(Number(o.value) > 0);
            previous = o.date;
        }
        const dates = new Set(s.observations.map(o => o.date));
        common = common ? common.intersection(dates) : dates;
    }
    assert(common.size > 0);
    return snapshot;
}
