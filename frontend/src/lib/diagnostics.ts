export interface DiagnosticEntry {
  time: string;
  source: string;
  level: string;
  event: string;
  message?: string;
  fields: Record<string, unknown>;
}

export function formatDiagnostic(entry: DiagnosticEntry): string {
  const time = new Date(entry.time).toLocaleTimeString('en-GB', { hour12: false });
  const message = entry.message === undefined ? '' : `  ${entry.message}`;
  const fields = Object.entries(entry.fields)
    .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
    .join(' ');
  return `${time}  ${entry.level.padEnd(5)}  ${entry.source}  ${entry.event}${message}${fields ? `  ${fields}` : ''}`;
}
