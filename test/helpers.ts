import { resolve } from 'node:path';

export function nativeExecutable(): string {
  const target = new Map([
    ['win32:x64', ['win32-x64', 'ttyglass.exe']],
    ['linux:x64', ['linux-x64-gnu', 'ttyglass']],
    ['darwin:x64', ['darwin-x64', 'ttyglass']],
    ['darwin:arm64', ['darwin-arm64', 'ttyglass']],
  ]).get(`${process.platform}:${process.arch}`);
  if (target === undefined) {
    throw new Error(`Unsupported test platform ${process.platform}/${process.arch}`);
  }
  return resolve('packages', target[0] ?? '', 'bin', target[1] ?? '');
}
