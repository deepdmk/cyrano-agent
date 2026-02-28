import styles from './AudioLevelBars.module.css';

interface Props {
  level: number; // 0-1 normalized
  visible: boolean;
}

const BAR_COUNT = 5;
const BASE_HEIGHT = 4;
const MAX_HEIGHT = 24;

export function AudioLevelBars({ level, visible }: Props) {
  if (!visible) return null;

  const normalized = Math.max(0, Math.min(1, level));

  return (
    <div className={styles.container}>
      {Array.from({ length: BAR_COUNT }, (_, i) => {
        const variation = Math.sin(i * 1.2 + normalized * 5) * 0.3 + 0.7;
        const height = BASE_HEIGHT + (MAX_HEIGHT - BASE_HEIGHT) * normalized * variation;
        return (
          <div
            key={i}
            className={styles.bar}
            style={{ height: `${height}px` }}
          />
        );
      })}
    </div>
  );
}
