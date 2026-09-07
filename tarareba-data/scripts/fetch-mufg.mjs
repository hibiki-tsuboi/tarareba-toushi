import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { day, validate, validateManifest } from './contract.mjs';

export const funds = [
    { id: 'all-country', code: '253425', associationCode: '0331418A', isin: 'JP90C000H1T1',
        name: 'eMAXIS Slim 全世界株式（オール・カントリー）', start: '2018-10-31' },
    { id: 'sp500', code: '253266', associationCode: '03311187', isin: 'JP90C000GKC6',
        name: 'eMAXIS Slim 米国株式（S&P500）', start: '2018-07-03' }
];
export const latestURL = fund => `https://developer.am.mufg.jp/fund_information_latest/association_fund_cd/${fund.associationCode}`;
export const datedURL = (fund, date) => {
    day(date);
    return `https://developer.am.mufg.jp/fund_information_date/association_fund_cd/${fund.associationCode}/base_date/${date.replaceAll('-', '')}`;
};
export const navNote = '通常の基準価額（1万口あたり・信託報酬控除後）を使用。分配金の受取額・再投資は含みません。';
const normalize = value => value.normalize('NFKC').trim();
const decimal = value => {
    assert.match(value, /^(0|[1-9][0-9]{0,11})(\.[0-9]{1,6})?$/, '不正な基準価額');
    assert(Number(value) > 0, '基準価額は正数である必要があります');
    return value;
};

// Only a successful, explicitly empty dated response means there is no observation.
// HTTP errors and API error payloads must never be treated as market holidays.
export function parseFundInformation(payload, fund, requestedDate = null) {
    if (requestedDate !== null) day(requestedDate);
    assert.equal(payload.result?.status, 200, 'APIがエラーを返しました');
    assert(payload.result.errcd == null, 'APIがエラーを返しました');
    assert.equal(payload.errors?.count, 0, 'APIがエラーを返しました');
    assert(Array.isArray(payload.datasets), 'APIのデータ配列が不正です');
    assert.equal(payload.result.retcount, payload.datasets.length, 'APIの件数が一致しません');
    if (requestedDate !== null && payload.datasets.length === 0) return null;
    assert.equal(payload.datasets.length, 1, 'APIの商品が一意ではありません');
    const record = payload.datasets[0];
    assert.equal(record.fund_cd, fund.code, 'APIの商品コードが一致しません');
    assert.equal(record.association_fund_cd, fund.associationCode, 'APIの協会コードが一致しません');
    assert.equal(record.isin_cd, fund.isin, 'APIのISINが一致しません');
    assert.equal(normalize(record.fund_name), normalize(fund.name), 'APIの商品名が一致しません');
    assert.match(record.base_date, /^\d{8}$/, 'APIの基準日が不正です');
    const date = record.base_date.replace(/^(\d{4})(\d{2})(\d{2})$/, '$1-$2-$3');
    day(date);
    assert(date >= fund.start, '設定日前のデータです');
    if (requestedDate !== null) assert.equal(date, requestedDate, 'APIの基準日が指定日と一致しません');
    assert.equal(typeof record.nav, 'number', 'APIの基準価額が数値ではありません');
    return { date, value: decimal(String(record.nav)) };
}

export async function readSnapshot(root) {
    const target = resolve(root, 'public/live');
    const manifest = await readJSON(resolve(target, 'manifest.json'));
    if (manifest === null) return null;
    validateManifest(manifest, 'live');
    const series = [];
    for (const fund of manifest.funds) series.push(await readJSON(resolve(target, fund.path)));
    return validate({ manifest, series }, 'live');
}

export function createSnapshot(histories, publishedAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')) {
    assert.equal(histories.length, funds.length);
    const series = funds.map((fund, i) => ({
        schemaVersion: 1, isSample: false, fundId: fund.id, currency: 'JPY', valueBasis: 'nav',
        source: { kind: 'official', name: '三菱UFJアセットマネジメント',
            url: `https://emaxis.am.mufg.jp/fund/${fund.code}.html`,
            note: navNote },
        observations: histories[i].observations.map(({ date, value }) => ({ date, value }))
    }));
    const lastDate = series.map(s => s.observations.at(-1).date).sort().at(0);
    const hash = createHash('sha256').update(JSON.stringify(series)).digest('hex').slice(0, 12);
    const version = `mufg-${lastDate.replaceAll('-', '')}-${hash}`;
    for (const s of series) s.datasetVersion = version;
    const manifest = { schemaVersion: 1, datasetVersion: version, isSample: false, publishedAt,
        funds: funds.map((fund, i) => ({ id: fund.id, displayName: fund.name, currency: 'JPY',
            path: `funds/${fund.id}.${version}.json`,
            firstDate: series[i].observations[0].date, lastDate: series[i].observations.at(-1).date })) };
    return validate({ manifest, series }, 'live');
}

const json = value => JSON.stringify(value, null, 2) + '\n';
async function readJSON(path) {
    try { return JSON.parse(await readFile(path, 'utf8')); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
async function atomicWrite(path, contents) {
    const temp = `${path}.${randomUUID()}.tmp`;
    try { await writeFile(temp, contents, { flag: 'wx' }); await rename(temp, path); }
    finally { await rm(temp, { force: true }); }
}

export async function writeSnapshot(snapshot, root) {
    validate(snapshot, 'live');
    const target = resolve(root, 'public/live');
    const oldManifest = await readJSON(resolve(target, 'manifest.json'));
    if (oldManifest?.datasetVersion === snapshot.manifest.datasetVersion) {
        // Content did not change. Keep the timestamp and immutable URLs identical.
        snapshot.manifest.publishedAt = oldManifest.publishedAt;
        assert.deepEqual(snapshot.manifest, oldManifest, '同じ版のmanifestが変更されています');
    } else if (oldManifest) {
        for (const fund of snapshot.manifest.funds) {
            const old = oldManifest.funds.find(f => f.id === fund.id);
            assert(old && fund.firstDate === old.firstDate && fund.lastDate >= old.lastDate, '取得履歴が短くなっています');
            const oldSeries = await readJSON(resolve(target, old.path));
            assert(oldSeries, '旧版の履歴が見つかりません');
            const dates = new Set(snapshot.series.find(s => s.fundId === fund.id).observations.map(o => o.date));
            assert(oldSeries.observations.every(o => dates.has(o.date)), '取得履歴から既存の観測日が欠けています');
        }
    }
    // Detect a collision before writing either series; never overwrite a versioned file.
    for (const fund of snapshot.manifest.funds) {
        const old = await readJSON(resolve(target, fund.path));
        if (old) assert.deepEqual(old, snapshot.series.find(s => s.fundId === fund.id), '既存の版は変更できません');
    }
    await mkdir(resolve(target, 'funds'), { recursive: true });
    for (const fund of snapshot.manifest.funds) {
        const path = resolve(target, fund.path);
        if (!await readJSON(path)) await atomicWrite(path, json(snapshot.series.find(s => s.fundId === fund.id)));
    }
    // Publish the manifest only after both validated histories exist.
    await atomicWrite(resolve(target, 'manifest.json'), json(snapshot.manifest));
    return snapshot;
}

export async function fetchBytes(url, contentType, fetcher = fetch) {
    const response = await fetcher(url, { redirect: 'error', signal: AbortSignal.timeout(20_000),
        headers: { Accept: contentType } });
    assert.equal(response.status, 200, `取得に失敗しました（${response.status}）: ${url}`);
    assert.equal(response.headers.get('content-type')?.split(';')[0].trim(), contentType, '応答形式が一致しません');
    const limit = 2 * 1024 * 1024;
    const length = response.headers.get('content-length');
    assert(length === null || (/^\d+$/.test(length) && Number(length) <= limit), '応答が2MiBを超えています');
    assert(response.body, '応答が空です');
    const chunks = [];
    let size = 0;
    for await (const chunk of response.body) {
        size += chunk.length;
        assert(size <= limit, '応答が2MiBを超えています');
        chunks.push(chunk);
    }
    return Buffer.concat(chunks);
}

const nextDay = date => new Date(day(date).getTime() + 86_400_000).toISOString().slice(0, 10);
const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

export async function updateFromMufg(root, fetcher = fetch, options = {}) {
    const existing = await readSnapshot(root);
    assert(existing || options.backfill === true,
        '保存済みの履歴がありません。初回の全履歴取得には --backfill を明示してください');
    // Fail before any network request if the saved data is incompatible or incomplete.
    const histories = funds.map(fund => {
        if (!existing) return { observations: [] };
        const series = existing.series.find(s => s.fundId === fund.id);
        assert.equal(series.valueBasis, 'nav', '先に npm run migrate:nav で既存データを移行してください');
        assert.equal(series.observations[0].date, fund.start, '設定来の履歴が揃っていません');
        return { observations: series.observations.map(o => ({ ...o })) };
    });
    const today = options.today ?? new Date(Date.now() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
    day(today);
    let requested = false;
    const download = async url => {
        if (requested) await (options.wait ?? wait)(1000);
        requested = true;
        return JSON.parse(await fetchBytes(url, 'application/json', fetcher));
    };
    for (const [index, fund] of funds.entries()) {
        const observations = histories[index].observations;
        const latest = parseFundInformation(await download(latestURL(fund)), fund);
        assert(latest.date <= today, 'APIの最新基準日が未来です');
        const previous = observations.at(-1);
        assert(!previous || latest.date >= previous.date, 'APIの最新基準日が保存済み履歴より古いです');
        if (previous?.date === latest.date) {
            // Allow a correction of the latest NAV without fetching older observations again.
            observations[observations.length - 1] = latest;
            continue;
        }
        for (let date = previous ? nextDay(previous.date) : fund.start; date <= latest.date; date = nextDay(date)) {
            const observation = date === latest.date ? latest
                : parseFundInformation(await download(datedURL(fund, date)), fund, date);
            if (observation) observations.push(observation);
        }
        assert.equal(observations[0]?.date, fund.start, '設定日の基準価額が取得できません');
    }
    // Commit only once all requested dates for both funds have been validated.
    return writeSnapshot(createSnapshot(histories), root);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        const args = process.argv.slice(2);
        assert(args.length === 0 || (args.length === 1 && args[0] === '--backfill'),
            '指定できる引数は --backfill のみです');
        const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
        const snapshot = await updateFromMufg(root, fetch, { backfill: args.includes('--backfill') });
        console.log(`Updated ${snapshot.manifest.datasetVersion}: ` +
            snapshot.series.map(s => `${s.fundId} ${s.observations.length} observations`).join(', '));
        console.log('Distribution JSON is ready. The iOS app is unchanged. No deployment was performed.');
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
