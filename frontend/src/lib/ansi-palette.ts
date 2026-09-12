import type { ITheme } from '@xterm/xterm';

import type { ColorScheme } from './color-schemes';

interface RgbColor {
  red: number;
  green: number;
  blue: number;
}

type PaletteKey =
  | 'background'
  | 'foreground'
  | 'selectionBackground'
  | 'black'
  | 'red'
  | 'green'
  | 'yellow'
  | 'blue'
  | 'magenta'
  | 'cyan'
  | 'white'
  | 'brightBlack'
  | 'brightRed'
  | 'brightGreen'
  | 'brightYellow'
  | 'brightBlue'
  | 'brightMagenta'
  | 'brightCyan'
  | 'brightWhite';

const paletteKeys: readonly PaletteKey[] = [
  'background',
  'black',
  'selectionBackground',
  'brightBlack',
  'red',
  'brightRed',
  'green',
  'brightGreen',
  'yellow',
  'brightYellow',
  'blue',
  'brightBlue',
  'magenta',
  'brightMagenta',
  'cyan',
  'brightCyan',
  'white',
  'brightWhite',
  'foreground',
];

// biome-ignore lint/suspicious/noControlCharactersInRegex: ANSI SGR sequences start with the escape control character.
const sgrPattern = /\u001b\[([0-9:;]*)m/g;

function parseHexColor(value: string | undefined): RgbColor | undefined {
  const match = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(value ?? '');
  if (match === null) {
    return undefined;
  }
  return {
    red: Number.parseInt(match[1] ?? '', 16),
    green: Number.parseInt(match[2] ?? '', 16),
    blue: Number.parseInt(match[3] ?? '', 16),
  };
}

function colorDistance(left: RgbColor, right: RgbColor): number {
  const redMean = (left.red + right.red) / 2;
  const red = left.red - right.red;
  const green = left.green - right.green;
  const blue = left.blue - right.blue;
  return (2 + redMean / 256) * red * red + 4 * green * green + (2 + (255 - redMean) / 256) * blue * blue;
}

function mapColor(color: RgbColor, source: ITheme, target: ITheme): RgbColor {
  let nearestKey: PaletteKey = 'foreground';
  let nearestDistance = Number.POSITIVE_INFINITY;

  for (const key of paletteKeys) {
    const referenceColor = parseHexColor(source[key]);
    if (referenceColor === undefined) {
      continue;
    }
    const distance = colorDistance(color, referenceColor);
    if (distance < nearestDistance) {
      nearestKey = key;
      nearestDistance = distance;
    }
  }

  return parseHexColor(target[nearestKey]) ?? parseHexColor(target.foreground) ?? color;
}

function indexedColor(index: number): RgbColor | undefined {
  if (index < 16 || index > 255) {
    return undefined;
  }
  if (index >= 232) {
    const value = 8 + (index - 232) * 10;
    return { red: value, green: value, blue: value };
  }
  const cubeIndex = index - 16;
  const levels = [0, 95, 135, 175, 215, 255] as const;
  return {
    red: levels[Math.floor(cubeIndex / 36)] ?? 0,
    green: levels[Math.floor((cubeIndex % 36) / 6)] ?? 0,
    blue: levels[cubeIndex % 6] ?? 0,
  };
}

function isColorCommand(value: string): boolean {
  return value === '38' || value === '48' || value === '58';
}

function validByte(value: string | undefined): number | undefined {
  if (value === undefined || !/^\d{1,3}$/.test(value)) {
    return undefined;
  }
  const parsed = Number(value);
  return parsed >= 0 && parsed <= 255 ? parsed : undefined;
}

function mappedParameters(command: string, color: RgbColor): string[] {
  return [command, '2', String(color.red), String(color.green), String(color.blue)];
}

function transformColonParameter(parameter: string, source: ITheme, target: ITheme): string {
  const parts = parameter.split(':');
  const command = parts[0] ?? '';
  if (!isColorCommand(command)) {
    return parameter;
  }
  if (parts[1] === '2') {
    const red = validByte(parts.at(-3));
    const green = validByte(parts.at(-2));
    const blue = validByte(parts.at(-1));
    if (red === undefined || green === undefined || blue === undefined) {
      return parameter;
    }
    const mapped = mapColor({ red, green, blue }, source, target);
    return `${command}:2::${mapped.red}:${mapped.green}:${mapped.blue}`;
  }
  if (parts[1] === '5') {
    const index = validByte(parts.at(-1));
    const color = index === undefined ? undefined : indexedColor(index);
    if (color === undefined) {
      return parameter;
    }
    const mapped = mapColor(color, source, target);
    return `${command}:2::${mapped.red}:${mapped.green}:${mapped.blue}`;
  }
  return parameter;
}

function transformSgr(parameters: string, source: ITheme, target: ITheme): string {
  const parts = parameters.split(';');
  const transformed: string[] = [];

  for (let index = 0; index < parts.length; index += 1) {
    const command = parts[index] ?? '';
    if (command.includes(':')) {
      transformed.push(transformColonParameter(command, source, target));
      continue;
    }
    if (!isColorCommand(command)) {
      transformed.push(command);
      continue;
    }

    const mode = parts[index + 1];
    if (mode === '2') {
      const red = validByte(parts[index + 2]);
      const green = validByte(parts[index + 3]);
      const blue = validByte(parts[index + 4]);
      if (red !== undefined && green !== undefined && blue !== undefined) {
        transformed.push(...mappedParameters(command, mapColor({ red, green, blue }, source, target)));
        index += 4;
        continue;
      }
    } else if (mode === '5') {
      const paletteIndex = validByte(parts[index + 2]);
      const color = paletteIndex === undefined ? undefined : indexedColor(paletteIndex);
      if (color !== undefined) {
        transformed.push(...mappedParameters(command, mapColor(color, source, target)));
        index += 2;
        continue;
      }
    }
    transformed.push(command);
  }

  return transformed.join(';');
}

function splitIncompleteControlSequence(data: string): { complete: string; remainder: string } {
  const escapeIndex = data.lastIndexOf('\u001b');
  if (escapeIndex < 0) {
    return { complete: data, remainder: '' };
  }
  const suffix = data.slice(escapeIndex);
  if (suffix === '\u001b') {
    return { complete: data.slice(0, escapeIndex), remainder: suffix };
  }
  if (suffix.startsWith('\u001b[') && !/[\x40-\x7e]/.test(suffix.slice(2))) {
    return { complete: data.slice(0, escapeIndex), remainder: suffix };
  }
  return { complete: data, remainder: '' };
}

export class AnsiPaletteMapper {
  readonly #source: ITheme;
  #scheme: ColorScheme;
  #remainder = '';

  constructor(source: ITheme, scheme: ColorScheme) {
    this.#source = source;
    this.#scheme = scheme;
  }

  setScheme(scheme: ColorScheme): void {
    this.#scheme = scheme;
  }

  reset(): void {
    this.#remainder = '';
  }

  transform(chunk: string): string {
    const { complete, remainder } = splitIncompleteControlSequence(this.#remainder + chunk);
    this.#remainder = remainder;
    if (this.#scheme.id === 'default') {
      return complete;
    }
    return complete.replaceAll(sgrPattern, (_sequence, parameters: string) => {
      return `\u001b[${transformSgr(parameters, this.#source, this.#scheme.terminal)}m`;
    });
  }
}
