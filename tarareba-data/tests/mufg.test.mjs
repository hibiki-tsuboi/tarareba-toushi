import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { funds, latestURL, datedURL, parseFundInformation, createSnapshot, writeSnapshot, fetchBytes,
    updateFromMufg, readSnapshot } from '../scripts/fetch-mufg.mjs';
import { validate } from '../scripts/contract.mjs';

// Fictional API responses; these tests never contact the provider.
const histories = () => funds.map(f => ({ observations: [
    { date: f.start, value: '10000' }, { date: '2025-01-06', value: '9000' },
    { date: '2025-01-07', value: '9900' }
] }));
const payload = (fund, date = '2025-01-07', nav = 9900) => ({
    result: { status: 200, retcount: 1, errcd: null }, errors: { count: 0 }, datasets: [{
        fund_cd: fund.code, association_fund_cd: fund.associationCode, isin_cd: fund.isin,
        fund_name: fund.name, base_date: date.replaceAll('-', ''), nav
    }]
});
const empty = () => ({ result: { status: 200, retcount: 0, errcd: null }, errors: { count: 0 }, datasets: [] });
const options = { wait: async () => {}, today: '2026-09-07' };
const response = value => new Response(JSON.stringify(value), { headers: { 'content-type': 'application/json' } });

async function folder(t, snapshot = createSnapshot(histories())) {
    const root = await mkdtemp(resolve(tmpdir(), 'tarareba-nav-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    if (snapshot) await writeSnapshot(snapshot, root);
    return root;
}
function server(latestDate, value = 10100, dates = new Map()) {
    const requests = [];
    return { requests, fetch: async url => {
        requests.push(url);
        const fund = funds.find(f => url.includes(f.associationCode));
        assert(fund, 'Unexpected fund');
        if (url === latestURL(fund)) return response(payload(fund, latestDate, value));
        const date = url.match(/base_date\/(\d{4})(\d{2})(\d{2})$/)?.slice(1).join('-');
        assert(date && dates.has(date), `Unexpected historical request: ${url}`);
        const nav = dates.get(date);
        return response(nav === null ? empty() : payload(fund, date, nav));
    } };
}

test('uses only the requested date and ordinary NAV, ignoring other API fields', () => {
    const data = payload(funds[0]);
    data.datasets[0].netassets = 999999;
    data.datasets[0].percentage_change_full = '999';
    assert.deepEqual(parseFundInformation(data, funds[0], '2025-01-07'), { date: '2025-01-07', value: '9900' });
    const history = histories();
    history[0].observations[1].distribution = '1000';
    history[0].observations[1].reinvestedValue = '11000';
    const snapshot = createSnapshot(history, '2026-09-06T00:00:00Z');
    assert.equal(snapshot.series[0].valueBasis, 'nav');
    assert.deepEqual(Object.keys(snapshot.series[0].observations[1]), ['date', 'value']);
    assert.equal(snapshot.series[0].observations[1].value, '9000');
    assert.throws(() => validate(snapshot, 'sample'));
});

test('rejects wrong products, days, NAVs and malformed/error API envelopes', () => {
    const mutations = [
        p => p.result.status = 500, p => p.result.errcd = 'unavailable', p => p.result.retcount = 0,
        p => p.errors.count = 1, p => delete p.errors, p => p.datasets = [],
        p => p.datasets.push(p.datasets[0]), p => p.datasets[0].fund_cd = 'wrong',
        p => p.datasets[0].association_fund_cd = 'wrong', p => p.datasets[0].isin_cd = 'wrong',
        p => p.datasets[0].fund_name = 'another fund', p => p.datasets[0].base_date = '20250108',
        p => p.datasets[0].base_date = '20250230', p => p.datasets[0].base_date = '20180101',
        ...[0, -1, null, '9900', '1e4', {}, Infinity].map(value => p => p.datasets[0].nav = value)
    ];
    for (const mutate of mutations) {
        const data = payload(funds[0]); mutate(data);
        assert.throws(() => parseFundInformation(data, funds[0], '2025-01-07'));
    }
    assert.throws(() => datedURL(funds[0], '2025-02-30'));
});

test('only an explicitly successful empty dated response means no observation', () => {
    assert.equal(parseFundInformation(empty(), funds[0], '2025-01-11'), null);
    assert.throws(() => parseFundInformation(empty(), funds[0]));
    for (const mutate of [p => p.result.status = 404, p => p.result.errcd = 'not-found',
        p => p.errors.count = 1, p => p.result.retcount = 1, p => delete p.datasets]) {
        const data = empty(); mutate(data);
        assert.throws(() => parseFundInformation(data, funds[0], '2025-01-11'));
    }
});

test('unchanged latest NAVs require only two API calls and preserve version, timestamps and history', async t => {
    const root = await folder(t);
    const before = await readSnapshot(root);
    const remote = server('2025-01-07', 9900);
    const pauses = [];
    const next = await updateFromMufg(root, remote.fetch, { ...options, wait: async ms => pauses.push(ms) });
    assert.deepEqual(next, before);
    assert.deepEqual(remote.requests, funds.map(latestURL));
    assert.deepEqual(pauses, [1000]);
});

test('fills only dates after the saved end, skips successful empty days, and appends the latest NAV', async t => {
    const root = await folder(t);
    const remote = server('2025-01-13', 10300, new Map([
        ['2025-01-08', 10000], ['2025-01-09', 10100], ['2025-01-10', 10200],
        ['2025-01-11', null], ['2025-01-12', null]
    ]));
    const next = await updateFromMufg(root, remote.fetch, options);
    for (const [i, fund] of funds.entries()) {
        assert.deepEqual(next.series[i].observations.slice(0, 3), histories()[i].observations);
        assert.deepEqual(next.series[i].observations.slice(3), [
            { date: '2025-01-08', value: '10000' }, { date: '2025-01-09', value: '10100' },
            { date: '2025-01-10', value: '10200' }, { date: '2025-01-13', value: '10300' }
        ]);
        assert.deepEqual(remote.requests.filter(url => url.includes(fund.associationCode)), [
            latestURL(fund), ...['2025-01-08', '2025-01-09', '2025-01-10', '2025-01-11', '2025-01-12'].map(date => datedURL(fund, date))
        ]);
    }
    assert(remote.requests.every(url => new URL(url).host === 'developer.am.mufg.jp'));
});

test('a one-day update uses the latest API response without requesting saved history', async t => {
    const root = await folder(t);
    const remote = server('2025-01-08');
    const next = await updateFromMufg(root, remote.fetch, options);
    assert.deepEqual(remote.requests, funds.map(latestURL));
    assert.equal(next.series[0].observations.at(-1).date, '2025-01-08');
});

test('missing or incompatible local history fails before any request; initial backfill is explicit', async t => {
    const root = await folder(t, null);
    let requests = 0;
    const fetcher = async () => { requests++; throw new Error('No network allowed'); };
    await assert.rejects(updateFromMufg(root, fetcher, options), /--backfill/);
    assert.equal(requests, 0);
    const old = createSnapshot(histories());
    old.series.forEach(s => s.valueBasis = 'reinvestedIndex');
    await writeSnapshot(old, root);
    await assert.rejects(updateFromMufg(root, fetcher, options), /通常基準価額ではありません/);
    assert.equal(requests, 0);
});

test('adding a fund needs an explicit backfill and never refetches the saved ones', async t => {
    // The extra fund stands in for a product added to the catalogue later.
    const added = { id: 'topix', code: '000000', associationCode: '0000000A', isin: 'JP90C0000000',
        name: 'テスト専用の追加商品', start: '2025-01-06' };
    const root = await folder(t);
    funds.push(added);
    t.after(() => { funds.pop(); });

    let blocked = 0;
    const refuse = async () => { blocked++; throw new Error('No network allowed'); };
    await assert.rejects(updateFromMufg(root, refuse, options), /topix/);
    await assert.rejects(updateFromMufg(root, refuse, options), /--backfill/);
    assert.equal(blocked, 0, 'requests must not start before the missing fund is acknowledged');

    const requests = [];
    const fetcher = async url => {
        requests.push(url);
        const fund = funds.find(f => url.includes(f.associationCode));
        if (url === latestURL(fund)) return response(payload(fund, '2025-01-08', 10200));
        const date = url.match(/base_date\/(\d{4})(\d{2})(\d{2})$/).slice(1).join('-');
        return response(payload(fund, date, 10100));
    };
    const before = await readSnapshot(root);
    const snapshot = await updateFromMufg(root, fetcher, { ...options, backfill: true });

    // The latest date reuses the latest-value response, so it is never requested by date.
    assert.deepEqual(requests.filter(url => url.includes(funds[0].associationCode)),
        [latestURL(funds[0])], 'saved funds resume from their last date instead of their inception');
    assert.deepEqual(requests.filter(url => url.includes(added.associationCode)),
        [latestURL(added), datedURL(added, '2025-01-06'), datedURL(added, '2025-01-07')]);

    const history = snapshot.series.find(s => s.fundId === 'topix');
    assert.equal(history.observations[0].date, added.start);
    assert.equal(history.observations.length, 3);
    for (const old of before.series) {
        const next = snapshot.series.find(s => s.fundId === old.fundId);
        assert.deepEqual(next.observations.slice(0, old.observations.length), old.observations,
            'existing dates and NAVs stay byte-identical when a fund is added');
    }
    assert.equal(snapshot.manifest.funds.length, 3);
});

test('explicit initial backfill requests each date from fund inception', async t => {
    const root = await folder(t, null);
    const requests = [];
    const fetcher = async url => {
        requests.push(url);
        const fund = funds.find(f => url.includes(f.associationCode));
        const end = '2018-11-02';
        if (url === latestURL(fund)) return response(payload(fund, end, 10200));
        const date = url.match(/base_date\/(\d{4})(\d{2})(\d{2})$/).slice(1).join('-');
        return response(payload(fund, date, date === fund.start ? 10000 : 10100));
    };
    const snapshot = await updateFromMufg(root, fetcher, { ...options, backfill: true });
    assert(snapshot.series.every(s => s.observations.at(-1).date === '2018-11-02'));
    assert.equal(snapshot.series[0].observations[0].date, '2018-10-31');
    assert.equal(snapshot.series[1].observations[0].date, '2018-07-03');
    assert.equal(snapshot.series[0].observations.length, 3);
    assert.equal(snapshot.series[1].observations.length, 123);
    assert.equal(requests.length, 126);
    assert.deepEqual(requests.slice(0, 6), [latestURL(funds[0]), datedURL(funds[0], '2018-10-31'),
        datedURL(funds[0], '2018-11-01'), latestURL(funds[1]), datedURL(funds[1], '2018-07-03'),
        datedURL(funds[1], '2018-07-04')]);
    assert.equal(requests.at(-1), datedURL(funds[1], '2018-11-01'));
    assert.deepEqual(await readSnapshot(root), snapshot);
});

test('API rollback, future dates, mismatched dates and failures leave saved files intact', async t => {
    const root = await folder(t);
    const before = await readSnapshot(root);
    const files = await readdir(resolve(root, 'public/live/funds'));
    for (const fetcher of [server('2025-01-06').fetch, server('2027-01-01').fetch,
        async url => {
            const fund = funds.find(f => url.includes(f.associationCode));
            if (url === latestURL(fund)) return response(payload(fund, '2025-01-10'));
            return response(payload(fund, '2025-01-07'));
        },
        async url => {
            const fund = funds.find(f => url.includes(f.associationCode));
            if (url === latestURL(fund)) return response(payload(fund, '2025-01-10'));
            return new Response('{}', { status: 404 });
        },
        async url => {
            if (url === latestURL(funds[0])) return response(payload(funds[0], '2025-01-08'));
            throw new Error('second fund failed');
        }
    ]) {
        await assert.rejects(updateFromMufg(root, fetcher, options));
        assert.deepEqual(await readSnapshot(root), before);
        assert.deepEqual(await readdir(resolve(root, 'public/live/funds')), files);
    }
});

test('a corrected latest NAV updates the same fixed URL without changing older observations', async t => {
    const root = await folder(t);
    const before = await readSnapshot(root);
    const next = await updateFromMufg(root, server('2025-01-07', 9800).fetch, options);
    assert.notEqual(next.manifest.datasetVersion, before.manifest.datasetVersion);
    assert.equal(next.series[0].observations.at(-1).value, '9800');
    assert.deepEqual(next.series[0].observations.slice(0, -1), before.series[0].observations.slice(0, -1));
});

test('live datasets require official sources, HTTPS attribution and separate identities', () => {
    const snapshot = createSnapshot(histories());
    for (const change of [
        s => s.series[0].source.kind = 'synthetic', s => s.series[0].source.url = null,
        s => s.series[0].source.url = 'http://example.com/',
        s => s.manifest.funds[0].id = 'demo-all-country', s => s.manifest.funds[0].displayName += '（サンプル）',
        s => s.series[1].isSample = true
    ]) {
        const changed = structuredClone(snapshot); change(changed);
        assert.throws(() => validate(changed, 'live'));
    }
});

test('writes distribution files only, keeps editions stable and rejects history loss', async t => {
    const directory = await mkdtemp(resolve(tmpdir(), 'tarareba-mufg-'));
    t.after(() => rm(directory, { recursive: true, force: true }));
    const root = resolve(directory, 'tarareba-data');
    const first = await writeSnapshot(createSnapshot(histories(), '2026-09-06T00:00:00Z'), root);
    const unchanged = await writeSnapshot(createSnapshot(histories(), '2026-09-06T01:00:00Z'), root);
    assert.deepEqual(first, unchanged);
    const updated = histories();
    updated[0].observations[1].value = '11001';
    const next = await writeSnapshot(createSnapshot(updated), root);
    assert.notEqual(first.manifest.datasetVersion, next.manifest.datasetVersion);
    assert.deepEqual((await readdir(resolve(root, 'public/live/funds'))).sort(), ['all-country.json', 'sp500.json']);
    const manifest = await readFile(resolve(root, 'public/live/manifest.json'), 'utf8');
    updated[0].observations.splice(1, 1);
    await assert.rejects(writeSnapshot(createSnapshot(updated), root), /観測日が欠け/);
    assert.equal(await readFile(resolve(root, 'public/live/manifest.json'), 'utf8'), manifest);
    await assert.rejects(readdir(resolve(directory, 'ios')), { code: 'ENOENT' });
});

test('rejects changed content without a changed identifier', async t => {
    const directory = await mkdtemp(resolve(tmpdir(), 'tarareba-mufg-'));
    t.after(() => rm(directory, { recursive: true, force: true }));
    const root = resolve(directory, 'tarareba-data');
    const snapshot = await writeSnapshot(createSnapshot(histories()), root);
    snapshot.series[1].observations[1].value = '12000';
    await assert.rejects(writeSnapshot(snapshot, root), /同じ版のデータ/);
});

test('rejects HTTP errors, HTML and advertised or streamed oversize responses', async () => {
    const responses = [
        new Response('{}', { status: 500, headers: { 'content-type': 'application/json' } }),
        new Response('<html>', { headers: { 'content-type': 'text/html' } }),
        new Response('{}', { headers: { 'content-type': 'application/json', 'content-length': '2097153' } }),
        new Response(Buffer.alloc(2097153), { headers: { 'content-type': 'application/json' } })
    ];
    for (const response of responses) {
        await assert.rejects(fetchBytes('https://example.com/', 'application/json', async () => response));
    }
    let options;
    const result = await fetchBytes('https://example.com/', 'application/json', async (_, value) => {
        options = value;
        return new Response('{}', { headers: { 'content-type': 'application/json;charset=UTF-8' } });
    });
    assert.equal(result.toString(), '{}');
    assert.equal(options.redirect, 'error');
    assert(options.signal instanceof AbortSignal);
});

test('an upstream failure leaves the last valid manifest intact', async t => {
    const directory = await mkdtemp(resolve(tmpdir(), 'tarareba-mufg-'));
    t.after(() => rm(directory, { recursive: true, force: true }));
    const root = resolve(directory, 'tarareba-data');
    await writeSnapshot(createSnapshot(histories()), root);
    const path = resolve(root, 'public/live/manifest.json');
    const before = await readFile(path, 'utf8');
    await assert.rejects(updateFromMufg(root, async () => new Response('unavailable', { status: 503 })));
    assert.equal(await readFile(path, 'utf8'), before);
});


test('only the changed fund gets new content and the fixed file count stays constant', async t => {
    const root = await folder(t);
    const before = await readSnapshot(root);
    const otherPath = resolve(root, 'public/live/funds/sp500.json');
    const otherBytes = await readFile(otherPath, 'utf8');
    const history = histories();
    history[0].observations.push({ date: '2025-01-08', value: '10300' });
    const next = await writeSnapshot(createSnapshot(history), root);
    assert.notEqual(next.manifest.funds[0].contentVersion, before.manifest.funds[0].contentVersion);
    assert.equal(next.manifest.funds[1].contentVersion, before.manifest.funds[1].contentVersion);
    assert.deepEqual(next.manifest.funds.map(f => f.path), before.manifest.funds.map(f => f.path));
    assert.equal(await readFile(otherPath, 'utf8'), otherBytes);
    assert.deepEqual((await readdir(resolve(root, 'public/live/funds'))).sort(), ['all-country.json', 'sp500.json']);
});

test('migration from versioned URLs preserves every date and value and subsequent writes stay fixed', async t => {
    const root = await folder(t, null);
    const legacy = createSnapshot(histories());
    legacy.manifest.schemaVersion = 1;
    legacy.manifest.datasetVersion = 'legacy-live';
    for (const fund of legacy.manifest.funds) {
        delete fund.contentVersion;
        fund.path = `funds/${fund.id}.legacy-live.json`;
    }
    for (const series of legacy.series) {
        series.schemaVersion = 1;
        series.datasetVersion = 'legacy-live';
    }
    await writeSnapshot(legacy, root);
    const next = await writeSnapshot(createSnapshot(histories()), root);
    assert.deepEqual(next.series.map(s => s.observations), legacy.series.map(s => s.observations));
    for (const fund of legacy.manifest.funds) {
        assert.deepEqual(JSON.parse(await readFile(resolve(root, 'public/live', fund.path), 'utf8')),
            legacy.series.find(s => s.fundId === fund.id));
    }
    const files = await readdir(resolve(root, 'public/live/funds'));
    await updateFromMufg(root, server('2025-01-08').fetch, options);
    assert.deepEqual(await readdir(resolve(root, 'public/live/funds')), files);
});

test('a hundred-product catalog can contain additional histories outside the comparison period', () => {
    const snapshot = createSnapshot(histories());
    for (let index = 2; index < 100; index++) {
        const series = structuredClone(snapshot.series[0]);
        series.fundId = `additional-${index}`;
        series.observations = [{ date: '2010-01-04', value: '10000' }];
        const descriptor = { ...snapshot.manifest.funds[0], id: series.fundId,
            displayName: `追加商品${index}`, path: `funds/${series.fundId}.json`,
            firstDate: '2010-01-04', lastDate: '2010-01-04' };
        snapshot.series.push(series);
        snapshot.manifest.funds.push(descriptor);
    }
    assert.equal(validate(snapshot, 'live').manifest.funds.length, 100);
    const missing = structuredClone(snapshot);
    missing.manifest.funds.shift();
    missing.series.shift();
    assert.throws(() => validate(missing, 'live'), /必要な商品/);
});
