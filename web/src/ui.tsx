import { useId, useRef } from "react";
import type { ReactNode } from "react";
import { count, validCount } from "./domain.ts";
export function Icon({ name, size = 20 }: { name: string; size?: number }) {
  const paths: Record<string, string> = {
    plus: "M12 5v14M5 12h14",
    minus: "M5 12h14",
    arrow: "m9 5 7 7-7 7",
    back: "m15 5-7 7 7 7",
    check: "m5 12 4 4L19 6",
    info: "M12 11v6M12 7h.01M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0",
    court: "M4 3h16v18H4zM4 12h16M9 3v4h6V3M9 21v-4h6v4",
    calendar: "M5 5h14v16H5zM8 3v4M16 3v4M5 10h14",
    sun: "M12 3v2M12 19v2M3 12h2M19 12h2M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0",
    undo: "M4 10h9a6 6 0 0 1 0 12M4 10l5-5M4 10l5 5",
    download: "M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5",
    user: "M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0M4 21v-3a8 8 0 0 1 16 0v3",
    list: "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01",
  };
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d={paths[name] ?? paths.list} />
    </svg>
  );
}
export function Count({
  label,
  value,
  onChange,
  compact = false,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  compact?: boolean;
}) {
  const control = useId();
  const invalid = !validCount(value);
  const n = invalid ? null : count(value);
  return (
    <div className={`count ${compact ? "compact" : ""}`}>
      <label htmlFor={control}>{label}</label>
      <div className="stepper">
        <button
          type="button"
          aria-label={`Decrease ${label}`}
          disabled={invalid || n === null || n === 0}
          onClick={() => onChange(String((n ?? 0) - 1))}
        >
          <Icon name="minus" size={16} />
        </button>
        <input
          id={control}
          aria-invalid={invalid}
          value={value}
          inputMode="numeric"
          autoComplete="off"
          placeholder="Not entered"
          onChange={(e) => onChange(e.target.value)}
        />
        <button
          type="button"
          aria-label={`Increase ${label}`}
          disabled={invalid || n === Number.MAX_SAFE_INTEGER}
          onClick={() => onChange(String((n ?? 0) + 1))}
        >
          <Icon name="plus" size={16} />
        </button>
      </div>
      {invalid && (
        <small className="error">
          Use a nonnegative whole number within the supported range.
        </small>
      )}
    </div>
  );
}
export function Tabs({
  items,
  value,
  onChange,
  label,
}: {
  items: string[];
  value: string;
  onChange: (v: string) => void;
  label: string;
}) {
  return (
    <nav className="tabs" aria-label={label}>
      {items.map((v) => (
        <button
          key={v}
          type="button"
          aria-current={value === v ? "page" : undefined}
          onClick={() => onChange(v)}
        >
          {v}
        </button>
      ))}
    </nav>
  );
}
export function Notice({
  children,
  error = false,
}: {
  children: ReactNode;
  error?: boolean;
}) {
  return (
    <div
      className={error ? "notice error" : "notice"}
      role={error ? "alert" : undefined}
    >
      <Icon name="info" />
      <div>{children}</div>
    </div>
  );
}
export function Empty({
  title,
  children,
  action,
}: {
  title: string;
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="empty">
      <Icon name="court" size={36} />
      <h2>{title}</h2>
      <p>{children}</p>
      {action}
    </div>
  );
}
export function Scroller({
  children,
  label,
}: {
  children: ReactNode;
  label: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  return (
    <>
      <div className="scroll-guidance">
        <span>Scroll across for every column.</span>
        <span>
          <button
            type="button"
            aria-label={`Scroll ${label} left`}
            onClick={() =>
              ref.current?.scrollBy({ left: -300, behavior: "instant" })
            }
          >
            ← Previous
          </button>
          <button
            type="button"
            aria-label={`Scroll ${label} right`}
            onClick={() =>
              ref.current?.scrollBy({ left: 300, behavior: "instant" })
            }
          >
            Next →
          </button>
        </span>
      </div>
      <div
        ref={ref}
        className="table-scroll"
        tabIndex={0}
        role="region"
        aria-label={label}
      >
        {children}
      </div>
    </>
  );
}
export function download(
  name: string,
  content: string,
  type = "application/json",
) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([content], { type }));
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}
