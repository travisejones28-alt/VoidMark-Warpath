// Development only: node tools/download_source.mjs ../reference
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
const manifest=JSON.parse(await fs.readFile(new URL('./source.json',import.meta.url),'utf8'));
const destination=path.resolve(process.argv[2] || '../reference');
await fs.mkdir(destination,{recursive:true});
for(const file of manifest.files){
 const response=await fetch(`https://raw.githubusercontent.com/${manifest.repository}/${manifest.commit}/${file.path}`);
 if(!response.ok)throw new Error(`${file.path}: ${response.status}`);
 const data=Buffer.from(await response.arrayBuffer());
 if(crypto.createHash('sha256').update(data).digest('hex')!==file.sha256)throw new Error(`Source checksum mismatch: ${file.path}`);
 await fs.writeFile(path.join(destination,file.local),data);
}
const b=manifest.blacklist;
const response=await fetch(`https://raw.githubusercontent.com/${b.repository}/${b.commit}/${b.path}`);
if(!response.ok)throw new Error('Availability reference download failed');
await fs.writeFile(path.join(destination,'QuestieQuestBlacklist.lua'),await response.text());
console.log('Pinned reference files downloaded and checksummed. Run Lua importer from repository root.');
