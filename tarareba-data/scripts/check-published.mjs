import assert from 'node:assert/strict';
import { appendFile, readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validate, validateManifest } from './contract.mjs';
import { fetchBytes } from './fetch-mufg.mjs';

export const publicURL = 'https://tarareba-data.hibiki-apps.workers.dev/live/';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = async path => JSON.parse(await readFile(path, 'utf8'));
class MissingManifest extends Error {}
class PublicationChanged extends Error {}

export async function localSnapshot(directory = root) {
    const folder = resolve(directory, 'public/live');
    const manifest = validateManifest(await read(resolve(folder, 'manifest.json')), 'live');
    const series = [];
    for (const fund of manifest.funds) series.push(await read(resolve(folder, fund.path)));
    return validate({ manifest, series }, 'live');
}

export async function publishedSnapshot(fetcher = fetch) {
    for (let attempt = 0; attempt < 2; attempt++) {
        try { return await readPublishedSnapshot(fetcher); }
        catch (error) {
            if (!(error instanceof PublicationChanged)) throw error;
            if (attempt === 1) throw new Error('公開データの更新情報が一致しません。時間をおいて再実行してください');
        }
    }
}

async function readPublishedSnapshot(fetcher) {
    const download = async path => {
        const bytes = await fetchBytes(new URL(path, publicURL).href, 'application/json', async (url, options) => {
            const response = await fetcher(url, options);
            if (path === 'manifest.json' && response.status === 404) throw new MissingManifest();
            return response;
        });
        return JSON.parse(bytes);
    };
    let manifest;
    try { manifest = await download('manifest.json'); }
    catch (error) { if (error instanceof MissingManifest) return null; throw error; }
    // Validate paths before making any history requests.
    validateManifest(manifest, 'live');
    const series = [];
    for (const fund of manifest.funds) {
        const history = await download(fund.path);
        if (manifest.schemaVersion === 2 && history.datasetVersion !== fund.contentVersion) throw new PublicationChanged();
        series.push(history);
    }
    return validate({ manifest, series }, 'live');
}

export async function publicationStatus(directory = root, fetcher = fetch) {
    const local = await localSnapshot(directory);
    const published = await publishedSnapshot(fetcher);
    if (!published) return { needsDeploy: true, snapshot: local };
    if (local.manifest.datasetVersion === published.manifest.datasetVersion) {
        assert.deepEqual(local, published, '同じ版の公開JSONとローカルJSONが異なります。公開を中止します。');
        return { needsDeploy: false, snapshot: local };
    }
    for (const previous of published.manifest.funds) {
        const next = local.manifest.funds.find(f => f.id === previous.id);
        assert(next && next.firstDate === previous.firstDate && next.lastDate >= previous.lastDate,
            '公開中の履歴より短いデータには切り替えられません');
        const oldSeries = published.series.find(s => s.fundId === previous.id);
        // Already-published legacy URLs remain readable during migration only.
        if (published.manifest.schemaVersion === 1) {
            const archive = await read(resolve(directory, 'public/live', previous.path));
            assert.deepEqual(archive, oldSeries, '移行前の公開JSONが見つかりません');
        }
        const dates = new Set(local.series.find(s => s.fundId === previous.id).observations.map(o => o.date));
        assert(oldSeries.observations.every(o => dates.has(o.date)), '公開中の履歴から観測日が欠けています');
    }
    return { needsDeploy: true, snapshot: local };
}

export async function verifyPublication(directory = root, fetcher = fetch) {
    const local = await localSnapshot(directory);
    const published = await publishedSnapshot(fetcher);
    assert(published, '公開manifestが見つかりません');
    assert.deepEqual(published, local, '公開されたmanifest・2履歴が今回のJSONと一致しません');
    return local;
}

async function report(snapshot, message) {
    console.log(`${message}: ${snapshot.manifest.datasetVersion}`);
    if (process.env.GITHUB_STEP_SUMMARY) {
        const lines = [message, '', `版: \`${snapshot.manifest.datasetVersion}\``, '',
            ...snapshot.manifest.funds.map(f => `- ${f.id}: ${f.firstDate} 〜 ${f.lastDate}`), ''];
        await appendFile(process.env.GITHUB_STEP_SUMMARY, lines.join('\n') + '\n');
    }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        const command = process.argv[2];
        assert(process.argv.length === 3 && ['status', 'verify'].includes(command), 'status または verify を指定してください');
        if (command === 'status') {
            const result = await publicationStatus();
            if (process.env.GITHUB_OUTPUT) {
                await appendFile(process.env.GITHUB_OUTPUT, `needs_deploy=${result.needsDeploy}\n`);
            }
            await report(result.snapshot, result.needsDeploy ? '公開が必要です' : '公開済みJSONと一致しています。公開を省略します');
        } else {
            await report(await verifyPublication(), '公開されたmanifestと2履歴の一致を確認しました');
        }
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
