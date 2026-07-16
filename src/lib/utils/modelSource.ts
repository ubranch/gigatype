import type { ModelSource } from "@/bindings";

export const isLegacyModelSource = (source: ModelSource): boolean =>
  typeof source === "object" && "Url" in source;
