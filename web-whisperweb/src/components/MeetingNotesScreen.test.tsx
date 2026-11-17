import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vitest";
import { MeetingNotesScreen } from "./MeetingNotesScreen";

vi.mock("@/hooks/useAuth", () => ({ useAuth: () => ({ user: { id: "owner" } }) }));
vi.mock("./NotebookRecordingSources", () => ({ NotebookRecordingSources: ({ note }: { note: { meetingId: string; recordingIds?: string[] } }) => <div data-testid="recording">{note.meetingId} · {note.recordingIds?.join(",")}</div> }));
vi.mock("./MeetingSidekick", () => ({ MeetingSidekick: ({ archived, visible, onHide }: { archived: boolean; visible: boolean; onHide: () => void }) => <aside hidden={!visible} aria-label="Jasper" data-archived={archived}><button onClick={onHide}>Hide Jasper</button></aside> }));
vi.mock("@/components/EmberMascot", () => ({ EmberMascot: () => null }));
vi.mock("@/components/JasperIntelKit", () => ({ JasperCanvasBackdrop: () => null, JasperKitKeyframes: () => null, useJasperSheetTheme: () => ({ theme: {}, dark: false }) }));
vi.mock("@/lib/meetings", () => ({ fetchTranscript: vi.fn().mockResolvedValue([{ id: "speech", username: "Alex", text: "Launch is Thursday." }]) }));
afterEach(cleanup);
function show(notes: string | null): void {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<QueryClientProvider client={client}><MeetingNotesScreen title="Launch meeting" meetingId="meeting" recordingId="exact-recording" notes={notes} onClose={() => undefined} /></QueryClientProvider>);
}
describe("restored meeting notes", () => {
  it("shows transcript and exact recording even when no summary exists", async () => {
    show(null);
    expect(await screen.findByText("Launch is Thursday.")).toBeInTheDocument();
    expect(screen.getByTestId("recording")).toHaveTextContent("meeting · exact-recording");
    expect(screen.queryByText("My meeting notebook")).not.toBeInTheDocument();
  });
  it('refreshes late speech without replacing original meeting notes', async () => {
    const { fetchTranscript } = await import('@/lib/meetings');
    show('Original decision snapshot.'); await screen.findByText('Launch is Thursday.');
    vi.mocked(fetchTranscript).mockResolvedValueOnce([{ id: 'late', username: 'Josh', text: 'Recovered final decision.' }] as never);
    fireEvent.click(screen.getByRole('button', { name: 'Refresh saved transcript' }));
    expect(await screen.findByText('Recovered final decision.')).toBeInTheDocument(); expect(screen.getByText('Original decision snapshot.')).toBeInTheDocument();
  });
  it("opens archived Jasper separately without replacing the original summary", async () => {
    show("Launch summary stays here.");
    await screen.findByText("Launch is Thursday.");
    expect(screen.queryByRole("complementary")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Ask Jasper about this meeting" }));
    expect(screen.getByRole("complementary")).toHaveAttribute("data-archived", "true");
    expect(screen.getByText("Launch summary stays here.")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Hide Jasper" }));
    expect(screen.getByText("Launch summary stays here.")).toBeInTheDocument();
  });
});
