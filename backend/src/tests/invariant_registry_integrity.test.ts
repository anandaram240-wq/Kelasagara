// backend/src/tests/invariant_registry_integrity.test.ts
import assert from "assert";
import fs from "fs";
import path from "path";
import { describe, it } from "node:test";

describe("TICKET E-01: INVARIANT REGISTRY INTEGRITY & COLLISION AUDIT", () => {
  const invariantsFilePath = path.resolve(__dirname, "../../../INVARIANTS.md");

  it("should successfully locate and parse INVARIANTS.md", () => {
    assert.ok(fs.existsSync(invariantsFilePath), "INVARIANTS.md must exist in repo root");
  });

  it("should verify zero ID collisions and strict sequential integrity (I-01 through I-31)", () => {
    const content = fs.readFileSync(invariantsFilePath, "utf-8");
    const idRegex = /\|\s*\*\*I-(\d{2})\*\*\s*\|\s*\*\*([^*]+)\*\*\s*\|/g;

    const matches: { id: string; num: number; name: string }[] = [];
    let match;
    while ((match = idRegex.exec(content)) !== null) {
      const num = parseInt(match[1], 10);
      matches.push({
        id: `I-${match[1]}`,
        num,
        name: match[2].trim(),
      });
    }

    assert.ok(matches.length >= 31, `Expected at least 31 registered invariants, found ${matches.length}`);

    // Check uniqueness
    const seen = new Set<string>();
    for (const item of matches) {
      assert.strictEqual(seen.has(item.id), false, `Collision detected for Invariant ID: ${item.id}`);
      seen.add(item.id);
    }

    // Check sequential order (1..31)
    for (let i = 0; i < matches.length; i++) {
      const expectedNum = i + 1;
      assert.strictEqual(
        matches[i].num,
        expectedNum,
        `Sequence break: expected I-${expectedNum.toString().padStart(2, "0")}, got ${matches[i].id}`
      );
    }
  });

  it("should ensure all invariant references in backend source code map to registered invariants", () => {
    const content = fs.readFileSync(invariantsFilePath, "utf-8");
    const validIds = new Set<string>();
    const idRegex = /\|\s*\*\*I-(\d{2})\*\*\s*\|/g;
    let m;
    while ((m = idRegex.exec(content)) !== null) {
      validIds.add(`I-${m[1]}`);
    }

    const servicesDir = path.resolve(__dirname, "../services");
    const files = fs.readdirSync(servicesDir).filter((f) => f.endsWith(".ts"));

    const refRegex = /Invariant\s+(I-\d{2})/g;
    const referencedInCode = new Set<string>();

    for (const file of files) {
      const src = fs.readFileSync(path.join(servicesDir, file), "utf-8");
      let codeMatch;
      while ((codeMatch = refRegex.exec(src)) !== null) {
        referencedInCode.add(codeMatch[1]);
      }
    }

    for (const ref of referencedInCode) {
      assert.ok(
        validIds.has(ref),
        `Source code references unregistered Invariant ID: ${ref}`
      );
    }
  });
});
