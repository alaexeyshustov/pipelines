import tseslint from 'typescript-eslint';
import prettier from 'eslint-config-prettier';

export default tseslint.config(
  { ignores: ['app/assets/**'] },
  {
    files: ['app/javascript/**/*.ts'],
    languageOptions: {
      parserOptions: {
        project: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  tseslint.configs.recommended,
  prettier,
  {
    rules: {
      // Core best practices
      eqeqeq: ['error', 'always'],
      'no-console': 'warn',
      'no-alert': 'error',

      // Override recommended: ignore args/vars prefixed with _ (Stimulus pattern)
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      // Enforce `import type` for type-only imports
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { prefer: 'type-imports', fixStyle: 'inline-type-imports' },
      ],
      // Type-checked: prefer ?. over &&-based null guards
      '@typescript-eslint/prefer-optional-chain': 'error',
      // Type-checked: prefer ?? over || for nullish coalescing
      '@typescript-eslint/prefer-nullish-coalescing': 'error',
    },
  },
);
