import { act, cleanup, renderHook, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({ dashboard: vi.fn(), generation: 0 }));
vi.mock("@/lib/jasperCoachConnect", () => ({ coachDashboard: mocks.dashboard }));
vi.mock("@/hooks/useJasperGeneration", () => ({ useJasperGeneration: () => mocks.generation }));
import { useCoachPreviews } from "./useCoachPreviews";
afterEach(() => { cleanup(); vi.resetAllMocks(); mocks.generation = 0; });
describe("bounded owner-scoped coach previews", () => {
  it("schedules no more than four reads at once and stops queued work on exit", async () => {
    const finish: Array<(value: unknown) => void> = [];
    mocks.dashboard.mockImplementation(() => new Promise(resolve => finish.push(resolve)));
    const hook = renderHook(({ active }) => useCoachPreviews("A", ["1", "2", "3", "4", "5", "6"], active), { initialProps: { active: true } });
    await waitFor(() => expect(mocks.dashboard).toHaveBeenCalledTimes(4));
    await act(async () => finish[0]({ fetchedAt: 1 }));
    await waitFor(() => expect(mocks.dashboard).toHaveBeenCalledTimes(5));
    expect(hook.result.current["1"]).toEqual({ fetchedAt: 1 });
    hook.rerender({ active: false });
    await act(async () => finish.slice(1).forEach(resolve => resolve({ fetchedAt: 2 })));
    expect(mocks.dashboard).toHaveBeenCalledTimes(5);
    expect(hook.result.current["2"]).toBeUndefined();
  });
  it("immediately hides outgoing owner/generation rows and ignores late completions", async () => {
    const finish: Array<(value: unknown) => void> = [];
    mocks.dashboard.mockImplementation(() => new Promise(resolve => finish.push(resolve)));
    const hook = renderHook(({ owner }) => useCoachPreviews(owner, ["client"], true), { initialProps: { owner: "A" } });
    await waitFor(() => expect(finish).toHaveLength(1));
    hook.rerender({ owner: "B" });
    expect(hook.result.current).toEqual({});
    await waitFor(() => expect(finish).toHaveLength(2));
    await act(async () => finish[0]({ fetchedAt: 1 }));
    expect(hook.result.current).toEqual({});
    await act(async () => finish[1]({ fetchedAt: 2 }));
    expect(hook.result.current.client).toEqual({ fetchedAt: 2 });
    mocks.generation++;
    hook.rerender({ owner: "B" });
    expect(hook.result.current).toEqual({});
  });
});
