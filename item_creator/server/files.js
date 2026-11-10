// Downloads item images. Node is only used for the HTTP request: all file
// writing is done from Lua (SaveResourceFile), because the FXServer Node
// runtime does not allow scripts to write files.
const http = require('http');
const https = require('https');

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

// Answers with (id, true, mimeType, base64) or (id, false, errorKey).
on('item_creator:internal:download', async (id, address, maxBytes, timeoutMs) => {
    try {
        const buffer = await fetchBuffer(String(address), maxBytes, timeoutMs, 3);
        const type = imageType(buffer);
        if (!type) throw new Error('not_image');
        emit('item_creator:internal:downloaded', id, true, type, buffer.toString('base64'));
    } catch (error) {
        emit('item_creator:internal:downloaded', id, false, error.message || 'failed');
    }
});
