// Makes a new owner admin token. Paste the TOKEN into Warpath (Owner > Analytics > Settings)
// and store only the SHA-256 in Cloudflare:  npx wrangler secret put ADMIN_TOKEN_SHA256
// Nothing is written to disk.
import { randomBytes, createHash } from 'node:crypto';
const token = randomBytes(32).toString('base64url');
const hash = createHash('sha256').update(token).digest('hex');
console.log('TOKEN (paste into Warpath, keep private):\n  ' + token);
console.log('ADMIN_TOKEN_SHA256 (paste into wrangler secret put):\n  ' + hash);
