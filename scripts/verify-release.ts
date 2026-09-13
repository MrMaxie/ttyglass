import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

interface Manifest {
  name?: string;
  private?: boolean;
  repository?: {
    type?: string;
    url?: string;
  };
  version: string;
}

const manifest = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8')) as Manifest;
const releaseTag = process.env.TTYGLASS_RELEASE_TAG;
const nativeManifests = await Promise.all(
  ['win32-x64', 'linux-x64-gnu', 'darwin-x64', 'darwin-arm64'].map(
    async (directory) =>
      JSON.parse(await readFile(new URL(`../packages/${directory}/package.json`, import.meta.url), 'utf8')) as Manifest,
  ),
);

assert.equal(typeof releaseTag, 'string', 'TTYGLASS_RELEASE_TAG is required');
assert.equal(manifest.private, undefined, 'package.json must not mark a release as private');
assert.notEqual(manifest.version, '0.0.0', '0.0.0 is reserved for local package development');
assert.equal(
  releaseTag,
  `v${manifest.version}`,
  `release tag ${releaseTag} does not match package version ${manifest.version}`,
);
for (const nativeManifest of nativeManifests) {
  assert.equal(
    nativeManifest.repository?.url,
    manifest.repository?.url,
    `${nativeManifest.name ?? 'native package'} repository must match ttyglass for npm provenance`,
  );
  assert.equal(
    nativeManifest.version,
    manifest.version,
    `${nativeManifest.name ?? 'native package'} version must match ttyglass`,
  );
}

process.stdout.write(`release ${releaseTag} matches ttyglass and all native packages at ${manifest.version}\n`);
