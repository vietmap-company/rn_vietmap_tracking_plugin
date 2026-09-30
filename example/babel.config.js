const path = require('path');
const { getConfig } = require('react-native-builder-bob/babel-config');
const pkg = require('../package.json');

const root = path.resolve(__dirname, '..');

module.exports = getConfig(
  {
    presets: [
      [
        'module:@react-native/babel-preset',
        {
          unstable_transformProfile: 'hermes-stable',
        },
      ],
    ],
    plugins: [
      [
        '@babel/plugin-transform-react-jsx',
        {
          // 'classic' required `import React` in every file and made React
          // log "Your app (or one of its dependencies) is using an outdated
          // JSX transform" on startup. 'automatic' matches the root tsconfig's
          // "jsx": "react-jsx".
          runtime: 'automatic',
        },
      ],
    ],
  },
  { root, pkg }
);
