// @vitest-environment-options {"url":"https://www.mydailywhisper.com/"}
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
const { open, from } = vi.hoisted(() => ({ open: vi.fn(() => true), from: vi.fn() }));
vi.mock("@/pages/MeetingRoom", () => ({ default: () => null }));
vi.mock("@/components/MeetingSaveBanner", () => ({ MeetingSaveBanner: () => null }));
vi.mock("@/hooks/useAuth", () => ({ useAuth: () => ({ user: null }) }));
vi.mock("@/hooks/useMeetingHost", () => ({ useMeetingHost: () => ({ active: null, recordingStatus: null, open }) }));
vi.mock("@/lib/supabase", () => ({ supabase: { from } }));
import { MeetRouteBinder } from "./MeetingHostSurface";
afterEach(() => { cleanup(); vi.clearAllMocks(); sessionStorage.clear(); });

describe("legacy invitation route handoff", () => {
  it.each(["ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456", "wsp-Ab12-Cd34"])("hands signed-out legacy %s to Meet without mounting a room or writing data", async (identity) => {
    const external = vi.fn();
    render(<QueryClientProvider client={new QueryClient()}><MemoryRouter initialEntries={[`/meet/${identity}?access_token=discard&autoJoin=1`]}><Routes><Route path="/meet/:id" element={<MeetRouteBinder openExternal={external} />} /></Routes></MemoryRouter></QueryClientProvider>);
    await waitFor(() => expect(external).toHaveBeenCalledWith(`https://meet.mydailywhisper.com/meet/${identity}`));
    expect(open).not.toHaveBeenCalled(); expect(from).not.toHaveBeenCalled();
  });
  it.each(["sd=1", "call=alex&mode=audio", "groupCall=1"])("leaves %s in social Whisper", async (query) => {
    const external = vi.fn();
    render(<QueryClientProvider client={new QueryClient()}><MemoryRouter initialEntries={[`/meet/wsp-Ab12-Cd34?${query}`]}><Routes><Route path="/meet/:id" element={<MeetRouteBinder openExternal={external} />} /></Routes></MemoryRouter></QueryClientProvider>);
    await waitFor(() => expect(open).toHaveBeenCalled());
    expect(open).toHaveBeenCalledWith("wsp-Ab12-Cd34", query.startsWith("call=") ? "alex" : null, query.startsWith("call=") ? "audio" : null);
    expect(external).not.toHaveBeenCalled(); expect(from).not.toHaveBeenCalled();
  });
});
