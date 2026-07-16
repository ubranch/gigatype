import { afterEach, describe, expect, test } from "bun:test";
import { GlobalRegistrator } from "@happy-dom/global-registrator";
import i18next from "i18next";
import React, { useState } from "react";
import { I18nextProvider } from "react-i18next";
import { Dropdown } from "../src/components/ui/Dropdown";

if (!GlobalRegistrator.isRegistered) GlobalRegistrator.register();

const { cleanup, render, within } = await import("@testing-library/react");
const userEvent = (await import("@testing-library/user-event")).default;

const i18n = i18next.createInstance();
await i18n.init({ lng: "en", resources: { en: { translation: {} } } });

const options = [
  { value: "auto", label: "Auto", disabled: true },
  { value: "cpu", label: "CPU" },
  { value: "cuda", label: "CUDA" },
  { value: "directml", label: "DirectML", disabled: true },
  { value: "tensorrt", label: "TensorRT" },
];

afterEach(() => cleanup());

function renderDropdown(
  props: Partial<React.ComponentProps<typeof Dropdown>> = {},
) {
  return render(
    <I18nextProvider i18n={i18n}>
      <Dropdown
        ariaLabel="ONNX Acceleration"
        options={options}
        selectedValue={null}
        onSelect={() => undefined}
        {...props}
      />
    </I18nextProvider>,
  );
}

describe("dropdown accessibility", () => {
  test("exposes its setting name and popup state", () => {
    const view = renderDropdown({ selectedValue: "cuda" });
    const trigger = view.getByRole("button", {
      name: "ONNX Acceleration",
    });

    expect(trigger.getAttribute("aria-expanded")).toBe("false");
    expect(trigger.getAttribute("aria-haspopup")).toBe("listbox");
    expect(trigger.getAttribute("aria-controls")).not.toBeNull();
    expect(view.queryByRole("listbox")).toBeNull();
  });

  test("opening focuses the selected enabled option", async () => {
    const user = userEvent.setup();
    const view = renderDropdown({ selectedValue: "cuda" });
    const trigger = view.getByRole("button", {
      name: "ONNX Acceleration",
    });

    await user.click(trigger);

    const listbox = view.getByRole("listbox", {
      name: "ONNX Acceleration",
    });
    expect(document.activeElement).toBe(
      within(listbox).getByRole("option", { name: "CUDA" }),
    );
  });

  test("opening falls back to the first enabled option", async () => {
    const user = userEvent.setup();
    const view = renderDropdown();

    await user.click(view.getByRole("button", { name: "ONNX Acceleration" }));

    const listbox = view.getByRole("listbox");
    const disabledOption = within(listbox).getByRole("option", {
      name: "Auto",
    }) as HTMLButtonElement;
    expect(disabledOption.disabled).toBe(true);
    expect(document.activeElement).toBe(
      within(listbox).getByRole("option", { name: "CPU" }),
    );
  });

  test("Arrow, Home, and End keys move focus among enabled options", async () => {
    const user = userEvent.setup();
    const view = renderDropdown({ selectedValue: "cpu" });

    await user.click(view.getByRole("button", { name: "ONNX Acceleration" }));
    const listbox = view.getByRole("listbox");
    const cpu = within(listbox).getByRole("option", { name: "CPU" });
    const cuda = within(listbox).getByRole("option", { name: "CUDA" });
    const tensorrt = within(listbox).getByRole("option", {
      name: "TensorRT",
    });

    expect(document.activeElement).toBe(cpu);
    await user.keyboard("{ArrowDown}");
    expect(document.activeElement).toBe(cuda);
    await user.keyboard("{ArrowDown}");
    expect(document.activeElement).toBe(tensorrt);
    await user.keyboard("{ArrowDown}");
    expect(document.activeElement).toBe(cpu);
    await user.keyboard("{ArrowUp}");
    expect(document.activeElement).toBe(tensorrt);
    await user.keyboard("{Home}");
    expect(document.activeElement).toBe(cpu);
    await user.keyboard("{End}");
    expect(document.activeElement).toBe(tensorrt);
  });

  test("Escape closes the listbox and restores trigger focus", async () => {
    const user = userEvent.setup();
    const view = renderDropdown({ selectedValue: "cuda" });
    const trigger = view.getByRole("button", {
      name: "ONNX Acceleration",
    });

    await user.click(trigger);
    await user.keyboard("{Escape}");

    expect(view.queryByRole("listbox")).toBeNull();
    expect(trigger.getAttribute("aria-expanded")).toBe("false");
    expect(document.activeElement).toBe(trigger);
  });

  test("Enter and Space keep native option selection behavior", async () => {
    const user = userEvent.setup();
    const selections: string[] = [];

    const StatefulDropdown = () => {
      const [selectedValue, setSelectedValue] = useState<string | null>(null);
      return (
        <I18nextProvider i18n={i18n}>
          <Dropdown
            ariaLabel="ONNX Acceleration"
            options={options}
            selectedValue={selectedValue}
            onSelect={(value) => {
              selections.push(value);
              setSelectedValue(value);
            }}
          />
        </I18nextProvider>
      );
    };

    const view = render(<StatefulDropdown />);
    const trigger = view.getByRole("button", {
      name: "ONNX Acceleration",
    });

    await user.click(trigger);
    await user.keyboard("{Enter}");
    expect(selections).toEqual(["cpu"]);
    expect(view.queryByRole("listbox")).toBeNull();
    expect(document.activeElement).toBe(trigger);

    await user.click(trigger);
    await user.keyboard("{ArrowDown}");
    await user.keyboard(" ");
    expect(selections).toEqual(["cpu", "cuda"]);
    expect(view.queryByRole("listbox")).toBeNull();
    expect(document.activeElement).toBe(trigger);
  });

  test("a disabled dropdown cannot open", async () => {
    const user = userEvent.setup();
    const view = renderDropdown({ disabled: true });
    const trigger = view.getByRole("button", {
      name: "ONNX Acceleration",
    }) as HTMLButtonElement;

    expect(trigger.disabled).toBe(true);
    await user.click(trigger);
    expect(view.queryByRole("listbox")).toBeNull();
  });
});
