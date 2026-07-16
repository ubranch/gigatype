import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const read = (path: string) => readFileSync(join(root, path), "utf8");

describe("GigaType branding contract", () => {
  test("uses an independent package and bundle identity", () => {
    const tauri = JSON.parse(read("src-tauri/tauri.conf.json"));
    const packageJson = JSON.parse(read("package.json"));
    const cargo = read("src-tauri/Cargo.toml");

    expect(tauri.productName).toBe("GigaType");
    expect(tauri.version).toBe("0.9.3-gigatype.1");
    expect(tauri.identifier).toBe("io.github.ubranch.gigatype");
    expect(tauri.bundle.createUpdaterArtifacts).toBe(false);
    expect(tauri.bundle.windows.signCommand).toBeUndefined();
    expect(packageJson.name).toBe("gigatype-app");
    expect(packageJson.version).toBe("0.9.3-gigatype.1");
    expect(cargo).toContain('name = "gigatype"');
    expect(cargo).toContain('name = "gigatype_app_lib"');
  });

  test("contains no upstream updater integration", () => {
    const packageJson = read("package.json");
    const cargo = read("src-tauri/Cargo.toml");
    const backend = read("src-tauri/src/lib.rs");
    const defaultCapability = read("src-tauri/capabilities/default.json");
    const desktopCapability = read("src-tauri/capabilities/desktop.json");

    expect(packageJson).not.toContain("@tauri-apps/plugin-updater");
    expect(cargo).not.toContain("tauri-plugin-updater");
    expect(backend).not.toContain("tauri_plugin_updater");
    expect(backend).not.toContain("trigger_update_check");
    expect(defaultCapability).not.toContain("updater:");
    expect(desktopCapability).not.toContain("updater:");
    expect(existsSync(join(root, "src/components/update-checker"))).toBe(false);
  });
});
