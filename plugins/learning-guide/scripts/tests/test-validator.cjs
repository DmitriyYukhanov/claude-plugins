const assert = require('assert');
const path = require('path');
const { validate } = require(path.join(__dirname, '..', 'validator.cjs'));

const fs = require('fs');
const schema = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', '..', 'assets', 'tour-spec.schema.json'),
  'utf8'
));

function minSpec(overrides = {}) {
  return Object.assign({
    schema_version: '1.0',
    title: 'T',
    lang: 'en',
    archetype: 'generic',
    sections: [{ id: 'intro', level: 1, title: 'Intro', body_md: 'hi' }]
  }, overrides);
}

module.exports = [
  { name: 'minimal valid spec passes', fn: () => {
    const errs = validate(minSpec(), schema);
    assert.deepStrictEqual(errs, []);
  }},
  { name: 'missing required field reports it', fn: () => {
    const s = minSpec(); delete s.title;
    const errs = validate(s, schema);
    assert.ok(errs.some(e => e.path === '/' && /title/.test(e.message)),
      JSON.stringify(errs));
  }},
  { name: 'wrong type reports path', fn: () => {
    const errs = validate(minSpec({ title: 42 }), schema);
    assert.ok(errs.some(e => e.path === '/title'), JSON.stringify(errs));
  }},
  { name: 'enum violation', fn: () => {
    const errs = validate(minSpec({ archetype: 'unknown' }), schema);
    assert.ok(errs.some(e => e.path === '/archetype'), JSON.stringify(errs));
  }},
  { name: 'pattern violation on lang', fn: () => {
    const errs = validate(minSpec({ lang: 'English' }), schema);
    assert.ok(errs.some(e => e.path === '/lang'), JSON.stringify(errs));
  }},
  { name: 'additionalProperties rejected', fn: () => {
    const errs = validate(minSpec({ extra: 1 }), schema);
    assert.ok(errs.some(e => e.path === '/' && /extra/.test(e.message)),
      JSON.stringify(errs));
  }},
  { name: 'nested array item validated', fn: () => {
    const errs = validate(minSpec({
      sections: [{ id: 'intro', level: 99, title: 'X', body_md: 'y' }]
    }), schema);
    assert.ok(errs.some(e => e.path === '/sections/0/level'),
      JSON.stringify(errs));
  }},
  { name: '$ref resolves internal definition', fn: () => {
    const errs = validate(minSpec({
      glossary: [{ term: '', definition: 'd' }]
    }), schema);
    assert.ok(errs.some(e => e.path === '/glossary/0/term'),
      JSON.stringify(errs));
  }},
  { name: 'patternProperties on external_links', fn: () => {
    const errs = validate(minSpec({
      external_links: { 'lowercase-': 'https://x.example/{id}' }
    }), schema);
    assert.ok(errs.some(e => e.path === '/external_links'),
      JSON.stringify(errs));
  }},
  { name: 'patternProperties accepts valid prefix', fn: () => {
    const errs = validate(minSpec({
      external_links: { 'TICKET-': 'https://x.example/{id}' }
    }), schema);
    assert.deepStrictEqual(errs, []);
  }},
  { name: '{id} required in external_links template', fn: () => {
    const errs = validate(minSpec({
      external_links: { 'TICKET-': 'https://x.example/no-placeholder' }
    }), schema);
    assert.ok(errs.some(e => e.path === '/external_links/TICKET-'),
      JSON.stringify(errs));
  }},
  // R3 — external-link scheme allowlist enforced at schema level.
  { name: 'external_links rejects javascript: scheme', fn: () => {
    const errs = validate(minSpec({
      external_links: { 'EVIL-': 'javascript:alert(1)/{id}' }
    }), schema);
    assert.ok(errs.some(e => e.path === '/external_links/EVIL-'),
      JSON.stringify(errs));
  }},
  { name: 'external_links accepts mailto: with {id}', fn: () => {
    const errs = validate(minSpec({
      external_links: { 'MAIL-': 'mailto:team@x.example?subject={id}' }
    }), schema);
    assert.deepStrictEqual(errs, []);
  }},
  // CF8 — cross_ref source must be a valid embedded-source name (no selector-injection chars).
  { name: 'cross_ref source must be a valid name', fn: () => {
    const errs = validate(minSpec({
      cross_ref_patterns: [{ pattern: 'X', source: 'a"b' }]
    }), schema);
    assert.ok(errs.some(e => e.path === '/cross_ref_patterns/0/source'), JSON.stringify(errs));
  }}
];
