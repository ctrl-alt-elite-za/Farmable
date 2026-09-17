import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import eslintConfigPrettier from 'eslint-config-prettier';

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommended,
  eslintConfigPrettier,
  {
    ignores: [
      '**/dist/**',
      '**/build/**',
      '**/.expo/**',
      '**/.venv/**',
      '**/coverage/**',
      '.uv-cache/**',
      '.pytest_cache/**',
      '.mypy_cache/**',
      '.ruff_cache/**',
      'apps/ml-service/data/**',
      'packages/api-client/**',
      'apps/mobile/android/**',
      'apps/mobile/ios/**',
    ],
  },
  {
    // Babel and Jest load these two files with require(), so they use CommonJS
    // globals that an ESM-by-default flat config does not assume.
    files: ['apps/mobile/babel.config.js', 'apps/mobile/jest.config.js'],
    languageOptions: {
      sourceType: 'commonjs',
      globals: { module: 'writable', require: 'readonly' },
    },
  },
  {
    // Expo loads this config plugin through Node's CommonJS loader.
    files: ['apps/mobile/with-viro-monorepo.js'],
    languageOptions: {
      sourceType: 'commonjs',
      globals: { process: 'readonly' },
    },
    rules: { '@typescript-eslint/no-require-imports': 'off' },
  },
  {
    files: ['apps/mobile/jest.setup.js'],
    languageOptions: { globals: { process: 'readonly' } },
  },
  {
    files: ['packages/geo/**/*.ts'],
    rules: {
      'no-restricted-syntax': [
        'error',
        {
          selector: 'ImportExpression',
          message: 'Geometry uses only statically checked pure imports.',
        },
        {
          selector: "CallExpression[callee.name='require']",
          message: 'Geometry uses only statically checked pure imports.',
        },
      ],
      'no-restricted-globals': ['error', { name: 'fetch', message: 'Geometry must be pure.' }],
      'no-restricted-properties': [
        'error',
        { object: 'globalThis', property: 'fetch', message: 'Geometry must be pure.' },
        { object: 'window', property: 'fetch', message: 'Geometry must be pure.' },
      ],
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: [
                'node:*',
                'fs',
                'fs/*',
                'fs-extra',
                'fs-extra/*',
                'react-native',
                'react-native-*',
                'react-native-*/**',
                'expo',
                'expo-*',
                'expo-*/**',
                '@expo/*',
                '@react-native/*',
                '@reactvision/*',
                '@shopify/react-native-*',
                '@nativescript/*',
                '@capacitor/*',
              ],
              message: 'Geometry cannot access filesystem or device APIs.',
            },
          ],
        },
      ],
    },
  },
);
