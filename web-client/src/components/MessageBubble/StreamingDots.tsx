import styles from './StreamingDots.module.css';

export function StreamingDots() {
  return (
    <div className={styles.container}>
      {[0, 1, 2].map((i) => (
        <div
          key={i}
          className={styles.dot}
          style={{ animationDelay: `${i * 200}ms` }}
        />
      ))}
    </div>
  );
}
