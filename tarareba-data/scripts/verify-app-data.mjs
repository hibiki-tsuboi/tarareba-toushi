import assert from 'node:assert/strict';
import { readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// The application currently needs no JSON/CSV resources. Asset-catalog metadata is the only source-tree exception.
export async function verifyNoDataFiles(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
        const path = resolve(directory, entry.name);
        if (entry.isDirectory()) {
            if (!entry.name.endsWith('.xcassets')) await verifyNoDataFiles(path);
        } else {
            assert(!/\.(json|jsonc|csv)$/i.test(entry.name), `アプリにデータファイルを同梱できません: ${path}`);
        }
    }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    const path = process.argv[2];
    assert(path?.endsWith('.app') && process.argv.length === 3, 'ビルド済みの .app パスを1つ指定してください');
    await verifyNoDataFiles(resolve(path));
    console.log('Verified: the built app contains no JSON/CSV data resources.');
}
