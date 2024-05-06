import { read } from '$app/server';
import { markdown } from '$lib/server/markdown/index.js';
import { getTypedPages } from '$lib/server/contents.js';
import { error } from '@sveltejs/kit';
import matter from 'gray-matter';

export async function load({ params }) {
  const pages = getTypedPages('docs');
  const current = pages.find((page) => page.slug == params.slug);
  if (!current) error(404);

  const contents = await read(current.asset).text();
  const { content } = matter(contents);

  return {
    pages,
    current,
    content: markdown.render(content),
  };
}
