import { useEffect, useRef } from 'react';

export function useAutoScroll(deps: unknown[]) {
  const containerRef = useRef<HTMLDivElement>(null);
  const prevDepsRef = useRef<unknown[]>([]);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const scrollToBottom = () => {
      container.scrollTo({
        top: container.scrollHeight,
        behavior: 'smooth',
      });
    };

    // Use requestAnimationFrame to ensure DOM has updated
    requestAnimationFrame(scrollToBottom);

    prevDepsRef.current = deps;
  }, deps); // eslint-disable-line react-hooks/exhaustive-deps

  return containerRef;
}
