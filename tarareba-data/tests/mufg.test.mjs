import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { funds, headers, parseCSV, parseMufgCSV, validateLatest, createSnapshot, writeSnapshot, fetchBytes,
    updateFromMufg } from '../scripts/fetch-mufg.mjs';
import { validate } from '../scripts/contract.mjs';

// Deliberately fictional fixtures. They exercise nonzero distributions independently of today's funds.
const csv = fund => `${fund.name}\r\n${headers.join(',')}\r\n` +
    `${fund.start.replaceAll('-', '/')},10000,10000,,1.00\r\n` +
    '2025/01/06,9000,11000,2000,1.10\r\n2025/01/07,9900,12100,,1.20\r\n';
const histories = () => funds.map(f => parseMufgCSV(csv(f), f));
const latest = fund => ({ result: { status: 200 }, errors: { count: 0 }, datasets: [{
    fund_cd: fund.code, association_fund_cd: fund.associationCode, isin_cd: fund.isin,
    fund_name: fund.name, base_date: '20250107', nav: 9900
}] });

test('imports the official reinvested column without adding distributions again', () => {
    const history = histories()[0];
    assert.equal(history.observations[1].value, '11000');
    assert.equal(history.observations[2].value, '12100');
    assert.equal(history.navs.get('2025-01-06'), '9000');
    validateLatest(latest(funds[0]), history, funds[0]);
    const snapshot = createSnapshot(histories(), '2026-09-06T00:00:00Z');
    assert.equal(snapshot.manifest.isSample, false);
    assert.equal(snapshot.series[0].valueBasis, 'reinvestedIndex');
    assert.equal(snapshot.series[0].observations[2].value, '12100');
    assert.throws(() => validate(snapshot, 'sample'));
});

test('parses quoted CSV and rejects malformed quoting', () => {
    assert.deepEqual(parseCSV('"a,b","c""d"\r\n"line\nbreak",e'), [['a,b', 'c"d'], ['line\nbreak', 'e']]);
    for (const value of ['"unclosed', 'a"b,c', '"a"b,c']) assert.throws(() => parseCSV(value));
    const quoted = csv(funds[0]).split('\r\n').map(line => line ? line.split(',').map(c => `"${c}"`).join(',') : '').join('\r\n');
    assert.deepEqual(parseMufgCSV(quoted, funds[0]), histories()[0]);
});

test('rejects wrong funds, missing columns, invalid values, dates and truncated history', () => {
    const original = csv(funds[0]);
    const bad = [
        original.replace(funds[0].name, funds[1].name),
        original.replace(headers[2], '基準価額'),
        original.replace('9000,11000', '9000,'),
        original.replace('9000,11000', '9000,0'),
        original.replace('9000,11000', '9000,1e4'),
        original.replace('9000,11000', 'NaN,11000'),
        original.replace('2025/01/06', '2025/02/30'),
        original.replace('2025/01/07', '2025/01/06'),
        original.replace('2018/10/31,10000,10000,,1.00\r\n', ''),
        original.replace('9000,11000,2000,1.10', '9000,11000,2000')
    ];
    for (const text of bad) assert.throws(() => parseMufgCSV(text, funds[0]));
});

test('API identity, NAV and date must agree with the CSV', () => {
    for (const change of [
        p => p.result.status = 500, p => p.errors.count = 1, p => p.datasets = [],
        p => p.datasets[0].fund_cd = 'wrong', p => p.datasets[0].isin_cd = 'wrong',
        p => p.datasets[0].base_date = '20250108', p => p.datasets[0].nav = 9901
    ]) {
        const payload = latest(funds[0]); change(payload);
        assert.throws(() => validateLatest(payload, histories()[0], funds[0]));
    }
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

test('keeps unchanged editions stable, preserves old files and rejects history loss', async t => {
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
    assert.equal((await readdir(resolve(root, 'public/live/funds'))).length, 4);
    const manifest = await readFile(resolve(root, 'public/live/manifest.json'), 'utf8');
    updated[0].observations.splice(1, 1);
    await assert.rejects(writeSnapshot(createSnapshot(updated), root), /観測日が欠け/);
    assert.equal(await readFile(resolve(root, 'public/live/manifest.json'), 'utf8'), manifest);
    const bundle = JSON.parse(await readFile(resolve(directory, 'ios/TararebaToushi/Resources/BundledLive.json'), 'utf8'));
    assert.deepEqual(bundle, next);
});

test('rejects an existing immutable file with different content', async t => {
    const directory = await mkdtemp(resolve(tmpdir(), 'tarareba-mufg-'));
    t.after(() => rm(directory, { recursive: true, force: true }));
    const root = resolve(directory, 'tarareba-data');
    const snapshot = await writeSnapshot(createSnapshot(histories()), root);
    snapshot.series[1].observations[1].value = '12000';
    await assert.rejects(writeSnapshot(snapshot, root), /既存の版は変更できません/);
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

test('an upstream failure leaves the last valid manifest and bundle intact', async t => {
    const directory = await mkdtemp(resolve(tmpdir(), 'tarareba-mufg-'));
    t.after(() => rm(directory, { recursive: true, force: true }));
    const root = resolve(directory, 'tarareba-data');
    await writeSnapshot(createSnapshot(histories()), root);
    const path = resolve(root, 'public/live/manifest.json');
    const before = await readFile(path, 'utf8');
    await assert.rejects(updateFromMufg(root, async () => new Response('unavailable', { status: 503 })));
    assert.equal(await readFile(path, 'utf8'), before);
});
