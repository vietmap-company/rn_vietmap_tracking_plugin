import js from '@eslint/js';
import tseslint from '@typescript-eslint/eslint-plugin';
import tsparser from '@typescript-eslint/parser';

export default [
  js.configs.recommended,
  {
    files: ['**/*.{js,ts,tsx}'],
    plugins: {
      '@typescript-eslint': tseslint,
    },
    languageOptions: {
      parser: tsparser,
      ecmaVersion: 'latest',
      sourceType: 'module',
      parserOptions: {
        ecmaFeatures: {
          jsx: true,
        },
      },
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
        React: 'readonly',
        JSX: 'readonly',
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

      // TypeScript specific rules
      '@typescript-eslint/no-unused-vars': 'warn',
      '@typescript-eslint/no-explicit-any': 'warn',
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
