import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import { day, ids, validate } from './contract.mjs';

export function generate({ start = '2020-01-06', end = '2026-09-04', seed = 42, version = 'sample-v1' } = {}) {
    const from = day(start), to = day(end);
    if (from > to || (to - from) / 86400000 > 20_000 || !Number.isInteger(seed) || seed < 0 || seed > 0xffffffff) {
        throw new Error('期間またはシードが不正です。');
    }
    let state = seed >>> 0;
    const random = () => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state / 4294967296; };
    const values = [10000, 10000];
    const observations = [[], []];
    let index = 0;
    for (let date = new Date(from); date <= to; date.setUTCDate(date.getUTCDate() + 1)) {
        if ([0, 6].includes(date.getUTCDay())) continue;
        // Deliberately fictional cycles, including declines and flat stretches.
        const cycle = Math.floor(index / 120) % 4;
        const drifts = [[0.0011, 0.0016], [-0.0009, -0.0014], [0, 0], [0.0014, 0.0007]][cycle];
        for (let f = 0; f < 2; f++) {
            const noise = (random() - 0.5) * 0.007;
            if (index > 0) values[f] *= 1 + drifts[f] + (cycle === 2 ? 0 : noise);
            observations[f].push({ date: date.toISOString().slice(0, 10), value: values[f].toFixed(6) });
        }
        index++;
    }
    if (!index) throw new Error('期間に平日がありません。');
    const names = ['オルカン（サンプル）', 'S&P500（サンプル）'];
    const manifest = {
        schemaVersion: 1, datasetVersion: version, isSample: true,
        publishedAt: `${end}T00:00:00Z`,
        funds: ids.map((id, i) => ({ id, displayName: names[i], currency: 'JPY',
            path: `funds/${id}.${version}.json`, firstDate: observations[i][0].date, lastDate: observations[i].at(-1).date }))
    };
    const series = ids.map((fundId, i) => ({ schemaVersion: 1, datasetVersion: version, isSample: true,
        fundId, currency: 'JPY', valueBasis: 'reinvestedIndex',
        source: { kind: 'synthetic', name: '開発用に生成した架空の比較データ', url: null,
            note: `実際の運用実績ではありません。平日のみの架空データで、日本の営業日カレンダーではありません。seed=${seed}` },
        observations: observations[i] }));
    return validate({ manifest, series });
}

const json = value => JSON.stringify(value, null, 2) + '\n';
async function immutableWrite(path, value) {
    const content = json(value);
    try {
        const current = await readFile(path, 'utf8');
        if (current !== content) throw new Error(`既存の版は変更できません。--version で新版を指定してください: ${path}`);
    } catch (error) {
        if (error.code !== 'ENOENT') throw error;
        await writeFile(path, content, { flag: 'wx' });
    }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const options = {};
    const args = process.argv.slice(2);
    for (let i = 0; i < args.length; i += 2) {
        const key = args[i].replace(/^--/, '');
        if (!['start', 'end', 'seed', 'version'].includes(key) || args[i + 1] === undefined) throw new Error('引数が不正です。');
        options[key] = key === 'seed' ? Number(args[i + 1]) : args[i + 1];
    }
    const snapshot = generate(options);
    const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
    const target = resolve(root, 'public/sample');
    const bundle = resolve(root, '../ios/TararebaToushi/Resources/BundledSample.json');
    await mkdir(resolve(target, 'funds'), { recursive: true });
    for (const f of snapshot.manifest.funds) {
        await immutableWrite(resolve(target, f.path), snapshot.series.find(s => s.fundId === f.id));
    }
    await writeFile(resolve(target, 'manifest.json'), json(snapshot.manifest));
    await mkdir(dirname(bundle), { recursive: true });
    await writeFile(bundle, json(snapshot));
    console.log(`Generated ${snapshot.manifest.datasetVersion}: ${snapshot.series[0].observations.length} observations per fund; public + bundle.`);
}
