// Narrow untrusted JSON before using it in the host broker.
export const ACCOUNTS = ["personal", "work"] as const;
export type Account = (typeof ACCOUNTS)[number];
export type Route = Account | "auto";

export function isAccount(value: unknown): value is Account {
  return value === "personal" || value === "work";
}

export function isRoute(value: unknown): value is Route {
  return value === "auto" || isAccount(value);
}

export function record(value: unknown): Record<string, unknown> | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

export function list(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

export function hasCode(error: unknown, code: string): boolean {
  return record(error)?.code === code;
}
