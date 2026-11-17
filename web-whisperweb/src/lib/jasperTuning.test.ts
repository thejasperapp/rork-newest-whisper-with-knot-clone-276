import { beforeEach, describe, expect, it } from "vitest";
import { defaultJasperTuning, jasperTuningBlock, loadJasperTuning, saveJasperTuning } from "./jasperTuning";

describe("personal Jasper tuning", () => {
  beforeEach(() => localStorage.clear());
  it("keeps accounts separate and supports a zero-strength pause", () => {
    saveJasperTuning("a", { version: 1, more: ["Short answers"], less: [], strength: 0.8 });
    expect(jasperTuningBlock("a")).toContain("Short answers");
    expect(loadJasperTuning("b")).toEqual(defaultJasperTuning);
    saveJasperTuning("a", { version: 1, more: ["Short answers"], less: [], strength: 0 });
    expect(jasperTuningBlock("a")).toBe("");
  });
  it("rejects excessive inputs and corrupt stored data", () => {
    expect(() => saveJasperTuning("a", { version: 1, more: ["a".repeat(81)], less: [], strength: 1 })).toThrow();
    expect(() => saveJasperTuning("a", { version: 1, more: Array(9).fill("one"), less: [], strength: 1 })).toThrow();
    localStorage.setItem("whisper-jasper-tuning-v1:a", "garbage");
    expect(loadJasperTuning("a")).toEqual(defaultJasperTuning);
  });
});
