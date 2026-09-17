import { ESLint } from 'eslint';
import { describe, expect, it } from 'vitest';

describe('geometry purity guard', () => {
  it.each([
    ["fetch('https://example.test');", 'no-restricted-globals'],
    ["globalThis.fetch('https://example.test');", 'no-restricted-properties'],
    ["window.fetch('https://example.test');", 'no-restricted-properties'],
    ["import fs from 'fs'; void fs;", 'no-restricted-imports'],
    ["import fs from 'node:fs/promises'; void fs;", 'no-restricted-imports'],
    ["import location from 'expo-location'; void location;", 'no-restricted-imports'],
    ["import device from 'react-native'; void device;", 'no-restricted-imports'],
    ["import camera from 'react-native-vision-camera'; void camera;", 'no-restricted-imports'],
    ["import ar from '@reactvision/react-viro'; void ar;", 'no-restricted-imports'],
    ["import native from '@shopify/react-native-skia'; void native;", 'no-restricted-imports'],
    ["import('node:fs');", 'no-restricted-syntax'],
    ["require('fs');", 'no-restricted-syntax'],
  ])('rejects impure source: %s', async (source, rule) => {
    const results = await new ESLint().lintText(source, { filePath: 'src/purity-probe.ts' });
    expect(results[0].messages.some((message) => message.ruleId === rule)).toBe(true);
  });

  it('permits pure geometry imports', async () => {
    const results = await new ESLint().lintText("import { area } from '@turf/area'; void area;", {
      filePath: 'src/purity-probe.ts',
    });
    expect(results[0].errorCount).toBe(0);
  });
});
