'use strict';

const js = require('@eslint/js');
const globals = require('globals');
const lwcConfig = require('@salesforce/eslint-config-lwc');

module.exports = [
    {
        ignores: [
            'node_modules/**',
            'coverage/**',
            '.sfdx/**',
            '.sf/**',
            '.localdevserver/**'
        ]
    },
    {
        files: ['jest.config.js'],
        languageOptions: {
            ecmaVersion: 2021,
            sourceType: 'commonjs',
            globals: {
                ...globals.node
            }
        },
        rules: {
            ...js.configs.recommended.rules
        }
    },
    ...lwcConfig.configs.recommended.map((config) => ({
        ...config,
        files: ['force-app/main/default/lwc/**/*.js']
    })),
    {
        files: ['force-app/main/default/lwc/**/__tests__/**/*.js'],
        rules: {
            '@lwc/lwc/no-async-operation': 'off'
        }
    }
];
