import { useEffect, useRef } from 'react';
import type { ChatMessage } from '../../models/ChatMessage';
import { MessageBubble } from '../MessageBubble/MessageBubble';
import { EmptyState } from '../EmptyState/EmptyState';
import styles from './MessageList.module.css';

interface Props {
  messages: ChatMessage[];
}

export function MessageList({ messages }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const lastMessageCountRef = useRef(0);
  const lastContentRef = useRef('');

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const scrollToBottom = () => {
      container.scrollTo({
        top: container.scrollHeight,
        behavior: 'smooth',
      });
    };

    requestAnimationFrame(scrollToBottom);
  }, [messages.length]);

  // Scroll on content update (streaming)
  useEffect(() => {
    const lastMsg = messages[messages.length - 1];
    if (!lastMsg) return;

    const newContent = lastMsg.content;
    if (newContent === lastContentRef.current && messages.length === lastMessageCountRef.current) return;

    lastContentRef.current = newContent;
    lastMessageCountRef.current = messages.length;

    const container = containerRef.current;
    if (!container) return;

    requestAnimationFrame(() => {
      container.scrollTo({
        top: container.scrollHeight,
        behavior: 'smooth',
      });
    });
  }, [messages]);

  if (messages.length === 0) {
    return (
      <div className={styles.container} ref={containerRef}>
        <EmptyState />
      </div>
    );
  }

  return (
    <div className={styles.container} ref={containerRef}>
      <div className={styles.list}>
        {messages.map((message) => (
          <MessageBubble key={message.id} message={message} />
        ))}
      </div>
    </div>
  );
}
