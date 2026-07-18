import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const css = readFileSync("src/overlay/RecordingOverlay.css", "utf8");
const rust = readFileSync("src-tauri/src/overlay.rs", "utf8");

describe("overlay edge geometry", () => {
  test("keeps the card border inside the transparent overlay window", () => {
    expect(css).toMatch(
      /\.ov-stage\s*\{[\s\S]*?box-sizing:\s*border-box;[\s\S]*?padding-block:\s*1px;[\s\S]*?\}/,
    );
  });

  test("preserves the 12px visible Windows taskbar gap", () => {
    expect(rust).toContain("const OVERLAY_EDGE_INSET: f64 = 1.0;");
    expect(rust).toContain("const OVERLAY_VISIBLE_BOTTOM_GAP: f64 = 12.0;");
    expect(rust).toMatch(
      /const OVERLAY_BOTTOM_OFFSET:\s*f64\s*=\s*OVERLAY_VISIBLE_BOTTOM_GAP\s*-\s*OVERLAY_EDGE_INSET;/,
    );
  });
});
