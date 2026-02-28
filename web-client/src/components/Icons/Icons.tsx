import { type SVGProps } from 'react';

type IconProps = SVGProps<SVGSVGElement> & { size?: number };

function iconProps({ size = 24, ...rest }: IconProps): SVGProps<SVGSVGElement> {
  return {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.5,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    ...rest,
  };
}

/** SF Symbol: plus.message */
export function PlusMessageIcon(props: IconProps) {
  return (
    <svg {...iconProps(props)}>
      <path d="M4 18l-1.5 3.5L7 20l4 0c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2H4c-1.1 0-2 .9-2 2v8c0 1.1.9 2 2 2z" />
      <path d="M22 6v8c0 1.1-.9 2-2 2h-1" />
      <path d="M22 6c0-1.1-.9-2-2-2h-7c-1.1 0-2 .9-2 2" />
      <line x1="16" y1="8" x2="16" y2="14" />
      <line x1="13" y1="11" x2="19" y2="11" />
    </svg>
  );
}

/** SF Symbol: gear */
export function GearIcon(props: IconProps) {
  return (
    <svg {...iconProps(props)}>
      <circle cx="12" cy="12" r="3" />
      <path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" />
    </svg>
  );
}

/** SF Symbol: mic.fill */
export function MicIcon(props: IconProps) {
  return (
    <svg {...iconProps(props)}>
      <rect x="9" y="2" width="6" height="12" rx="3" fill="currentColor" stroke="none" />
      <path d="M5 10v1a7 7 0 0014 0v-1" />
      <line x1="12" y1="18" x2="12" y2="22" />
      <line x1="8" y1="22" x2="16" y2="22" />
    </svg>
  );
}

/** SF Symbol: waveform */
export function WaveformIcon(props: IconProps) {
  return (
    <svg {...iconProps(props)}>
      <line x1="4" y1="8" x2="4" y2="16" />
      <line x1="8" y1="5" x2="8" y2="19" />
      <line x1="12" y1="2" x2="12" y2="22" />
      <line x1="16" y1="5" x2="16" y2="19" />
      <line x1="20" y1="8" x2="20" y2="16" />
    </svg>
  );
}

/** SF Symbol: ellipsis.circle.fill */
export function EllipsisCircleIcon(props: IconProps) {
  return (
    <svg {...iconProps({ ...props, stroke: 'none' })}>
      <circle cx="12" cy="12" r="11" fill="currentColor" />
      <circle cx="7" cy="12" r="1.5" fill="var(--color-background, white)" />
      <circle cx="12" cy="12" r="1.5" fill="var(--color-background, white)" />
      <circle cx="17" cy="12" r="1.5" fill="var(--color-background, white)" />
    </svg>
  );
}

/** SF Symbol: speaker.wave.2.fill */
export function SpeakerIcon(props: IconProps) {
  return (
    <svg {...iconProps(props)}>
      <path d="M3 9h3l5-5v16l-5-5H3V9z" fill="currentColor" stroke="none" />
      <path d="M15.5 8a5 5 0 010 8" />
      <path d="M18 5a9 9 0 010 14" />
    </svg>
  );
}

/** SF Symbol: arrow.up.circle.fill */
export function SendIcon(props: IconProps) {
  return (
    <svg {...iconProps({ ...props, stroke: 'none' })}>
      <circle cx="12" cy="12" r="11" fill="currentColor" />
      <path
        d="M12 7l-4 4h2.5v5h3v-5H16l-4-4z"
        fill="var(--color-background, white)"
      />
    </svg>
  );
}

/** SF Symbol: bubble.left.and.bubble.right */
export function ChatBubblesIcon(props: IconProps) {
  const { size = 24, ...rest } = props;
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1}
      strokeLinecap="round"
      strokeLinejoin="round"
      {...rest}
    >
      <path d="M3 14c0 1.66 1.34 3 3 3h1v3l3-3h3c1.66 0 3-1.34 3-3V8c0-1.66-1.34-3-3-3H6C4.34 5 3 6.34 3 8v6z" />
      <path d="M16 8h2c1.66 0 3 1.34 3 3v6c0 1.66-1.34 3-3 3h-1v3l-3-3" />
    </svg>
  );
}

/** SF Symbol: eye */
export function EyeIcon(props: IconProps) {
  return (
    <svg {...iconProps(props)}>
      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

/** SF Symbol: eye.slash */
export function EyeSlashIcon(props: IconProps) {
  return (
    <svg {...iconProps(props)}>
      <path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94" />
      <path d="M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19" />
      <path d="M14.12 14.12a3 3 0 11-4.24-4.24" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
  );
}

/** SF Symbol: checkmark.circle.fill */
export function CheckmarkCircleIcon(props: IconProps) {
  return (
    <svg {...iconProps({ ...props, stroke: 'none' })}>
      <circle cx="12" cy="12" r="11" fill="currentColor" />
      <path
        d="M7.5 12.5l3 3 6-6"
        stroke="var(--color-background, white)"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </svg>
  );
}
