import { describe, expect, test } from "bun:test";
import type { ModelSource } from "../src/bindings";
import { isLegacyModelSource } from "../src/lib/utils/modelSource";

describe("legacy model source classification", () => {
  test("only Url is legacy", () => {
    const sources: Array<[ModelSource, boolean]> = [
      [{ Url: { url: "https://example.test/model", sha256: null } }, true],
      [{ HuggingFace: { repo_id: "owner/repo", revision: "main" } }, false],
      [
        {
          HuggingFaceBundle: {
            repo_id: "owner/repo",
            revision: "0123456789012345678901234567890123456789",
            files: [],
          },
        },
        false,
      ],
      ["Local", false],
    ];

    for (const [source, expected] of sources) {
      expect(isLegacyModelSource(source)).toBe(expected);
    }
  });
});
