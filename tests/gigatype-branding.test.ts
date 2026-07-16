import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const read = (path: string) => readFileSync(join(root, path), "utf8");

const readPngHeader = (path: string) => {
  const bytes = readFileSync(join(root, path));

  return {
    signature: bytes.subarray(0, 8).toString("hex"),
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
  };
};

describe("GigaType branding contract", () => {
  test("uses an independent package and bundle identity", () => {
    const tauri = JSON.parse(read("src-tauri/tauri.conf.json"));
    const packageJson = JSON.parse(read("package.json"));
    const cargo = read("src-tauri/Cargo.toml");

    expect(tauri.productName).toBe("GigaType");
    expect(tauri.mainBinaryName).toBe("GigaType");
    expect(tauri.version).toBe("0.9.3-gigatype.1");
    expect(tauri.identifier).toBe("io.github.ubranch.gigatype");
    expect(tauri.bundle.createUpdaterArtifacts).toBe(false);
    expect(tauri.bundle.windows.signCommand).toBeUndefined();
    expect(packageJson.name).toBe("gigatype-app");
    expect(packageJson.version).toBe("0.9.3-gigatype.1");
    expect(cargo).toContain('name = "gigatype"');
    expect(cargo).toContain('name = "gigatype_app_lib"');
  });

  test("uses the renamed library crate in disabled source targets", () => {
    const disabledCli = read("src-tauri/src/audio_toolkit/bin/cli.rs");

    expect(disabledCli).toContain("use gigatype_app_lib::audio_toolkit");
    expect(disabledCli).not.toContain("handy_app_lib");
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

  test("keeps generated Nix dependencies free of the updater", () => {
    expect(read(".nix/bun.nix")).not.toContain("@tauri-apps/plugin-updater");
  });

  test("tracks the current bun.lock hash for Nix dependency generation", () => {
    const bunLockHash = createHash("sha256")
      .update(readFileSync(join(root, "bun.lock")))
      .digest("hex");

    expect(read(".nix/bun-lock-hash").trim()).toBe(bunLockHash);
  });

  test("launches the GigaType executable from Home Manager", () => {
    const homeManagerModule = read("nix/hm-module.nix");

    expect(homeManagerModule).toContain(
      'ExecStart = "${cfg.package}/bin/GigaType";',
    );
  });

  test("declares the GigaType executable as the flake main program", () => {
    const flake = read("flake.nix");

    expect(flake).toContain('mainProgram = "GigaType";');
  });

  test("uses independent user-facing visuals and links", () => {
    const sidebar = read("src/components/Sidebar.tsx");
    const about = read("src/components/settings/about/AboutSettings.tsx");
    const headers = read("src-tauri/src/llm_client.rs");

    expect(
      existsSync(join(root, "src/components/icons/GigaTypeMark.tsx")),
    ).toBe(true);
    expect(
      existsSync(join(root, "src/components/icons/GigaTypeLogo.tsx")),
    ).toBe(true);
    expect(existsSync(join(root, "src/components/icons/HandyHand.tsx"))).toBe(
      false,
    );
    expect(
      existsSync(join(root, "src/components/icons/HandyTextLogo.tsx")),
    ).toBe(false);
    expect(sidebar).toContain("GigaTypeLogo");
    expect(sidebar).toContain("GigaTypeMark");
    expect(about).toContain("https://github.com/ubranch/GigaType");
    expect(about).not.toContain("handy.computer/donate");
    expect(headers).toContain("https://github.com/ubranch/GigaType");
  });

  test("uses generated GigaType sources and rasters for every idle tray theme", () => {
    const tray = read("src-tauri/src/tray.rs");
    const assets = [
      {
        source: "src-tauri/icons/tray/tray_idle.svg",
        raster: "src-tauri/resources/tray_idle.png",
        colors: ["#FFFFFF"],
      },
      {
        source: "src-tauri/icons/tray/tray_idle_dark.svg",
        raster: "src-tauri/resources/tray_idle_dark.png",
        colors: ["#2D1F2A"],
      },
      {
        source: "src-tauri/icons/tray/gigatype.svg",
        raster: "src-tauri/resources/gigatype.png",
        colors: ["#F59AC4", "#B85BE8"],
      },
    ];

    for (const { source, raster, colors } of assets) {
      expect(existsSync(join(root, source))).toBe(true);
      expect(existsSync(join(root, raster))).toBe(true);
      expect(read(source)).toContain('viewBox="0 0 128 128"');
      expect(read(source)).not.toContain("<rect");
      expect(read(source)).toContain("M84 43a32 32 0 1 0 4 42V66H65");
      expect(read(source)).toContain("M43 57v14M53 51v26M63 57v14");
      for (const color of colors) expect(read(source)).toContain(color);
      expect(readPngHeader(raster)).toEqual({
        signature: "89504e470d0a1a0a",
        width: 64,
        height: 64,
      });
    }

    expect(tray).toContain(
      '(AppTheme::Dark, TrayIconState::Idle) => "resources/tray_idle.png"',
    );
    expect(tray).toContain(
      '(AppTheme::Light, TrayIconState::Idle) => "resources/tray_idle_dark.png"',
    );
    expect(tray).toContain(
      '(AppTheme::Colored, TrayIconState::Idle) => "resources/gigatype.png"',
    );
    expect(tray).not.toContain('"resources/handy.png"');
    expect(existsSync(join(root, "src-tauri/resources/handy.png"))).toBe(false);
  });

  test("uses the exact public application title", () => {
    const html = read("index.html");

    expect(html.match(/<title>.*?<\/title>/g)).toEqual([
      "<title>GigaType</title>",
    ]);
  });

  test("keeps sidebar icons decorative and constrains the centered logo", () => {
    const sidebar = read("src/components/Sidebar.tsx");
    const logo = read("src/components/icons/GigaTypeLogo.tsx");

    expect(sidebar).toMatch(/<Icon[\s\S]*?aria-hidden="true"[\s\S]*?\/>/);
    expect(logo).toContain("justify-center");
    expect(logo).toContain("max-w-full");
    expect(logo).toContain("min-w-0");
    expect(logo).toContain("shrink-0");
    expect(logo).toContain("width={24}");
    expect(logo).toContain("height={24}");
    expect(logo).not.toContain('width="28%"');
  });
});
