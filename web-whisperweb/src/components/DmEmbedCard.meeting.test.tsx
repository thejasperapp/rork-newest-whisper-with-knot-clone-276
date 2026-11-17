import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
vi.mock("@/hooks/useAuth", () => ({ useAuth: () => ({ user: null, profile: null }) }));
import { DmEmbedCard } from "./DmEmbedCard";

afterEach(cleanup);
describe("meeting DM card action", () => {
  it.each(["ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456", "wsp-Ab12-Cd34"])("opens Meet with exact identity %s even without an authenticated viewer", (identity) => {
    render(<QueryClientProvider client={new QueryClient()}><DmEmbedCard body={`Join my meeting: https://www.mydailywhisper.com/meet/${identity}`} mine={false} meId="" /></QueryClientProvider>);
    expect(screen.getByRole("link", { name: /Open in Whisper Meet/ })).toHaveAttribute("href", `https://meet.mydailywhisper.com/meet/${identity}`);
  });
  it("keeps a voice call on its existing social route", () => {
    const body = '::whisper-call-v1::{"meetingId":"ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456","fromUserId":"sender","fromUsername":"alex","mode":"audio","at":1}';
    render(<QueryClientProvider client={new QueryClient()}><DmEmbedCard body={body} mine={false} meId="" /></QueryClientProvider>);
    expect(screen.getByRole("link")).toHaveAttribute("href", "/meet/ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456?call=alex&mode=audio");
    expect(screen.queryByText("Open in Whisper Meet")).toBeNull();
  });
});
