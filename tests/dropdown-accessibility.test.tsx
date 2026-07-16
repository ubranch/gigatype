import { describe, expect, test } from "bun:test";
import i18next from "i18next";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { I18nextProvider } from "react-i18next";
import { Dropdown } from "../src/components/ui/Dropdown";

describe("dropdown accessibility", () => {
  test("exposes its setting name and popup state", async () => {
    const i18n = i18next.createInstance();
    await i18n.init({ lng: "en", resources: { en: { translation: {} } } });

    const markup = renderToStaticMarkup(
      <I18nextProvider i18n={i18n}>
        <Dropdown
          ariaLabel="ONNX Acceleration"
          options={[{ value: "cuda", label: "CUDA" }]}
          selectedValue="cuda"
          onSelect={() => undefined}
        />
      </I18nextProvider>,
    );

    expect(markup).toContain('aria-label="ONNX Acceleration"');
    expect(markup).toContain('aria-expanded="false"');
    expect(markup).toContain('aria-haspopup="listbox"');
    expect(markup).toContain("aria-controls=");
  });
});
