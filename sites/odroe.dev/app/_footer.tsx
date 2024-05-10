import { ArrowUpRightIcon } from '@heroicons/react/24/solid';
import Link from 'next/link';
import { footerLinks } from './_footer.metadata';
import { SimpleIconsX } from '@/components/icons/x(twitter)';
import { SimpleIconsDiscord } from '@/components/icons/discord';
import { SimpleIconsGithub } from '@/components/icons/github';

const Subscribe = () => {
  return (
    <div className="mt-10 xl:mt-0">
      <form>
        <div className="flex content-center items-center justify-between text-base">
          <label
            className="block text-gray-700 dark:text-gray-200 font-semibold"
            htmlFor="subscribe"
          >
            Subscribe to our newsletter
          </label>
        </div>
        <p className="text-gray-500 dark:text-gray-400 text-sm">
          Stay updated on new releases and features, guides, and community
          updates.
        </p>
        <div className="relative mt-3 z-0 max-w-sm">
          <input
            type="email"
            name="email"
            id="subscribe"
            className="relative block w-full disabled:cursor-not-allowed disabled:opacity-75 focus:outline-none border-0 form-input rounded-md placeholder-gray-400 dark:placeholder-gray-500 text-base px-3.5 py-2.5 shadow-sm bg-white dark:bg-gray-900 text-gray-900 dark:text-white ring-1 ring-inset ring-gray-300 dark:ring-gray-700 focus:ring-2 focus:ring-primary-500 dark:focus:ring-primary-400 pe-12"
            placeholder="you@domain.com"
          />
          <span className="absolute inset-y-0 end-0 flex items-center px-3.5">
            <button
              type="submit"
              className="focus:outline-none focus-visible:outline-0 disabled:cursor-not-allowed disabled:opacity-75 flex-shrink-0 font-medium rounded-md text-xs gap-x-1.5 px-2.5 py-1.5 shadow-sm text-white dark:text-gray-900 bg-gray-900 hover:bg-gray-800 disabled:bg-gray-900 dark:bg-white dark:hover:bg-gray-100 dark:disabled:bg-white focus-visible:ring-inset focus-visible:ring-2 focus-visible:ring-primary-500 dark:focus-visible:ring-primary-400 inline-flex items-center"
            >
              Subscribe
            </button>
          </span>
        </div>
      </form>
    </div>
  );
};

export const Footer = () => {
  return (
    <footer>
      <div className="border-t border-gray-200 dark:border-gray-800 mx-auto px-4 sm:px-6 lg:px-8 max-w-7xl py-8 lg:py-12 xl:grid xl:grid-cols-3 xl:gap-8">
        <div className="flex flex-col lg:grid grid-flow-col auto-cols-fr gap-8 xl:col-span-2">
          {footerLinks.map(({ label, links }) => (
            <div key={label}>
              <h3 className="text-sm/6 font-semibold text-gray-900 dark:text-white">
                {label}
              </h3>
              <ul className="mt-6 space-y-4">
                {links.map(({ label, href, target = false }) => (
                  <li key={href}>
                    <Link
                      href={href}
                      className="text-sm relative text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white z-0"
                      target={target ? '_blank' : undefined}
                      rel={target ? 'noopener noreferrer' : undefined}
                    >
                      {label}
                      {target && (
                        <ArrowUpRightIcon className="size-3 absolute top-0.5 -right-3.5 text-gray-400 dark:text-gray-500" />
                      )}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
        <Subscribe />
      </div>

      <div className="border-t border-gray-200 dark:border-gray-800 mx-auto px-4 sm:px-6 lg:px-8 max-w-7xl py-8 lg:py-12 xl:grid xl:grid-cols-3 xl:gap-8">
        <div className="lg:flex-1 flex items-center justify-center lg:justify-end gap-x-1.5 lg:order-3">
          <a
            href="https://twitter.com/OdroeDev"
            target="_blank"
            rel="noopener noreferrer"
            className="focus:outline-none focus-visible:outline-0 disabled:cursor-not-allowed disabled:opacity-75 flex-shrink-0 font-medium rounded-md text-sm gap-x-1.5 p-1.5 text-gray-700 dark:text-gray-200 hover:text-gray-900 dark:hover:text-white hover:bg-gray-50 dark:hover:bg-gray-800 focus-visible:ring-inset focus-visible:ring-2 focus-visible:ring-primary-500 dark:focus-visible:ring-primary-400 inline-flex items-center"
            aria-label="Odroe on X"
          >
            <SimpleIconsX className="size-5 flex-shrink-0" />
          </a>
          <a
            href="http://"
            target="_blank"
            rel="noopener noreferrer"
            className="focus:outline-none focus-visible:outline-0 disabled:cursor-not-allowed disabled:opacity-75 flex-shrink-0 font-medium rounded-md text-sm gap-x-1.5 p-1.5 text-gray-700 dark:text-gray-200 hover:text-gray-900 dark:hover:text-white hover:bg-gray-50 dark:hover:bg-gray-800 focus-visible:ring-inset focus-visible:ring-2 focus-visible:ring-primary-500 dark:focus-visible:ring-primary-400 inline-flex items-center"
            aria-label="Nuxt on Discord"
          >
            <SimpleIconsDiscord className="size-5 flex-shrink-0" />
          </a>
          <a
            href="https://github.com/odroe/odroe"
            target="_blank"
            rel="noopener noreferrer"
            className="focus:outline-none focus-visible:outline-0 disabled:cursor-not-allowed disabled:opacity-75 flex-shrink-0 font-medium rounded-md text-sm gap-x-1.5 p-1.5 text-gray-700 dark:text-gray-200 hover:text-gray-900 dark:hover:text-white hover:bg-gray-50 dark:hover:bg-gray-800 focus-visible:ring-inset focus-visible:ring-2 focus-visible:ring-primary-500 dark:focus-visible:ring-primary-400 inline-flex items-center"
            aria-label="Odroe on GitHub"
          >
            <SimpleIconsGithub className="size-5 flex-shrink-0" />
          </a>
        </div>
        <div className="mt-3 lg:mt-0 lg:order-2 flex items-center justify-center"></div>
        <div className="flex items-center justify-center lg:justify-start lg:flex-1 gap-x-1.5 mt-3 lg:mt-0 lg:order-1">
          <p className="text-gray-500 dark:text-gray-400 text-sm">
            Copyright © {new Date().getFullYear()} Odroe Inc. -{' '}
            <a
              href="https://github.com/odroe/odroe?tab=MIT-1-ov-file"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:underline"
            >
              MIT license
            </a>
          </p>
        </div>
      </div>
    </footer>
  );
};
