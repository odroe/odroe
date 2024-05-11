import { BrandLogo } from '@/components/brand';
import Link from 'next/link';
import { Navigation } from './_navigation';
import { MobileNavigation } from './_mobile-navigation';
import { SimpleIconsGithub } from '@/components/icons/github';

export const Header = () => {
  return (
    <header className="w-full h-16 sticky top-0 z-30 backdrop-blur bg-white/5 dark:bg-black/5 border-b border-b-gray-200 dark:border-b-gray-800 lg:border-b-0">
      <div className="mx-auto px-4 sm:px-6 lg:px-8 max-w-7xl flex items-center justify-between gap-3 h-full">
        <div className="lg:flex-1">
          <Link href="/" className=" inline-block">
            <BrandLogo className="h-6 fill-black dark:fill-white" />
          </Link>
        </div>
        <Navigation className="hidden lg:flex items-center gap-x-8 h-16" />
        <div className="flex-1 justify-end hidden items-center lg:flex gap-2">
          <Link
            href="https://github.com/odroe/odroe"
            target="_blank"
            rel="noopener noreferrer"
            className="p-1 rounded hover:bg-gray-50 dark:hover:bg-gray-800"
          >
            <SimpleIconsGithub className="size-5 fill-gray-700  dark:fill-gray-200" />
          </Link>
        </div>
        <MobileNavigation />
      </div>
    </header>
  );
};
