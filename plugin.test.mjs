import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, it } from 'node:test';

describe('plugin.xml', () => {
  it("should carry package.json's version", () => {
    const { version } = JSON.parse(
      readFileSync(join(import.meta.dirname, 'package.json'), 'utf8'),
    );
    const [, pluginVersion] = /<plugin\b[^>]*\sversion="([^"]*)"/.exec(
      readFileSync(join(import.meta.dirname, 'plugin.xml'), 'utf8'),
    );

    assert.equal(pluginVersion, version);
  });
});
