// File work that needs Node: installing the bridge into ox_inventory,
// downloading item images and keeping a backup of created items.
const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');

const RESOURCE = GetCurrentResourceName();
const OWN_PATH = GetResourcePath(RESOURCE);
const BACKUP_PATH = path.join(OWN_PATH, 'backup');
const MARKER = '-- item_creator bridge';
const MANIFEST_BLOCK = [
    '',
    `${MARKER} (added automatically by the item_creator resource)`,
    "server_script 'creator/server.lua'",
    "client_script 'creator/client.lua'",
    '',
].join('\n');

const log = (message) => console.log(`^3[item_creator]^0 ${message}`);

function inventoryPath() {
    const location = GetResourcePath('ox_inventory');
    return location && fs.existsSync(location) ? location : null;
}

function readIfExists(file) {
    return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
}

// ---------------------------------------------------------------------------
// Installer
// ---------------------------------------------------------------------------
function install() {
    const target = inventoryPath();
    if (!target) return log('^1ox_inventory was not found - the bridge could not be installed.^0');

    let changed = false;

    // 1. bridge scripts
    fs.mkdirSync(path.join(target, 'creator'), { recursive: true });
    for (const name of ['server.lua', 'client.lua']) {
        const source = fs.readFileSync(path.join(OWN_PATH, 'bridge', name), 'utf8');
        const destination = path.join(target, 'creator', name);
        if (readIfExists(destination) !== source) {
            fs.writeFileSync(destination, source);
            changed = true;
        }
    }

    // 2. data file (restored from the backup when ox_inventory was replaced by an update)
    const dataFile = path.join(target, 'data', 'created_items.lua');
    if (!fs.existsSync(dataFile)) {
        const backup = readIfExists(path.join(BACKUP_PATH, 'created_items.lua'));
        fs.writeFileSync(dataFile, backup || 'return {}\n');
        if (backup) {
            const images = path.join(BACKUP_PATH, 'images');
            if (fs.existsSync(images)) {
                for (const file of fs.readdirSync(images)) {
                    const destination = path.join(target, 'web', 'images', file);
                    if (!fs.existsSync(destination)) fs.copyFileSync(path.join(images, file), destination);
                }
            }
            log('restored created items and images from the backup.');
        }
        changed = true;
    }

    // 3. fxmanifest (two lines appended once)
    const manifestFile = path.join(target, 'fxmanifest.lua');
    const manifest = fs.readFileSync(manifestFile, 'utf8');
    if (!manifest.includes(MARKER)) {
        fs.writeFileSync(manifestFile, manifest.replace(/\s*$/, '\n') + MANIFEST_BLOCK);
        changed = true;
    }

    if (changed) {
        // Remembered for as long as this server process lives: ox_inventory was
        // already running when its files were changed, so it has not loaded them.
        SetConvar('itemcreator:pendingRestart', 'true');
        log('^2The bridge was installed into ox_inventory.^0');
        log('^1ox_inventory was already running, so it has not loaded the bridge yet.^0');
        log('^1Restart the server now, or type: refresh  then  ensure ox_inventory^0');
        log('^1(今すぐサーバーを再起動するか、コンソールで refresh → ensure ox_inventory を実行してください)^0');
    }
}

/** What is actually on disk, for the status message. */
function diskState() {
    const target = inventoryPath();
    if (!target) return 'no_inventory';
    const files = ['server.lua', 'client.lua'].every((name) => fs.existsSync(path.join(target, 'creator', name)));
    const manifest = (readIfExists(path.join(target, 'fxmanifest.lua')) || '').includes(MARKER);
    return files && manifest ? 'installed' : 'missing';
}

on('item_creator:internal:diskState', () => {
    let state = 'missing';
    try {
        state = diskState();
    } catch (error) {
        log(`^1could not read the ox_inventory folder: ${error.message}^0`);
    }
    emit('item_creator:internal:diskStateResult', state);
});

on('item_creator:internal:install', () => {
    try {
        install();
    } catch (error) {
        log(`^1bridge installation failed: ${error.message}^0`);
    }
});

// ---------------------------------------------------------------------------
// Image download
// ---------------------------------------------------------------------------
function fetchBuffer(address, maxBytes, timeoutMs, redirects) {
    return new Promise((resolve, reject) => {
        let url;
        try {
            url = new URL(address);
        } catch (error) {
            return reject(new Error('invalid_url'));
        }
        if (url.protocol !== 'http:' && url.protocol !== 'https:') return reject(new Error('invalid_url'));

        const client = url.protocol === 'https:' ? https : http;
        const request = client.get(url, {
            timeout: timeoutMs,
            headers: { 'User-Agent': 'Mozilla/5.0 (compatible; item-image-fetcher)', Accept: 'image/*,*/*' },
        }, (response) => {
            const status = response.statusCode;

            if ([301, 302, 303, 307, 308].includes(status) && response.headers.location) {
                response.resume();
                if (redirects <= 0) return reject(new Error('too_many_redirects'));
                const next = new URL(response.headers.location, url).toString();
                return resolve(fetchBuffer(next, maxBytes, timeoutMs, redirects - 1));
            }
            if (status !== 200) {
                response.resume();
                return reject(new Error(`http_${status}`));
            }

            const chunks = [];
            let size = 0;
            response.on('data', (chunk) => {
                size += chunk.length;
                if (size > maxBytes) {
                    request.destroy();
                    reject(new Error('too_large'));
                } else {
                    chunks.push(chunk);
                }
            });
            response.on('end', () => resolve(Buffer.concat(chunks)));
            response.on('error', reject);
        });

        request.on('timeout', () => request.destroy(new Error('timeout')));
        request.on('error', reject);
    });
}

/** Only real images are accepted, whatever the URL or the server claims. */
function imageType(buffer) {
    if (buffer.length < 12) return null;
    if (buffer.readUInt32BE(0) === 0x89504e47) return 'image/png';
    if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return 'image/jpeg';
    if (buffer.toString('ascii', 0, 4) === 'GIF8') return 'image/gif';
    if (buffer.toString('ascii', 0, 4) === 'RIFF' && buffer.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
    return null;
}

on('item_creator:internal:download', async (id, address, name, maxBytes, timeoutMs) => {
    try {
        if (typeof name !== 'string' || !/^[a-z0-9_]+$/.test(name)) throw new Error('invalid_name');
        const target = inventoryPath();
        if (!target) throw new Error('no_inventory');

        const buffer = await fetchBuffer(String(address), maxBytes, timeoutMs, 3);
        const type = imageType(buffer);
        if (!type) throw new Error('not_image');

        // ox_inventory only ships web/images/*.png, so the file always gets a .png
        // name. The browser detects the real format from the content.
        fs.writeFileSync(path.join(target, 'web', 'images', `${name}.png`), buffer);

        fs.mkdirSync(path.join(BACKUP_PATH, 'images'), { recursive: true });
        fs.writeFileSync(path.join(BACKUP_PATH, 'images', `${name}.png`), buffer);

        emit('item_creator:internal:downloaded', id, true, `data:${type};base64,${buffer.toString('base64')}`);
    } catch (error) {
        emit('item_creator:internal:downloaded', id, false, error.message || 'failed');
    }
});

// Keeps a copy of ox_inventory/data/created_items.lua inside this resource, so
// created items survive an ox_inventory update that replaces its folder.
on('item_creator:internal:backup', () => {
    try {
        const target = inventoryPath();
        const content = target && readIfExists(path.join(target, 'data', 'created_items.lua'));
        if (!content) return;
        fs.mkdirSync(BACKUP_PATH, { recursive: true });
        fs.writeFileSync(path.join(BACKUP_PATH, 'created_items.lua'), content);
    } catch (error) {
        log(`^1backup failed: ${error.message}^0`);
    }
});
