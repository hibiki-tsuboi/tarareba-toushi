import assert from 'node:assert/strict';

// The products of the generated sample. Which live products exist is the catalog's to say.
export const ids = ['demo-all-country', 'demo-sp500', 'demo-topix', 'demo-nasdaq100', 'demo-nikkei225', 'demo-gold', 'demo-emerging', 'demo-nanotech', 'demo-genomics', 'demo-developed-bond'];
// The app downloads every product it offers and offers at most this many (AppConfiguration).
export const maximumCatalogFunds = 20;
// Counted in characters as the app counts them, not in UTF-16 units.
const text = (value, limit) => typeof value === 'string' && value.trim() !== '' && [...value].length <= limit;
export function day(value) {
    assert.match(value, /^\d{4}-\d{2}-\d{2}$/);
    const date = new Date(`${value}T12:00:00Z`);
    assert(Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value);
    assert(value >= '1900-01-01' && value <= '2200-12-31');
    return date;
}

// Stricter than the app, which leaves out a product it cannot offer instead of failing:
// everything published here must be something the current app can offer.
// A published edition was valid under the rules of its day. Reading one back with
// `catalog: false` checks only what keeps the requests safe and the histories comparable;
// the catalog rules apply to what is about to be published.
export function validateManifest(m, mode = 'sample', { catalog = true } = {}) {
    assert(['sample', 'live'].includes(mode));
    const isSample = mode === 'sample';
    // Live data is the fixed-URL format; the sample keeps its versioned files.
    assert.equal(m.schemaVersion, isSample ? 1 : 2);
    assert.equal(m.isSample, isSample);
    assert.match(m.datasetVersion, /^[a-z0-9][a-z0-9-]{0,63}$/);
    assert.match(m.publishedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    day(m.publishedAt.slice(0, 10));
    assert(Number.isFinite(Date.parse(m.publishedAt)));
    assert.equal(new Date(m.publishedAt).toISOString().replace('.000Z', 'Z'), m.publishedAt);
    assert(Array.isArray(m.funds) && m.funds.length > 0, '商品がありません');
    assert(m.funds.length <= (catalog ? maximumCatalogFunds : 1000), `アプリが扱える商品は${maximumCatalogFunds}までです`);
    assert.equal(new Set(m.funds.map(f => f.id)).size, m.funds.length);
    if (catalog) {
        assert(Array.isArray(m.notices) && m.notices.length <= 10 && m.notices.every(n => text(n, 200)), '表記が不正です');
    }
    for (const f of m.funds) {
        assert.equal(f.currency, 'JPY');
        assert(text(f.displayName, 80), '商品名が不正です');
        if (catalog) {
            assert.equal(f.valueBasis, isSample ? 'reinvestedIndex' : 'nav');
            assert(text(f.shortName, 20), '短い商品名が不正です');
            assert(text(f.summary, 60), '商品の説明が不正です');
            assert(f.category === undefined || text(f.category, 20), '商品の分類が不正です');
        }
        for (const name of [f.displayName, f.shortName].filter(name => name !== undefined)) {
            assert(isSample ? name.includes('サンプル') : !name.includes('サンプル'));
        }
        assert.match(f.id, /^[a-z0-9][a-z0-9-]{0,63}$/);
        if (m.schemaVersion === 2) {
            assert.equal(f.path, `funds/${f.id}.json`);
            assert.match(f.contentVersion, /^fund-[a-f0-9]{64}$/);
        } else {
            assert.equal(f.path, `funds/${f.id}.${m.datasetVersion}.json`);
        }
        day(f.firstDate); day(f.lastDate);
        assert(f.firstDate <= f.lastDate);
    }
    // The picker groups by category in delivered order, so each category is listed together.
    const categories = m.funds.map(f => f.category).filter((c, i, all) => c !== undefined && c !== all[i - 1]);
    assert.equal(new Set(categories).size, categories.length, '同じ分類の商品は続けて並べてください');
    return m;
}

export function validate(snapshot, mode = 'sample', options = {}) {
    const m = validateManifest(snapshot.manifest, mode, options);
    const isSample = mode === 'sample';
    const expectedIDs = m.funds.map(f => f.id);
    assert.equal(snapshot.series.length, expectedIDs.length);
    assert.deepEqual(snapshot.series.map(s => s.fundId).sort(), [...expectedIDs].sort());
    let common;
    for (const f of m.funds) {
        const s = snapshot.series.find(s => s.fundId === f.id);
        assert.equal(s.schemaVersion, m.schemaVersion);
        assert.equal(s.isSample, isSample);
        assert.equal(s.datasetVersion, m.schemaVersion === 2 ? f.contentVersion : m.datasetVersion);
        assert.equal(s.currency, 'JPY');
        // An edition from before the catalog rules states the kind in its histories only.
        assert.equal(s.valueBasis, f.valueBasis ?? (isSample ? 'reinvestedIndex' : 'nav'));
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
        // Products may have disjoint lifetimes. Only the pair the app selects first
        // needs a shared observation date.
        if (m.funds.indexOf(f) < 2) {
            const dates = new Set(s.observations.map(o => o.date));
            common = common ? common.intersection(dates) : dates;
        }
    }
    assert(common.size > 0, '最初に選ばれる商品に共通の観測日がありません');
    return snapshot;
}
