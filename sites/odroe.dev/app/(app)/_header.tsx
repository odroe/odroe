import { BrandLogo } from '@/components/brand';
import Link from 'next/link';
import { Navigation } from './_navigation';

export const Header = () => {
  return (
    <header className="w-full h-16 sticky z-auto top-0 backdrop-blur bg-white/75 dark:bg-black/75">
      <div className="mx-auto px-4 sm:px-6 lg:px-8 max-w-7xl flex items-center justify-between gap-3 h-full">
        <Link href="/" className="lg:flex-1">
          <BrandLogo className="h-6 fill-black dark:fill-white" />
        </Link>

        <Navigation className="hidden lg:flex items-center gap-x-8 h-16" />

        <div className="flex-1 justify-end hidden lg:flex">Right</div>
      </div>
    </header>
  );
};
