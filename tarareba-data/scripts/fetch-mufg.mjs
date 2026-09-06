import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { day, validate } from './contract.mjs';

export const funds = [
    { id: 'all-country', code: '253425', associationCode: '0331418A', isin: 'JP90C000H1T1',
        name: 'eMAXIS Slim 全世界株式（オール・カントリー）', start: '2018-10-31' },
    { id: 'sp500', code: '253266', associationCode: '03311187', isin: 'JP90C000GKC6',
        name: 'eMAXIS Slim 米国株式（S&P500）', start: '2018-07-03' }
];
export const csvURL = fund => `https://www.am.mufg.jp/fund_file/setteirai/${fund.code}.csv`;
export const latestURL = fund => `https://developer.am.mufg.jp/fund_information_latest/association_fund_cd/${fund.associationCode}`;
export const headers = ['基準日', '基準価額(円)', '基準価額（分配金再投資）(円)', '分配金（税引前）(円)', '純資産総額（億円）'];
const normalize = value => value.normalize('NFKC').trim();
const decimal = value => {
    assert.match(value, /^(0|[1-9][0-9]{0,11})(\.[0-9]{1,6})?$/, '不正な基準価額');
    assert(Number(value) > 0, '基準価額は正数である必要があります');
    return value;
};

// RFC 4180 quoting; reject a changed format instead of silently dropping rows/columns.
export function parseCSV(text) {
    const rows = [];
    let row = [], field = '', quoted = false, closed = false;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (quoted) {
            if (c === '"') {
                if (text[i + 1] === '"') { field += '"'; i++; }
                else { quoted = false; closed = true; }
            } else { field += c; }
        } else if (c === ',' || c === '\n' || c === '\r') {
            row.push(field); field = ''; closed = false;
            if (c !== ',') {
                rows.push(row); row = [];
                if (c === '\r' && text[i + 1] === '\n') i++;
            }
        } else if (c === '"') {
            assert(!field && !closed, '不正なCSV引用符'); quoted = true;
        } else {
            assert(!closed, 'CSV引用符の後に不正な文字があります'); field += c;
        }
    }
    assert(!quoted, 'CSV引用符が閉じていません');
    if (row.length || field || closed) { row.push(field); rows.push(row); }
    return rows;
}

export function parseMufgCSV(text, fund) {
    const rows = parseCSV(text.replace(/^\uFEFF/, ''));
    assert.deepEqual(rows[0]?.map(normalize), [normalize(fund.name)], 'CSVの商品が一致しません');
    assert.deepEqual(rows[1]?.map(normalize), headers.map(normalize), 'CSVの列構成が変わっています');
    assert(rows.length > 2 && rows.length <= 30_002, 'CSVの履歴件数が不正です');
    let previous = '';
    const observations = [], navs = new Map();
    for (const row of rows.slice(2)) {
        assert.equal(row.length, headers.length, 'CSVの列が不足しています');
        assert.match(row[0], /^\d{4}\/\d{2}\/\d{2}$/);
        const date = row[0].replaceAll('/', '-');
        day(date);
        assert(date > previous, 'CSVの観測日は昇順・重複なしである必要があります');
        const nav = decimal(row[1]), reinvested = decimal(row[2]);
        // Take the provider's reinvested series directly; do not add distributions again.
        if (row[3] !== '') {
            assert.match(row[3], /^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$/, '分配金の形式が不正です');
        }
        navs.set(date, nav);
        observations.push({ date, value: reinvested });
        previous = date;
    }
    assert.equal(observations[0].date, fund.start, '設定来の履歴が揃っていません');
    return { observations, navs };
}

export function validateLatest(payload, history, fund) {
    assert.equal(payload.result?.status, 200, 'APIがエラーを返しました');
    assert.equal(payload.errors?.count, 0, 'APIがエラーを返しました');
    assert.equal(payload.datasets?.length, 1, 'APIの商品が一意ではありません');
    const record = payload.datasets[0];
    assert.equal(record.fund_cd, fund.code);
    assert.equal(record.association_fund_cd, fund.associationCode);
    assert.equal(record.isin_cd, fund.isin);
    assert.equal(normalize(record.fund_name), normalize(fund.name));
    assert.match(record.base_date, /^\d{8}$/);
    const date = record.base_date.replace(/^(\d{4})(\d{2})(\d{2})$/, '$1-$2-$3');
    day(date);
    assert.equal(date, history.observations.at(-1).date, 'CSVとAPIの基準日が不一致です。時間をおいて再実行してください');
    assert.equal(decimal(String(record.nav)), history.navs.get(date), 'CSVとAPIの基準価額が一致しません');
}

export function createSnapshot(histories, publishedAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')) {
    assert.equal(histories.length, funds.length);
    const series = funds.map((fund, i) => ({
        schemaVersion: 1, isSample: false, fundId: fund.id, currency: 'JPY', valueBasis: 'reinvestedIndex',
        source: { kind: 'official', name: '三菱UFJアセットマネジメント',
            url: `https://emaxis.am.mufg.jp/fund/${fund.code}.html`,
            note: '公式「設定来データ」の基準価額（分配金再投資）を使用。税引前分配金を再投資した系列で、信託報酬控除後の値です。分配金の加算や信託報酬の再控除はしていません。' },
        observations: histories[i].observations.map(o => ({ ...o }))
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

export async function updateFromMufg(root, fetcher = fetch) {
    const histories = [];
    // Four serial requests per invocation, including the daily workflow.
    for (const fund of funds) {
        const csv = await fetchBytes(csvURL(fund), 'text/csv', fetcher);
        const history = parseMufgCSV(new TextDecoder('shift_jis', { fatal: true }).decode(csv), fund);
        const payload = JSON.parse(await fetchBytes(latestURL(fund), 'application/json', fetcher));
        validateLatest(payload, history, fund);
        histories.push(history);
    }
    return writeSnapshot(createSnapshot(histories), root);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        assert.equal(process.argv.length, 2, 'このコマンドは引数を取りません');
        const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
        const snapshot = await updateFromMufg(root);
        console.log(`Updated ${snapshot.manifest.datasetVersion}: ` +
            snapshot.series.map(s => `${s.fundId} ${s.observations.length} observations`).join(', '));
        console.log('Distribution JSON is ready. The iOS app is unchanged. No deployment was performed.');
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
