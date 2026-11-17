import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, cleanup, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { loadTeamsCard, teamsCardCandidate } from "./teamsInvitation";
import { TeamsInvitationCard } from "@/components/TeamsInvitationCard";

const auth = vi.hoisted(() => ({ id: "22222222-2222-4222-8222-222222222222", listener: undefined as undefined | ((_event: string, session: { user: { id: string } } | null) => void) }));
vi.mock("@/hooks/useAuth", () => ({ useAuth: () => ({ user: { id: auth.id } }) }));
vi.mock("@/lib/supabase", () => ({ supabaseUrl: "https://social.test", supabaseAnonKey: "test-anon", supabase: { auth: {
  onAuthStateChange: (callback: typeof auth.listener) => { auth.listener = callback; return { data: { subscription: { unsubscribe: vi.fn() } } }; },
  getSession: async () => ({ data: { session: { user: { id: auth.id }, access_token: "fixture-session" } }, error: null }),
} } }));
const sender = "11111111-1111-4111-8111-111111111111";
const recipient = "22222222-2222-4222-8222-222222222222";
const message = { id: "33333333-3333-4333-8333-333333333333", from_user_id: sender, to_user_id: recipient };
const card = { messageId: message.id, invitationId: "44444444-4444-4444-8444-444444444444", teamId: "55555555-5555-4555-8555-555555555555", inviterId: sender, recipientId: recipient, version: "1", teamName: "Private test team", status: "pending", expiresAt: Date.now()+3600000, occurredAt: Date.now(), canOpen: true };
let transport: ReturnType<typeof vi.fn<typeof fetch>>;
beforeEach(() => {
  auth.id = recipient;
  Object.defineProperty(document,"visibilityState",{configurable:true,value:"visible"});
  transport=vi.fn<typeof fetch>().mockResolvedValue(Response.json(card)); vi.stubGlobal("fetch",transport);
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
function mount() {
  const cache = new QueryClient({defaultOptions:{queries:{retry:false,gcTime:0}}});
  return render(<QueryClientProvider client={cache}><TeamsInvitationCard message={message}/></QueryClientProvider>);
}
describe("Teams invitation binding and UI",()=>{
  it("requires the exact standalone marker and message identity; quotes/copies are not live cards",()=>{
    expect(teamsCardCandidate(`::whisper-teams-v1::${message.id}`,message.id)).toBe(true);
    expect(teamsCardCandidate(`Quoted: ::whisper-teams-v1::${message.id}`,message.id)).toBe(false);
    expect(teamsCardCandidate(`::whisper-teams-v1::${message.id}`,sender)).toBe(false);
    expect(teamsCardCandidate("::whisper-teams-v1::{\"verified\":true}",message.id)).toBe(false);
  });
  it("uses the account session, no redirects/cache and binds all participant IDs",async()=>{
    expect((await loadTeamsCard(recipient,message)).teamName).toBe(card.teamName);
    expect(transport.mock.calls[0][0]).toBe("https://social.test/rest/v1/rpc/whisper_social_teams_card");
    expect(transport.mock.calls[0][1]).toMatchObject({method:"POST",redirect:"error",cache:"no-store",body:JSON.stringify({p_message_id:message.id})});
    transport.mockResolvedValueOnce(Response.json({...card,recipientId:sender}));
    await expect(loadTeamsCard(recipient,message)).rejects.toThrow();
    transport.mockResolvedValueOnce(Response.json({...card,messageId:sender}));
    await expect(loadTeamsCard(recipient,message)).rejects.toThrow();
  });
  it("rejects a successful late response after an A-to-B-to-A account transition",async()=>{
    transport.mockImplementationOnce(async()=>{
      auth.listener?.("SIGNED_IN",{user:{id:sender}});
      auth.listener?.("SIGNED_IN",{user:{id:recipient}});
      return Response.json(card);
    });
    await expect(loadTeamsCard(recipient,message)).rejects.toThrow();
  });
  it("shows last-reported status but no Accept, Join or unapproved browser link",async()=>{
    mount(); expect(await screen.findByText(card.teamName)).toBeInTheDocument();
    expect(screen.getByText(/Reported by Teams/)).toBeInTheDocument();
    expect(screen.getByText(/browser return link isn't available/)).toBeInTheDocument();
    expect(screen.queryByRole("button",{name:/accept|join/i})).not.toBeInTheDocument();
    expect(screen.queryByRole("link")).not.toBeInTheDocument();
    expect(transport).toHaveBeenCalledTimes(1);
  });
  it("keeps an unresolvable candidate generic and offers retry without leaking any title",async()=>{
    transport.mockResolvedValueOnce(Response.json({error:"denied"},{status:403})); mount();
    expect(await screen.findByText(/couldn't be confirmed/)).toBeInTheDocument();
    expect(screen.queryByText(card.teamName)).not.toBeInTheDocument();
    expect(screen.getByRole("button",{name:"Refresh status"})).toBeEnabled();
  });
  it("hides private card metadata when the browser becomes inactive",async()=>{
    mount(); expect(await screen.findByText(card.teamName)).toBeInTheDocument();
    act(()=>{Object.defineProperty(document,"visibilityState",{configurable:true,value:"hidden"});document.dispatchEvent(new Event("visibilitychange"));});
    await waitFor(()=>expect(screen.queryByText(card.teamName)).not.toBeInTheDocument());
    expect(screen.getByRole("button",{name:"Refresh status"})).toBeDisabled();
  });
  it("does not offer review guidance for expired or accepted invitations",async()=>{
    transport.mockResolvedValueOnce(Response.json({...card,status:"accepted",canOpen:false})); mount();
    expect(await screen.findByText("Accepted in Teams")).toBeInTheDocument();
    expect(screen.queryByText(/Review this invitation/)).not.toBeInTheDocument();
  });
});
