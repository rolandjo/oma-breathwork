const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const model = {};
vm.createContext(model);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../BreathworkModel.js'), 'utf8').replace(/^\.pragma library\s*/, ''), model);
let checks = 0;
function test(name, fn) { fn(); checks++; console.log('PASS', name); }
const empty = () => ({ version: 1, protocols: [] });
const draft = name => ({ name, inhale: 5.5, holdIn: 0, exhale: 5.5, holdOut: 0 });

test('long duplicate names have stable distinct IDs across reloads and edits', () => {
  let library = empty();
  for (let i = 0; i < 12; i++) library = model.saveProtocol(library, draft('A'.repeat(60))).library;
  library = model.parseProtocolLibrary(JSON.stringify(library));
  assert.equal(library.protocols.length, 12);
  assert.equal(new Set(library.protocols.map(p => p.id)).size, 12);
  const id = library.protocols[1].id;
  library = model.saveProtocol(library, { ...draft('Renamed'), id }).library;
  assert.equal(model.findProtocolRecord(library, id).name, 'Renamed');
  assert.equal(model.removeProtocol(library, id).protocols.length, 11);
});
test('punctuation and non-ASCII names can coexist', () => {
  let library = empty();
  for (const name of ['!!!', '呼吸', '呼吸', 'Morning calm']) library = model.saveProtocol(library, draft(name)).library;
  assert.equal(model.parseProtocolLibrary(JSON.stringify(library)).protocols.length, 4);
});
test('Coherent timings survive creating a saved version', () => {
  const timing = model.timingFromPattern(model.pattern('coherent'));
  const saved = model.saveProtocol(empty(), { name: 'My Coherent', ...timing });
  const library = model.parseProtocolLibrary(JSON.stringify(saved.library));
  assert.equal(model.pattern('saved:' + saved.record.id, {}, library).phases[0].secs, 5.5);
  assert.equal(model.cycleSeconds(model.pattern('saved:' + saved.record.id, {}, library)), 11);
});
test('full Power sequence includes release on every round', () => {
  for (const rounds of [1, 4, 20]) {
    for (let round = 1; round <= rounds; round++) {
      const transition = (stage, elapsed) => model.powerTransition(stage, elapsed, 30, 2, 10, round, rounds, 15 + (round - 1) * 10);
      assert.equal(transition('breathing', 59.99), '');
      assert.equal(transition('breathing', 60), 'retention');
      assert.equal(transition('retention', 14.999 + (round - 1) * 10), '');
      assert.equal(transition('retention', 15 + (round - 1) * 10), 'recoveryIn');
      assert.equal(transition('recoveryIn', 1), 'recoveryHold');
      assert.equal(transition('recoveryHold', 9.99), '');
      assert.equal(transition('recoveryHold', 10), 'release');
      assert.equal(transition('release', 0.99), '');
      assert.equal(transition('release', 1), round === rounds ? 'complete' : 'nextRound');
    }
  }
});
test('motion starts immediately and stays continuous at phase boundaries', () => {
  assert.equal(model.breathProgress(0), 0);
  assert.equal(model.breathProgress(1), 1);
  let previous = 0;
  for (let i = 1; i <= 1000; i++) {
    const progress = model.breathProgress(i / 1000);
    assert.ok(progress > previous && progress <= 1);
    previous = progress;
  }
  assert.ok(model.breathAt(model.pattern('box'), 0.1).fullness > 0.005);
  for (const key of model.PATTERN_ORDER) {
    const pattern = model.pattern(key);
    let boundary = 0;
    for (const phase of pattern.phases) {
      boundary += phase.secs;
      assert.ok(Math.abs(model.breathAt(pattern, boundary - 1e-6).fullness - model.breathAt(pattern, boundary).fullness) < 1e-5);
    }
  }
});
test('statistics switch correctly when the supplied date rolls over', () => {
  const stats = { days: { '2026-09-26': 6 } };
  assert.equal(model.todayMinutes(stats, '2026-09-26'), 6);
  assert.equal(model.todayMinutes(stats, '2026-09-27'), 0);
  assert.equal(model.streakDays(stats, '2026-09-27'), 1);
  assert.equal(model.streakDays(stats, '2026-09-28'), 0);
});
test('invalid libraries are detected before replacing the last good view', () => {
  assert.equal(model.protocolLibraryIsValid('{'), false);
  assert.equal(model.protocolLibraryIsValid('{"version":2,"protocols":[]}'), false);
  const library = model.saveProtocol(empty(), draft('Valid')).library;
  assert.equal(model.protocolLibraryIsValid(JSON.stringify(library)), true);
  library.protocols.push(library.protocols[0]);
  assert.equal(model.protocolLibraryIsValid(JSON.stringify(library)), false);
});
test('Power tooltip follows current rounds, pace, and separate hold settings', () => {
  const options = {powerRounds: 8, powerBreaths: 35, powerBreathSeconds: 3, powerRetentionHold: 15, powerRetentionIncrease: 10, powerRecoveryHold: 15};
  const description = model.protocolDescription(model.pattern('power'), options);
  assert.ok(description.includes('8 rounds · 35 breaths per round'));
  assert.ok(description.includes('3 sec per breath'));
  assert.ok(description.includes('Exhale holds: 15 / 25 / 35 / 45 / 55 / 65 / 75 / 85 sec'));
  assert.ok(description.includes('Recovery hold: 15 sec each round'));
  options.powerRounds = 1;
  options.powerRetentionHold = 25;
  assert.ok(model.protocolDescription(model.pattern('power'), options).includes('Exhale holds: 25 sec'));
  assert.ok(model.protocolDescription(model.pattern('power'), options).startsWith('1 round ·'));
});
test('ordinary protocol tooltips describe actual built-in, custom, and saved timings', () => {
  assert.ok(model.protocolDescription(model.pattern('coherent')).includes('Breathe in: 5.5 sec'));
  const custom = model.pattern('custom', {customIn: 7, customHoldIn: 2, customOut: 8, customHoldOut: 3});
  assert.equal(model.protocolDescription(custom), 'Breathe in: 7 sec · Hold after inhale: 2 sec · Breathe out: 8 sec · Hold after exhale: 3 sec');
  const saved = model.saveProtocol(empty(), draft('Saved'));
  assert.ok(model.protocolDescription(model.recordPattern(saved.record)).includes('Breathe out: 5.5 sec'));
});
test('double inhale preserves intermediate fullness through payload and saved copies', () => {
  const sigh = model.pattern('sigh');
  assert.equal(model.cycleSeconds(sigh), 10);
  const payload = model.pattern('sigh', {patternData: JSON.parse(JSON.stringify(sigh))});
  assert.equal(payload.phases[0].to, 0.8);
  assert.equal(model.breathAt(payload, 3).phaseIndex, 1);
  assert.equal(model.breathAt(payload, 3).fullness, 0.8);
  assert.ok(model.breathAt(payload, 3.5).fullness > 0.8);
  assert.equal(model.breathAt(payload, 4).fullness, 1);
  assert.equal(model.breathAt(payload, 4).phaseIndex, 2);
  const timings = model.timingFromPattern(sigh);
  assert.equal(timings.topUp, 1);
  const saved = model.saveProtocol(empty(), {name: 'My sigh', ...timings});
  const reloaded = model.parseProtocolLibrary(JSON.stringify(saved.library));
  assert.equal(model.recordPattern(reloaded.protocols[0]).phases.length, 3);
  assert.equal(model.recordPattern(reloaded.protocols[0]).phases[0].to, 0.8);
  assert.ok(model.protocolDescription(model.recordPattern(reloaded.protocols[0])).includes('Top-up inhale: 1 sec'));
  const disabled = model.saveProtocol(reloaded, {id: saved.record.id, name: 'No top-up', ...timings, topUp: 0});
  assert.equal(model.recordPattern(disabled.record).phases.length, 2);
});
console.log(`${checks} model checks passed`);
