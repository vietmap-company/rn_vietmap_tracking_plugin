import js from '@eslint/js';

export default [
  js.configs.recommended,
  {
    files: ['**/*.{js,ts,tsx}'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        console: 'readonly',
        process: 'readonly',
        Buffer: 'readonly',
        __dirname: 'readonly',
        __filename: 'readonly',
        module: 'readonly',
        require: 'readonly',
        exports: 'readonly',
        global: 'readonly',
      },
    },
    rules: {
      // Disable some rules that might conflict with TypeScript
      'no-unused-vars': 'off',
      'no-undef': 'off',
      'no-console': 'off',

      // Basic code quality rules
      'no-debugger': 'error',
      'no-alert': 'warn',
      'prefer-const': 'warn',
    },
  },
  {
    ignores: [
      'node_modules/',
      'lib/',
      'android/',
      'ios/',
      'example/android/',
      'example/ios/',
      '*.config.js',
      '*.config.mjs',
      'babel.config.js',
      'metro.config.js',
    ],
  },
];
