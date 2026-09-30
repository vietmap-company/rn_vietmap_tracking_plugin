#!/usr/bin/env node
/**
 * Fail the build when an iOS selector is declared but not implemented.
 *
 * RCT_EXTERN_METHOD registers a selector on the bridge without checking that
 * Swift implements it, so a declaration with no matching @objc compiles cleanly
 * and crashes at call time with "unrecognized selector". That is how 14 methods
 * stayed broken in 0.1.x. See UPGRADE_PLAN.md finding 10.
 *
 * Both the name and the full selector shape are compared: a declaration whose
 * argument labels drifted from the Swift implementation is the same crash.
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const mPath = path.join(root, 'ios', 'RnVietmapTrackingPluginModule.m');
const swiftPath = path.join(root, 'ios', 'RnVietmapTrackingPlugin.swift');

const m = fs.readFileSync(mPath, 'utf8');
const swift = fs.readFileSync(swiftPath, 'utf8');

/** Declared selectors, keyed by first segment. Commented-out lines are skipped. */
function declaredSelectors(source) {
  const result = new Map();
  const re = /^RCT_EXTERN_METHOD\(([\s\S]*?)\)\s*$/gm;
  let match;
  while ((match = re.exec(source)) !== null) {
    const labels = [...match[1].matchAll(/(\w+):/g)].map((m2) => m2[1]);
    if (labels.length > 0) {
      result.set(labels[0], labels.join(':') + ':');
    }
  }
  return result;
}

/** Implemented selectors: @objc(sel:with:) and a bare @objc above a func. */
function implementedSelectors(source) {
  const explicit = new Map();
  for (const match of source.matchAll(/@objc\(([\w:]+)\)/g)) {
    const selector = match[1];
    explicit.set(selector.split(':')[0], selector.includes(':') ? selector : null);
  }
  const bare = new Set();
  for (const match of source.matchAll(/@objc\s*(?:\n\s*)?func\s+(\w+)\s*\(/g)) {
    bare.add(match[1]);
  }
  return { explicit, bare };
}

/**
 * Methods the Swift class overrides must not be redefined in an Objective-C
 * category on the same class. A category method replaces the class's own
 * implementation and which one wins is not defined by the language, so the
 * definition has two homes and editing one of them can silently do nothing.
 *
 * This shipped once: `supportedEvents` lived in both, and a new event added to
 * the Swift list never reached the bridge.
 */
function duplicateOverrides(objc, swiftSource) {
  const guarded = ['supportedEvents', 'requiresMainQueueSetup', 'constantsToExport', 'moduleName'];
  const found = [];
  for (const name of guarded) {
    const inCategory = new RegExp(`^[+-]\\s*\\([^)]*\\)\\s*${name}\\b`, 'm').test(objc);
    const inSwift = new RegExp(`override\\s+(?:static\\s+)?func\\s+${name}\\b`).test(swiftSource);
    if (inCategory && inSwift) found.push(name);
  }
  return found;
}

const declared = declaredSelectors(m);
const { explicit, bare } = implementedSelectors(swift);
const duplicated = duplicateOverrides(m, swift);

const missing = [];
const mismatched = [];

for (const [name, shape] of declared) {
  if (!explicit.has(name) && !bare.has(name)) {
    missing.push(name);
    continue;
  }
  const implShape = explicit.get(name);
  // A bare @objc lets the compiler derive the selector, which cannot be
  // compared textually — only an explicit @objc(...) is checked for shape.
  if (implShape && implShape !== shape) {
    mismatched.push({ name, declared: shape, implemented: implShape });
  }
}

if (missing.length === 0 && mismatched.length === 0 && duplicated.length === 0) {
  console.log(`iOS parity OK — ${declared.size} selectors declared, all implemented.`);
  process.exit(0);
}

console.error('iOS parity check FAILED.\n');
if (missing.length > 0) {
  console.error('Declared in the .m with no Swift implementation:');
  for (const name of missing) console.error(`  - ${name}`);
  console.error('\nEach of these crashes at call time with "unrecognized selector".\n');
}
if (duplicated.length > 0) {
  console.error('Defined in BOTH the Swift class and an Objective-C category:');
  for (const name of duplicated) console.error(`  - ${name}`);
  console.error(
    '\nA category method replaces the class implementation, and which wins is\n' +
    'undefined. Keep one definition — the Swift override — and delete the other.\n'
  );
}
if (mismatched.length > 0) {
  console.error('Selector shape differs between the .m and the Swift:');
  for (const item of mismatched) {
    console.error(`  - ${item.name}`);
    console.error(`      .m:    ${item.declared}`);
    console.error(`      swift: ${item.implemented}`);
  }
  console.error('');
}
process.exit(1);
