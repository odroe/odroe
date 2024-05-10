import dynamic from 'next/dynamic';

const basedir = '.';

export const Demo = dynamic(() => import(`${basedir}/haha`), {
  ssr: true,
});
