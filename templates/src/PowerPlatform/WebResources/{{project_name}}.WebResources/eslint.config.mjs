import js from '@eslint/js';

export default [
  js.configs.recommended,
  {
    ignores: ['coverage/**', 'bin/**', 'obj/**']
  },
  {
    // Deployed web resources: plain ES2020 scripts, loaded by the form, with no module syntax.
    languageOptions: {
      ecmaVersion: 2020,
      sourceType: 'script',
      globals: {
        Xrm: 'readonly'
      }
    }
  },
  {
    // Tests and tooling configuration are not deployed: they may use ES modules.
    files: ['**/*.test.js', '**/*.mjs'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        URL: 'readonly'
      }
    }
  }
];
