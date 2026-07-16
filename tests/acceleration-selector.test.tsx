import { afterEach, describe, expect, test } from "bun:test";
import { GlobalRegistrator } from "@happy-dom/global-registrator";
import i18next from "i18next";
import { I18nextProvider } from "react-i18next";
import { commands, type AppSettings } from "../src/bindings";
import { AccelerationSelector } from "../src/components/settings/AccelerationSelector";
import { useSettingsStore } from "../src/stores/settingsStore";

if (!GlobalRegistrator.isRegistered) GlobalRegistrator.register();

const { cleanup, render, waitFor, within } = await import(
  "@testing-library/react"
);
const userEvent = (await import("@testing-library/user-event")).default;

const i18n = i18next.createInstance();
await i18n.init({
  lng: "en",
  resources: {
    en: {
      translation: {
        settings: {
          advanced: {
            acceleration: {
              transcribe: {
                title: "transcribe.cpp Acceleration",
                description: "transcribe description",
              },
              ort: {
                title: "ONNX Acceleration",
                description: "ONNX description",
                unavailable: "{{accelerator}} is unavailable: {{reason}}",
              },
              gpuDevice: { auto: "Auto" },
            },
          },
        },
      },
    },
  },
});

const originalGetAvailableAccelerators = commands.getAvailableAccelerators;
const originalChangeOrtAcceleratorSetting =
  commands.changeOrtAcceleratorSetting;

afterEach(() => {
  cleanup();
  commands.getAvailableAccelerators = originalGetAvailableAccelerators;
  commands.changeOrtAcceleratorSetting = originalChangeOrtAcceleratorSetting;
  useSettingsStore.getState().setSettings(null);
  useSettingsStore.getState().setLoading(true);
});

describe("AccelerationSelector", () => {
  test("preserves a persisted unavailable CUDA choice with its diagnostic", async () => {
    const updateCalls: string[] = [];
    const reason = "missing app-local component cublas64_13.dll";

    useSettingsStore.getState().setSettings({
      transcribe_accelerator: "auto",
      transcribe_gpu_device: -1,
      ort_accelerator: "cuda",
    } as AppSettings);
    useSettingsStore.getState().setLoading(false);

    commands.getAvailableAccelerators = async () => ({
      transcribe: ["auto", "cpu"],
      gpu_devices: [],
      ort: [
        { id: "auto", compiled: true, usable: true, reason: null },
        { id: "cpu", compiled: true, usable: true, reason: null },
        { id: "cuda", compiled: true, usable: false, reason },
      ],
      ort_requested: "cuda",
      ort_selected: "cpu",
      ort_fallback_reason: null,
    });
    commands.changeOrtAcceleratorSetting = async (accelerator) => {
      updateCalls.push(accelerator);
      return { status: "ok", data: null };
    };

    const view = render(
      <I18nextProvider i18n={i18n}>
        <AccelerationSelector descriptionMode="inline" />
      </I18nextProvider>,
    );

    const trigger = await waitFor(() =>
      view.getByRole("button", { name: "ONNX Acceleration" }),
    );
    expect(trigger.textContent).toContain("CUDA");
    expect(trigger.textContent).not.toContain("Auto");

    const diagnostic = view.getByRole("status");
    expect(diagnostic.textContent).toBe(`CUDA is unavailable: ${reason}`);
    expect(trigger.getAttribute("aria-describedby")).toBe(diagnostic.id);

    const user = userEvent.setup();
    await user.click(trigger);
    const listbox = view.getByRole("listbox", { name: "ONNX Acceleration" });
    const cuda = within(listbox).getByRole("option", {
      name: "CUDA",
    }) as HTMLButtonElement;
    expect(cuda.disabled).toBe(true);
    expect(within(listbox).getByRole("option", { name: "Auto" })).not.toBe(
      null,
    );
    expect(within(listbox).getByRole("option", { name: "CPU" })).not.toBe(null);
    expect(updateCalls).toEqual([]);
    expect(useSettingsStore.getState().settings?.ort_accelerator).toBe("cuda");
  });
});
