import { type PageData, type DefaultTheme } from 'vitepress';

const pattern = (({ relativePath }: PageData) => {
  const matchLinks = [
    {
      startsWiths: ['docs/'],
      href: 'https://github.com/odroe/odroe/edit/main/:path',
    },
  ] satisfies {
    startsWiths: string[];
    href: string;
  }[];

  for (const { startsWiths, href } of matchLinks) {
    for (const startsWith of startsWiths) {
      if (relativePath.startsWith(startsWith)) {
        return new URL(relativePath, href).toString();
      }
    }
  }

  return 'https://github.com/odroe/odroe/docs';
}) satisfies DefaultTheme.EditLink['pattern'];

export default { pattern } satisfies DefaultTheme.EditLink;
