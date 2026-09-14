import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const vendorRoot = resolve('vendor', 'libvterm');
const checksumFile = resolve(vendorRoot, 'SHA256SUMS');
const entries = readFileSync(checksumFile, 'utf8')
  .trim()
  .split(/\r?\n/u)
  .map((line) => {
    const match = /^([0-9a-f]{64}) {2}(.+)$/u.exec(line);
    if (match === null) {
      throw new Error(`Invalid libvterm checksum entry: ${line}`);
    }
    return { expected: match[1], path: match[2] };
  });

for (const entry of entries) {
  const actual = createHash('sha256')
    .update(readFileSync(resolve(vendorRoot, entry.path)))
    .digest('hex');
  if (actual !== entry.expected) {
    throw new Error(`libvterm checksum mismatch for ${entry.path}: expected ${entry.expected}, got ${actual}`);
  }
}

console.log(`Verified ${entries.length} libvterm 0.3.3 build inputs.`);
