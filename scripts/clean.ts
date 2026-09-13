import { rm } from 'node:fs/promises';
import { resolve } from 'node:path';

const platformDirectories = new Map([
  ['win32:x64', 'win32-x64'],
  ['linux:x64', 'linux-x64-gnu'],
  ['darwin:x64', 'darwin-x64'],
  ['darwin:arm64', 'darwin-arm64'],
]);

const platformDirectory = platformDirectories.get(`${process.platform}:${process.arch}`);
await Promise.all([
  rm(new URL('../dist', import.meta.url), { force: true, recursive: true }),
  rm(new URL('../frontend/dist', import.meta.url), { force: true, recursive: true }),
  ...(platformDirectory === undefined
    ? []
    : [rm(resolve('packages', platformDirectory, 'bin'), { force: true, recursive: true })]),
]);
