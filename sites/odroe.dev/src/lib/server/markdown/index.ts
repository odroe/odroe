import markdownit from 'markdown-it/index.js';

export const markdown = markdownit({
  html: true,
  linkify: true,
});
