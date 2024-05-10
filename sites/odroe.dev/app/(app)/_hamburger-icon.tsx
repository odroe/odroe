export const HanburgerIcon = ({ open }: { open: boolean }) => {
  return (
    <span
      className="relative size-6 group overflow-hidden block aria-expanded:translate-y-0.5 transition-all"
      aria-expanded={open}
    >
      <span className="transition-all w-full h-0.5 bg-black absolute left-0 top-0 origin-center translate-y-0.5 group-hover:translate-x-1/4 group-aria-expanded:-translate-x-0 group-aria-expanded:translate-y-2.5 group-aria-expanded:-rotate-45 rounded-full" />
      <span className="transition-all w-full h-0.5 bg-black absolute left-0 top-0 translate-y-2.5 translate-x-2/4 group-hover:translate-x-0 group-aria-expanded:translate-x-full rounded-full" />
      <span className="transition-all w-full h-0.5 bg-black absolute left-0 bottom-0 origin-center -translate-y-0.5 translate-x-1/4 group-hover:translate-x-2/4 group-aria-expanded:translate-x-0 group-aria-expanded:-translate-y-3 group-aria-expanded:rotate-45 rounded-full" />
    </span>
  );
};
