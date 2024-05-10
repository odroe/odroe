import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: {
    default: 'Odroe: Create user interfaces from Setup-widget',
    template: '%s | Odroe',
  },
  description:
    'A declarative, efficient, and flexible Flutter UI framework for building user interfaces.',
  applicationName: 'Odroe',
  appleWebApp: true,
  icons: {
    icon: {
      url: '/favicon.ico',
    },
  },
};

export default ({ children }: React.PropsWithChildren) => {
  return (
    <html lang="en">
      <body
        className="bg-white text-black dark:bg-black dark:text-white"
        style={inter.style}
      >
        {children}
      </body>
    </html>
  );
};
