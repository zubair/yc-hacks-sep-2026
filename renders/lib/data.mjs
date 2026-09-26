// Loads a postcard data file, fills defaults, validates, and derives every
// value the screen templates and the Blender scenes need. Both consumers read
// the resolved object, so a user detail is only ever typed once.
import { readFile, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const RENDERS_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const DEFAULT_COPY = {
  greeting: 'Greetings from',
  openHint: 'Open to write',
  forLabel: 'For {recipient}',
  toLabel: 'To',
  writeHint: 'Write a note',
  sendVia: 'Send with {channel}',
  prepare: 'Prepare to send',
  ready: 'Ready to send',
  readyTo: 'To {recipient}',
  continue: 'Continue',
  sealedMark: 'Sealed with love',
  sent: 'Sent to {recipient}',
  sentDetail: 'Waiting in {recipient}’s inbox.',
  received: 'A postcard from {sender}',
  receivedFrom: 'From {sender}',
  openToRead: 'Open to read',
  salutation: '{recipient},',
  signoff: 'Love, {sender}',
};

const DEFAULT_EDITORIAL = {
  wordmark: 'Postcard.',
  tagline: 'A little closer, from anywhere.',
  shots: {
    hero: { kicker: '', lines: ['A little closer,', 'from anywhere.'] },
    front: { kicker: '01 / The front', lines: ['Some places', 'stay with you.'] },
    back: { kicker: '02 / The back', lines: ['Same places.', 'A deeper connection.'] },
    sealed: { kicker: '03 / Close. Seal. Send.', lines: ['A more meaningful', 'way to travel.'] },
    sent: { kicker: '04 / Sent', lines: ['Kept safe until', 'they open it.'] },
    received: { kicker: '05 / Received', lines: ['Open to read.'] },
  },
};

const LIMITS = { name: 100, place: 200, message: 5000 };

export class DataError extends Error {}

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function deepMerge(base, over) {
  if (!isPlainObject(base) || !isPlainObject(over)) return over === undefined ? base : over;
  const out = { ...base };
  for (const [k, v] of Object.entries(over)) out[k] = deepMerge(base[k], v);
  return out;
}

export function interpolate(template, vars) {
  return String(template).replace(/\{(\w+)\}/g, (m, key) => (key in vars ? vars[key] : m));
}

function requireText(value, field, max) {
  if (typeof value !== 'string' || value.trim() === '') throw new DataError(`${field} is required`);
  if (value.length > max) throw new DataError(`${field} exceeds ${max} characters`);
  return value.trim();
}

// "14 MAG 2024" in the card's locale, the way a hand-cancel die prints it.
export function postmarkDate(isoDate, locale) {
  const d = new Date(`${isoDate}T12:00:00Z`);
  if (Number.isNaN(d.getTime())) throw new DataError(`date must be YYYY-MM-DD, got ${isoDate}`);
  const part = (opts) => new Intl.DateTimeFormat(locale, { timeZone: 'UTC', ...opts }).format(d);
  const month = part({ month: 'short' }).replace(/\.$/, '').toLocaleUpperCase(locale);
  return `${part({ day: 'numeric' })} ${month} ${part({ year: 'numeric' })}`;
}

export function longDate(isoDate, locale) {
  const d = new Date(`${isoDate}T12:00:00Z`);
  return new Intl.DateTimeFormat(locale, { timeZone: 'UTC', day: 'numeric', month: 'long', year: 'numeric' }).format(d);
}

export function screenGeometry(device) {
  const px = device.pxPerMm;
  const w = Math.round((device.pane.width - 2 * device.screen.inset) * px);
  const h = Math.round((device.pane.height - 2 * device.screen.inset) * px);
  const gap = Math.round(2 * (device.hinge.halfGap + device.screen.inset) * px);
  return {
    pane: { width: w, height: h },
    cover: { width: h, height: w }, // cover display is read in landscape
    spread: { width: 2 * w + gap, height: h, gap },
    cornerRadius: device.screen.cornerRadius * px,
    scale: device.rasterScale,
  };
}

export async function loadDevice() {
  return JSON.parse(await readFile(path.join(RENDERS_ROOT, 'device.json'), 'utf8'));
}

export function resolveData(raw, { baseDir = RENDERS_ROOT } = {}) {
  if (!isPlainObject(raw)) throw new DataError('data file must contain a JSON object');
  const id = requireText(raw.id ?? '', 'id', 60);
  if (!/^[a-z0-9][a-z0-9-]*$/.test(id)) throw new DataError('id must be lowercase letters, digits and dashes');
  const locale = raw.locale ?? 'en-US';
  try {
    new Intl.DateTimeFormat(locale);
  } catch {
    throw new DataError(`unsupported locale ${locale}`);
  }

  const sender = requireText(raw.sender?.name, 'sender.name', LIMITS.name);
  const recipient = requireText(raw.recipient?.name, 'recipient.name', LIMITS.name);
  const place = requireText(raw.place?.name, 'place.name', LIMITS.place);
  const country = requireText(raw.place?.country ?? '', 'place.country', LIMITS.place);
  const date = requireText(raw.date, 'date', 10);
  const channel = raw.delivery?.channel ?? 'Messages';
  const vars = { sender, recipient, place, country, channel };

  const copyTemplates = { ...DEFAULT_COPY, ...(raw.copy ?? {}) };
  const copy = Object.fromEntries(Object.entries(copyTemplates).map(([k, v]) => [k, interpolate(v, vars)]));

  const body = requireText(raw.message?.body, 'message.body', LIMITS.message);
  const salutation = interpolate(raw.message?.salutation ?? copyTemplates.salutation, vars);
  const signoff = interpolate(raw.message?.signoff ?? copyTemplates.signoff, vars);

  const photoSrc = requireText(raw.photo?.src, 'photo.src', 500);
  const focus = raw.photo?.focus ?? [0.5, 0.5];
  if (!Array.isArray(focus) || focus.length !== 2 || focus.some((n) => typeof n !== 'number' || n < 0 || n > 1)) {
    throw new DataError('photo.focus must be [x, y] with values between 0 and 1');
  }

  const upperCountry = country.toLocaleUpperCase(locale);
  const upperPlace = place.toLocaleUpperCase(locale);
  const editorial = deepMerge(DEFAULT_EDITORIAL, raw.editorial ?? {});

  return {
    id,
    locale,
    sender,
    recipient,
    place,
    country,
    date,
    dates: { postmark: postmarkDate(date, locale), long: longDate(date, locale) },
    message: { salutation, body, signoff },
    photo: {
      src: path.resolve(baseDir, photoSrc),
      focus,
      stampFocus: raw.photo?.stampFocus ?? focus,
    },
    stamp: { country: raw.stamp?.country ?? upperCountry, value: raw.stamp?.value ?? '1,20' },
    postmark: {
      top: raw.postmark?.top ?? upperPlace,
      bottom: raw.postmark?.bottom ?? upperCountry,
      motto: raw.postmark?.motto ?? '',
    },
    delivery: { channel, options: raw.delivery?.options ?? [channel] },
    theme: {
      handwriting: raw.theme?.handwriting ?? 'NothingYouCouldDo',
      frontPostmarkInk: raw.theme?.frontPostmarkInk ?? 'ink',
      backPostmarkInk: raw.theme?.backPostmarkInk ?? 'vermilion',
    },
    copy,
    editorial,
    scene: {
      book: raw.scene?.book ?? [upperCountry],
      finish: raw.scene?.finish ?? 'champagne',
    },
  };
}

export async function loadData(file) {
  const abs = path.resolve(file);
  let raw;
  try {
    raw = JSON.parse(await readFile(abs, 'utf8'));
  } catch (err) {
    throw new DataError(`cannot read ${file}: ${err.message}`);
  }
  const data = resolveData(raw, { baseDir: path.dirname(abs) });
  try {
    await access(data.photo.src);
  } catch {
    throw new DataError(`photo not found: ${data.photo.src}`);
  }
  return data;
}
