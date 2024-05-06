import markdownit from 'markdown-it';

export const markdown = markdownit({
  html: true,
  linkify: true,
});
