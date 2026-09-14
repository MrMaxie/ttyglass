import { svelte } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vite';

import packageMetadata from '../package.json' with { type: 'json' };

export default defineConfig({
  define: {
    __TTYGLASS_VERSION__: JSON.stringify(packageMetadata.version),
  },
  plugins: [svelte()],
  build: {
    rollupOptions: {
      output: {
        assetFileNames: 'assets/app.[ext]',
        chunkFileNames: 'assets/[name].js',
        entryFileNames: 'assets/app.js',
      },
    },
  },
});
