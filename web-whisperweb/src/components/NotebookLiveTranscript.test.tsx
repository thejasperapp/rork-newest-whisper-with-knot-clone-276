import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { NotebookLiveTranscript } from "./NotebookLiveTranscript";
const state = vi.hoisted(() => ({ owner: "00000000-0000-4000-8000-000000000001", rows: [] as unknown[], count: 0, error: null as unknown, writes: vi.fn() }));
vi.mock("@/lib/supabase", () => ({ supabase: { auth: { getSession: async () => ({ data: { session: { user: { id: state.owner } } } }) }, from: () => { const chain = { select: () => chain, eq: () => chain, order: () => chain, limit: () => chain, abortSignal: async () => ({ data: state.rows, count: state.count, error: state.error }), insert: state.writes }; return chain; } } }));
const meetingId = "00000000-0000-4000-8000-000000000002";
const first = { id: "00000000-0000-4000-8000-000000000003", meeting_id: meetingId, username: "Sam", text: "Ship Friday", spoken_at: "2026-09-12T08:00:00Z" };
const second = { ...first, id: "00000000-0000-4000-8000-000000000004", text: "Unselected speech", spoken_at: "2026-09-12T08:01:00Z" };
beforeEach(() => { state.rows = [second, first]; state.count = 2; state.error = null; state.writes.mockReset(); });
afterEach(cleanup);
function setup() {
  const onChoose = vi.fn(), client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<QueryClientProvider client={client}><NotebookLiveTranscript owner={state.owner} meetingId={meetingId} onChoose={onChoose} /></QueryClientProvider>);
  fireEvent.click(screen.getByText("Live transcript · choose context"));
  return { onChoose, client };
}
describe("live notebook evidence", () => {
  it("chooses only checked saved speech and freezes its time and meeting provenance", async () => {
    const { onChoose, client } = setup();
    fireEvent.click(await screen.findByRole("checkbox", { name: /Ship Friday/ }));
    fireEvent.click(screen.getByRole("button", { name: "Use selected speech" }));
    expect(onChoose).toHaveBeenCalledTimes(1);
    const context = onChoose.mock.calls[0][0]; expect(JSON.stringify(context)).toContain("Ship Friday"); expect(JSON.stringify(context)).not.toContain("Unselected speech");
    expect(context.sources[0].provenance).toContain(meetingId); expect(context.label).toContain(first.spoken_at);
    state.rows = [{ ...second, text: "New incoming speech" }, first];
    await act(async () => { await client.invalidateQueries(); });
    expect(onChoose).toHaveBeenCalledTimes(1); expect(JSON.stringify(context)).not.toContain("New incoming speech"); expect(state.writes).not.toHaveBeenCalled();
  });
  it("never presents a partial window as the entire transcript", async () => {
    state.count = 250; setup(); await screen.findByRole("checkbox", { name: /Ship Friday/ });
    expect(screen.getByRole("button", { name: "Use transcript so far" })).toBeDisabled();
  });
  it("shows a failed read as an error rather than successful empty transcription", async () => {
    state.error = { code: "offline" }; setup(); await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("unavailable"));
    expect(screen.getByRole("button", { name: "Use transcript so far" })).toBeDisabled();
  });
});
