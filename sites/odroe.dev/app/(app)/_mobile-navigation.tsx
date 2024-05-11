'use client';

import { Button, Dialog, DialogPanel, Transition } from '@headlessui/react';
import { createContext, useContext, useState } from 'react';
import { Header } from './_header';
import Link from 'next/link';
import { BrandLogo } from '@/components/brand';

export const HanburgerIcon = () => {
  return (
    <span className="relative size-6 overflow-hidden block aria-expanded:translate-y-0.5 transition-all">
      <span className="transition-all w-full h-0.5 bg-current absolute left-0 top-0 origin-center translate-y-0.5 group-hover:translate-x-1/4 group-aria-expanded:-translate-x-0 group-aria-expanded:translate-y-2.5 group-aria-expanded:-rotate-45 rounded-full" />
      <span className="transition-all w-full h-0.5 bg-current absolute left-0 top-0 translate-y-2.5 translate-x-2/4 group-hover:translate-x-0 group-aria-expanded:translate-x-full rounded-full" />
      <span className="transition-all w-full h-0.5 bg-current absolute left-0 bottom-0 origin-center -translate-y-0.5 translate-x-1/4 group-hover:translate-x-2/4 group-aria-expanded:translate-x-0 group-aria-expanded:-translate-y-3 group-aria-expanded:rotate-45 rounded-full" />
    </span>
  );
};

const context = createContext(false);

const AppBar = ({ onClose }: { onClose: () => void }) => {
  const open = useContext(context);

  return (
    <div className="w-full h-16 sticky top-0 z-50 border-b border-b-gray-200 dark:border-b-gray-800">
      <div className="mx-auto px-4 sm:px-6 lg:px-8 max-w-7xl flex items-center justify-between gap-3 h-full">
        <Link href="/" className="lg:flex-1">
          <BrandLogo className="h-6 fill-black dark:fill-white" />
        </Link>
        <Button className="group" onClick={onClose} aria-expanded={open}>
          <HanburgerIcon />
        </Button>
      </div>
    </div>
  );
};

export const MobileNavigation = () => {
  const [isOpen, setOpenState] = useState(false);
  const taggleOpen = () => setOpenState(!isOpen);

  return (
    <context.Provider value={isOpen}>
      <Button className="group" onClick={taggleOpen} aria-expanded={isOpen}>
        <HanburgerIcon />
      </Button>
      <Transition appear show={isOpen}>
        <div className="fixed inset-0 z-20 w-screen top-16 overflow-y-auto bg-transparent backdrop-blur">
          <div className="max-w-lg space-y-4 bg-white p-12">222</div>
        </div>
      </Transition>
    </context.Provider>
  );
};
