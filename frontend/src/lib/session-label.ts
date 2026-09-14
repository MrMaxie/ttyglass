export function sessionLabel(name: string, displayCommand: string): string {
  const explicitName = name.trim();
  if (explicitName.length > 0) return explicitName;

  const characters = [...displayCommand];
  return characters.length > 25 ? `${characters.slice(0, 25).join('')}(...)` : displayCommand;
}
