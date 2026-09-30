#!/usr/bin/env node
/**
 * Fail when the codegen script phase in Pods.xcodeproj carries a broken path.
 *
 * React Native bakes the path to react-native into that script phase relative
 * to the working directory `pod install` ran from
 * (codegen_utils.rb: `installation_root.relative_path_from(Pathname.pwd)`).
 * Run from anywhere but `example/ios`, it produces a chain of `..` that climbs
 * past the filesystem root, and the next clean build dies with
 * "with-environment.sh: No such file or directory".
 *
 * A local build does not catch this: a warm DerivedData keeps a cached, correct
 * copy of the script and Xcode skips the phase as up to date. Only a fresh
 * DerivedData — which is what a colleague or CI has — hits it. So this checks
 * the project file itself. See UPGRADE_PLAN.md finding 14.
 */
const fs = require('fs');
const path = require('path');

const project = path.join(
  __dirname, '..', 'example', 'ios', 'Pods', 'Pods.xcodeproj', 'project.pbxproj'
);

if (!fs.existsSync(project)) {
  console.log('Pods project not found — skipping codegen path check (run pod install first).');
  process.exit(0);
}

const contents = fs.readFileSync(project, 'utf8');
const match = /RCT_SCRIPT_RN_DIR=\\"\$RCT_SCRIPT_POD_INSTALLATION_ROOT((?:\/\.\.)*)\/node_modules\/react-native/.exec(contents);

if (!match) {
  console.log('Codegen script phase not found — skipping (new architecture may be off).');
  process.exit(0);
}

const levels = (match[1].match(/\/\.\./g) || []).length;
if (levels === 1) {
  console.log('Pods codegen path OK — react-native resolved one level up, as expected.');
  process.exit(0);
}

console.error('Pods codegen path is BROKEN.\n');
console.error(`  Expected 1 level of "..", found ${levels}.`);
console.error(`  The script would look for react-native at:`);
console.error(`    example/ios${match[1]}/node_modules/react-native\n`);
console.error('  Fix by reinstalling pods from the right directory:\n');
console.error('    cd example/ios && bundle exec pod install\n');
console.error('  A local build may still pass on a warm DerivedData; a clean one will not.');
process.exit(1);
