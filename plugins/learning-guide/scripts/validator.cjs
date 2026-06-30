'use strict';
// Focused JSON Schema validator. Supports: type, required, properties,
// additionalProperties, patternProperties, enum, pattern, minimum/maximum,
// minLength/maxLength, minItems/maxItems, items, $ref (internal #/$defs/*).
// Conditional keywords (if/then/else) are intentionally IGNORED — they exist in
// the shipped schema as editor hints only; render.cjs + the analyze quality gate
// are the authoritative enforcers for level>=2 → parent (see design-gate R16).
// Returns array of { path, message } — empty array means valid.

function validate(value, schema, root) {
  root = root || schema;
  const errors = [];
  walk(value, schema, '', errors, root);
  return errors;
}

function resolveRef(ref, root) {
  if (!ref.startsWith('#/')) throw new Error('only internal $refs supported: ' + ref);
  const parts = ref.slice(2).split('/');
  let cur = root;
  for (const p of parts) cur = cur[p];
  if (!cur) throw new Error('cannot resolve $ref: ' + ref);
  return cur;
}

function jsonType(v) {
  if (v === null) return 'null';
  if (Array.isArray(v)) return 'array';
  if (Number.isInteger(v)) return 'integer';
  if (typeof v === 'number') return 'number';
  return typeof v;
}

function typeMatches(v, t) {
  if (Array.isArray(t)) return t.some(x => typeMatches(v, x));
  const got = jsonType(v);
  if (t === 'number') return got === 'number' || got === 'integer';
  return got === t;
}

function walk(value, schema, path, errors, root) {
  if (schema.$ref) {
    walk(value, resolveRef(schema.$ref, root), path, errors, root);
    return;
  }

  if (schema.type !== undefined && !typeMatches(value, schema.type)) {
    errors.push({ path: path || '/', message: `expected type ${JSON.stringify(schema.type)}, got ${jsonType(value)}` });
    return;
  }

  if (schema.enum !== undefined && !schema.enum.includes(value)) {
    errors.push({ path: path || '/', message: `value not in enum ${JSON.stringify(schema.enum)}` });
    return;
  }

  const t = jsonType(value);

  if (t === 'string') {
    if (schema.minLength !== undefined && value.length < schema.minLength)
      errors.push({ path: path || '/', message: `string shorter than minLength ${schema.minLength}` });
    if (schema.maxLength !== undefined && value.length > schema.maxLength)
      errors.push({ path: path || '/', message: `string longer than maxLength ${schema.maxLength}` });
    if (schema.pattern !== undefined && !new RegExp(schema.pattern).test(value))
      errors.push({ path: path || '/', message: `string does not match pattern /${schema.pattern}/` });
  }

  if (t === 'number' || t === 'integer') {
    if (schema.minimum !== undefined && value < schema.minimum)
      errors.push({ path: path || '/', message: `value less than minimum ${schema.minimum}` });
    if (schema.maximum !== undefined && value > schema.maximum)
      errors.push({ path: path || '/', message: `value greater than maximum ${schema.maximum}` });
  }

  if (t === 'array') {
    if (schema.minItems !== undefined && value.length < schema.minItems)
      errors.push({ path: path || '/', message: `array shorter than minItems ${schema.minItems}` });
    if (schema.maxItems !== undefined && value.length > schema.maxItems)
      errors.push({ path: path || '/', message: `array longer than maxItems ${schema.maxItems}` });
    if (schema.items)
      value.forEach((it, i) => walk(it, schema.items, `${path}/${i}`, errors, root));
  }

  if (t === 'object') {
    if (Array.isArray(schema.required)) {
      for (const k of schema.required)
        if (!Object.prototype.hasOwnProperty.call(value, k))
          errors.push({ path: path || '/', message: `missing required property "${k}"` });
    }
    const props = schema.properties || {};
    const patternProps = schema.patternProperties || {};
    for (const k of Object.keys(value)) {
      const sub = props[k];
      if (sub) {
        walk(value[k], sub, `${path}/${k}`, errors, root);
        continue;
      }
      let matched = false;
      for (const re of Object.keys(patternProps)) {
        if (new RegExp(re).test(k)) {
          walk(value[k], patternProps[re], `${path}/${k}`, errors, root);
          matched = true;
          break;
        }
      }
      if (!matched && schema.additionalProperties === false)
        errors.push({ path: path || '/', message: `unexpected property "${k}"` });
    }
  }
}

module.exports = { validate };
