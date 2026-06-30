#!/usr/bin/env node
// Zero-dep test runner. Each test file exports an array of {name, fn} cases.
// Usage: node scripts/tests/run-all.cjs [filter-substring]
const fs = require('fs');
const path = require('path');

const dir = __dirname;
const filter = process.argv[2] || '';
const files = fs.readdirSync(dir).filter(f => f.startsWith('test-') && f.endsWith('.cjs'));

let total = 0, failed = 0;
for (const f of files) {
  const cases = require(path.join(dir, f));
  for (const c of cases) {
    if (filter && !c.name.includes(filter) && !f.includes(filter)) continue;
    total++;
    try {
      c.fn();
      process.stdout.write(`  ✓ ${f} :: ${c.name}\n`);
    } catch (err) {
      failed++;
      process.stdout.write(`  ✗ ${f} :: ${c.name}\n      ${err.message}\n`);
      if (process.env.VERBOSE) console.error(err.stack);
    }
  }
}
process.stdout.write(`\n${total - failed}/${total} passed\n`);
process.exit(failed === 0 ? 0 : 1);
