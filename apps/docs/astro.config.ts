import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://maxie.dev/',
  base: '/ttyglass',
  outDir: '../../docs',
  build: {
    assets: 'assets',
  },
  devToolbar: {
    enabled: false,
  },
});
