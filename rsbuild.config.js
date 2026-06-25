// @ts-check
import { defineConfig } from '@rsbuild/core';
import { pluginNodePolyfill } from '@rsbuild/plugin-node-polyfill';

// Docs: https://rsbuild.rs/config/
export default defineConfig({
    plugins: [pluginNodePolyfill()],
    source: {
        entry: {
            index: './_www/index.mjs'
        },
    },
    server: {
        publicDir: {
            name: "_www/public"
        },
    }
});
