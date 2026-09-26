import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolveData, postmarkDate, screenGeometry, DataError } from '../lib/data.mjs';

const minimal = {
  id: 'demo',
  locale: 'it-IT',
  sender: { name: 'Alex' },
  recipient: { name: 'Olivia' },
  place: { name: 'Cinque Terre', country: 'Italia' },
  date: '2024-05-14',
  message: { body: 'Wish you were here.' },
  photo: { src: 'photo.jpg' },
};

test('names flow into every derived string exactly once', () => {
  const d = resolveData(minimal, { baseDir: '/tmp' });
  assert.equal(d.message.salutation, 'Olivia,');
  assert.equal(d.message.signoff, 'Love, Alex');
  assert.equal(d.copy.forLabel, 'For Olivia');
  assert.equal(d.copy.received, 'A postcard from Alex');
  assert.equal(d.postmark.top, 'CINQUE TERRE');
  assert.equal(d.stamp.country, 'ITALIA');
  assert.equal(d.photo.src, '/tmp/photo.jpg');
});

test('overrides win over defaults and still interpolate', () => {
  const d = resolveData({ ...minimal, copy: { signoff: 'Baci, {sender}' }, message: { body: 'x', salutation: 'Cara {recipient}' } }, { baseDir: '/tmp' });
  assert.equal(d.message.signoff, 'Baci, Alex');
  assert.equal(d.message.salutation, 'Cara Olivia');
});

test('postmark date follows the card locale', () => {
  assert.equal(postmarkDate('2024-05-14', 'it-IT'), '14 MAG 2024');
  assert.equal(postmarkDate('2024-09-03', 'pt-PT'), '3 SET 2024');
  assert.equal(postmarkDate('2024-08-14', 'en-GB'), '14 AUG 2024');
});

test('rejects missing names, bad focus, over-long messages', () => {
  assert.throws(() => resolveData({ ...minimal, recipient: {} }), DataError);
  assert.throws(() => resolveData({ ...minimal, photo: { src: 'a.jpg', focus: [2, 0] } }), DataError);
  assert.throws(() => resolveData({ ...minimal, message: { body: 'x'.repeat(5001) } }), DataError);
  assert.throws(() => resolveData({ ...minimal, id: 'Bad Id' }), DataError);
});

test('screen geometry matches the modelled displays', () => {
  const g = screenGeometry({ pxPerMm: 10, rasterScale: 3, pane: { width: 80, height: 116 }, screen: { inset: 3, cornerRadius: 7.5 }, hinge: { halfGap: 1.5 } });
  assert.deepEqual(g.pane, { width: 740, height: 1100 });
  assert.deepEqual(g.cover, { width: 1100, height: 740 });
  assert.equal(g.spread.width, 740 * 2 + 90);
});
