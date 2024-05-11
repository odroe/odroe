import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';
import glob from 'fast-glob';

const docsSource = fileURLToPath(new URL('../../../docs', import.meta.url));

export default {
  paths() {
    const allMarkdownFiles = glob.sync(['**.md'], {
      cwd: docsSource,
      onlyFiles: true,
    });

    return allMarkdownFiles.map((file) => ({
      params: {
        slug: path.join(path.dirname(file), path.basename(file, '.md')),
      },
      content: fs.readFileSync(path.join(docsSource, file)).toString('utf-8'),
    }));
  },
};
