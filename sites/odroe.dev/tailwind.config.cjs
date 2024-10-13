/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: "selector",
  content: {
    relative: true,
    files: [".vitepress/theme/**/*.vue", "**/**.md"],
  },
  theme: {
    extend: {},
  },
  plugins: [],
};
