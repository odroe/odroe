'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  Popover,
  PopoverButton,
  PopoverGroup,
  PopoverPanel,
  Transition,
  type PopoverGroupProps,
} from '@headlessui/react';
import { ChevronDownIcon } from '@heroicons/react/16/solid';
import classes from './nav.module.css';

type NavLink = { label: string; href: string };
type DropdownLinkChild = NavLink & {
  desc: string;
};
type DropdownLink = NavLink & { children: DropdownLinkChild[] };

const navigation: (NavLink | DropdownLink)[] = [
  { label: 'Docs', href: '/docs' },
  { label: 'UI', href: '/ui' },
  { label: 'Templates', href: '/templates' },
  { label: 'Showcase', href: '/showcase' },
  {
    label: 'Enterprise',
    href: '/enterprise',
    children: [
      {
        label: 'Support',
        href: '/enterprise/support',
        desc: 'Get help with Odroe directly from the team that creates it.',
      },
      {
        label: 'Sponsors',
        href: '/enterprise/sponsors',
        desc: 'Become a sponsor and get your logo on our README on GitHub with a link to your site.',
      },
    ],
  },
  { label: 'Blog', href: '/blog' },
];

const DropdownNavItem = ({ label, href, desc }: DropdownLinkChild) => {
  const pathname = usePathname();

  return (
    <a
      className="block rounded-lg py-2 px-3 transition dark:hover:bg-white/5 hover:bg-gray-500/5"
      href={href}
      aria-selected={pathname.startsWith(href)}
    >
      <p className="font-semibold dark:text-white text-black">{label}</p>
      <p className="dark:text-white/50 text-black/50 line-clamp-2">{desc}</p>
    </a>
  );
};

const DropdownNav = ({ label, href, children }: DropdownLink) => {
  const pathname = usePathname();

  return (
    <Popover className="relative">
      <PopoverButton
        className={`${classes.nav_link} group focus:outline-none flex items-center cursor-pointer`}
        aria-selected={pathname.startsWith(href)}
      >
        {label}
        <ChevronDownIcon className="size-4 transition-all group-aria-expanded:rotate-180" />
      </PopoverButton>

      <Transition
        enter="transition ease-out duration-200"
        enterFrom="opacity-0 translate-y-1"
        enterTo="opacity-100 translate-y-0"
        leave="transition ease-in duration-150"
        leaveFrom="opacity-100 translate-y-0"
        leaveTo="opacity-0 translate-y-1"
      >
        <PopoverPanel
          anchor={{
            to: 'bottom',
            gap: 12,
          }}
          className="rounded-xl bg-white/5 text-sm/6 [--anchor-gap:var(--spacing-5)] shadow border dark:border-white/5 border-black/10 backdrop-blur z-50"
        >
          <div className="p-3 max-w-80">
            {children.map((props) => (
              <DropdownNavItem key={props.href} {...props} />
            ))}
          </div>
        </PopoverPanel>
      </Transition>
    </Popover>
  );
};

const NavItem = (props: NavLink | DropdownLink) => {
  if ('children' in props && props.children.length) {
    return <DropdownNav {...props} />;
  }

  const { label, href } = props;
  const pathname = usePathname();

  return (
    <Link
      key={href}
      href={href}
      aria-selected={pathname.startsWith(href)}
      className={classes.nav_link}
    >
      {label}
    </Link>
  );
};

export const Navigation = (props: Omit<PopoverGroupProps<'nav'>, 'as'>) => (
  <PopoverGroup {...props} as="nav">
    {navigation.map((nav) => (
      <NavItem key={nav.href} {...nav} />
    ))}
  </PopoverGroup>
);
