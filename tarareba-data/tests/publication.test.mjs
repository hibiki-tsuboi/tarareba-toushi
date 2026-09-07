import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { createSnapshot, funds, writeSnapshot } from '../scripts/fetch-mufg.mjs';
import { publicationStatus, publicURL, verifyPublication } from '../scripts/check-published.mjs';

// Small fictional histories; tests never contact the provider or deploy anything.
function snapshot(lastDate = '2025-01-07', value = '11000') {
    return createSnapshot(funds.map(f => ({ observations: [
        { date: f.start, value: '10000' }, { date: '2025-01-06', value: '10500' },
        { date: lastDate, value }
    ] })), '2026-09-06T00:00:00Z');
}

async function folder(t, data = snapshot()) {
    const directory = await mkdtemp(resolve(tmpdir(), 'tarareba-publication-'));
    t.after(() => rm(directory, { recursive: true, force: true }));
    await writeSnapshot(data, directory);
    return directory;
}

function server(data) {
    const files = new Map([['manifest.json', JSON.stringify(data.manifest)]]);
    for (const f of data.manifest.funds) {
        files.set(f.path, JSON.stringify(data.series.find(s => s.fundId === f.id)));
    }
    const requests = [];
    return { files, requests, fetch: async (url, options) => {
        assert(url.startsWith(publicURL));
        assert.equal(options.redirect, 'error');
        assert(options.signal instanceof AbortSignal);
        const path = url.slice(publicURL.length);
        requests.push(path);
        const contents = files.get(path);
        return new Response(contents ?? '{}', {
            status: contents === undefined ? 404 : 200, headers: { 'content-type': 'application/json' }
        });
    } };
}

test('unchanged published data skips deployment and verifies every history', async t => {
    const data = snapshot();
    const directory = await folder(t, data);
    const remote = server(data);
    assert.equal((await publicationStatus(directory, remote.fetch)).needsDeploy, false);
    assert.equal(remote.requests.length, funds.length + 1, 'the catalog plus one request per history');
    assert.deepEqual(await verifyPublication(directory, remote.fetch), data);
});

test('a failed deployment is retried even when Git already contains the new edition', async t => {
    const old = snapshot();
    const directory = await folder(t, old);
    const next = snapshot('2025-01-07', '12000');
    await writeSnapshot(next, directory);
    const file = resolve(directory, 'public/live/manifest.json');
    const saved = await readFile(file, 'utf8');
    // Both runs start with exactly the same checked-in files; the public URL is still old.
    for (let run = 0; run < 2; run++) {
        assert.equal((await publicationStatus(directory, server(old).fetch)).needsDeploy, true);
        assert.equal(await readFile(file, 'utf8'), saved);
    }
    await assert.rejects(verifyPublication(directory, server(old).fetch), /一致しません/);
    assert.deepEqual(await verifyPublication(directory, server(next).fetch), next);
    assert.equal((await publicationStatus(directory, server(next).fetch)).needsDeploy, false);
});

test('a missing manifest needs publication, but is never a successful verification', async t => {
    const directory = await folder(t);
    const missing = async () => new Response('{}', { status: 404 });
    assert.equal((await publicationStatus(directory, missing)).needsDeploy, true);
    await assert.rejects(verifyPublication(directory, missing), /見つかりません/);
});

test('HTTP, network, HTML, broken JSON and missing-history failures cannot skip verification', async t => {
    const data = snapshot();
    const directory = await folder(t, data);
    for (const fetcher of [
        async () => new Response('{}', { status: 503 }),
        async () => { throw new Error('network unavailable'); },
        async () => new Response('<html>', { headers: { 'content-type': 'text/html' } }),
        async () => new Response('{broken', { headers: { 'content-type': 'application/json' } })
    ]) {
        await assert.rejects(publicationStatus(directory, fetcher));
        await assert.rejects(verifyPublication(directory, fetcher));
    }
    const missingHistory = server(data);
    missingHistory.files.delete(data.manifest.funds[1].path);
    await assert.rejects(publicationStatus(directory, missingHistory.fetch));
    await assert.rejects(verifyPublication(directory, missingHistory.fetch));
});

test('unsafe remote manifests are rejected before any history request', async t => {
    const data = snapshot();
    const directory = await folder(t, data);
    for (const mutate of [
        m => m.funds[0].path = 'https://other.example/secret.json',
        m => m.funds[0].path = '../../secret.json',
        m => m.funds[0].path = 'funds/%2e%2e/secret.json',
        m => m.funds[1].id = m.funds[0].id,
        m => m.isSample = true
    ]) {
        const bad = structuredClone(data);
        mutate(bad.manifest);
        const remote = server(bad);
        await assert.rejects(publicationStatus(directory, remote.fetch));
        assert.deepEqual(remote.requests, ['manifest.json']);
    }
});

test('changed contents under an existing version cannot be overwritten silently', async t => {
    const data = snapshot();
    const directory = await folder(t, data);
    for (const mutate of [
        s => s.series[0].observations[1].value = '10501',
        s => s.manifest.publishedAt = '2026-09-06T01:00:00Z'
    ]) {
        const changed = structuredClone(data);
        mutate(changed);
        await assert.rejects(publicationStatus(directory, server(changed).fetch), /同じ版/);
        await assert.rejects(verifyPublication(directory, server(changed).fetch), /一致しません/);
    }
});

test('a shorter local history cannot replace a newer public edition', async t => {
    const directory = await folder(t);
    const newer = snapshot('2025-01-08');
    await assert.rejects(publicationStatus(directory, server(newer).fetch), /短いデータ/);
});

test('fixed URLs are overwritten without requiring a copy of each previous history', async t => {
    const old = snapshot();
    const directory = await folder(t, old);
    const next = snapshot('2025-01-07', '12000');
    await writeSnapshot(next, directory);
    assert.equal((await publicationStatus(directory, server(old).fetch)).needsDeploy, true);
    assert.deepEqual(await verifyPublication(directory, server(next).fetch), next);
});


test('a deployment between the catalog and history requests retries the catalog once', async t => {
    const old = snapshot();
    const next = snapshot('2025-01-07', '12000');
    const directory = await folder(t, next);
    const remote = server(next);
    let catalogs = 0;
    const fetcher = async (url, options) => {
        if (url === publicURL + 'manifest.json' && ++catalogs === 1) {
            return new Response(JSON.stringify(old.manifest), { headers: { 'content-type': 'application/json' } });
        }
        return remote.fetch(url, options);
    };
    assert.deepEqual(await verifyPublication(directory, fetcher), next);
    assert.equal(catalogs, 2);
});

test('persistent mixed fixed-URL contents fail verification instead of skipping publication', async t => {
    const old = snapshot();
    const next = snapshot('2025-01-07', '12000');
    const directory = await folder(t, next);
    const remote = server(next);
    remote.files.set('funds/all-country.json', JSON.stringify(old.series[0]));
    await assert.rejects(publicationStatus(directory, remote.fetch), /更新情報が一致しません/);
    assert.equal(remote.requests.filter(path => path === 'manifest.json').length, 2);
});
