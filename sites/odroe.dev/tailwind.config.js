/** @type {import('tailwindcss').Config} */
export default {
  prefix: 'tw-',
  darkMode: ['selector', '.dark'],
  content: ['./.vitepress/theme/**/*.{ts,vue}', './**/*.md'],
  theme: {
    extend: {},
  },
  plugins: [],
};
