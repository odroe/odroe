import { read } from '$app/server';
import matter from 'gray-matter';

const markdown = import.meta.glob<string>('../../../contents/**/*.md', {
  eager: true,
  query: '?url',
  import: 'default',
});

type Category = {
  index: number;
  title: string;
};

type Metadata = {
  title?: string;
  description?: string;
};

export type Page = {
  type: string;
  index: number;
  category: Category;
  slug: string;
  asset: string;
  metadata: Metadata;
};

export const pages: Page[] = [];

for (const [filename, asset] of Object.entries(markdown)) {
  const [, type, categoryIndex, categoryTitle, index, slug] =
    /.+\/(.+?)\/(\d{2})-(.+?)\/(\d{2})-(.+?).md$/gi.exec(filename)!;
  const contents = await read(asset).text();
  const { data: metadata } = matter(contents);

  pages.push({
    type,
    category: { index: Number(categoryIndex), title: categoryTitle },
    metadata,
    slug,
    asset,
    index: Number(index),
  });
}

export function getTypedPages(type: 'docs') {
  return pages.filter((page) => page.type == type);
}
