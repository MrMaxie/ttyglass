import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://mrmaxie.github.io',
  base: '/ttyglass',
  outDir: '../../docs',
  build: {
    assets: 'assets',
  },
  devToolbar: {
    enabled: false,
  },
});
