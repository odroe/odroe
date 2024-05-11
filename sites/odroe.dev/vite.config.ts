import { fileURLToPath } from 'url';
import { defineConfig } from 'vite';

export default defineConfig({
  resolve: {
    alias: [
      {
        find: /^.*\/VPNavBar\.vue$/,
        replacement: fileURLToPath(
          new URL('.vitepress/theme/components/navbar.vue', import.meta.url),
        ),
      },
    ],
  },
});
