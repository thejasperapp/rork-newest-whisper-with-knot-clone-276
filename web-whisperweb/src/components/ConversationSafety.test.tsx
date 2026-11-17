import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ConversationSafety } from "./ConversationSafety";
const fixture = vi.hoisted(() => ({ pending: null as Promise<void> | null }));
vi.mock("@/lib/supabase", () => ({ supabaseUrl: "https://fixture.invalid", supabaseAnonKey: "fixture", supabase: { auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) } } }));
vi.mock("@/lib/groupThemeSession", () => ({ groupThemeSession: async () => { if (fixture.pending) await fixture.pending; return { token: "fixture", signal: new AbortController().signal, check() {}, dispose() {} }; } }));
beforeEach(() => { fixture.pending = null; Object.defineProperty(document, "hidden", {configurable:true,value:false}); });
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
function mount(onBlocked = vi.fn()) { return render(<QueryClientProvider client={new QueryClient({defaultOptions:{queries:{retry:false}}})}><ConversationSafety accountID="owner" peerID="peer" username="person" onBlocked={onBlocked} /></QueryClientProvider>); }
it("reports via the supported RPC and requires its UUID receipt", async () => {
  const fetcher = vi.fn(async (url: string, init?: RequestInit) => {
    if (url.includes("whisper_blocks")) return Response.json([]);
    expect(url).toContain("rpc/whisper_submit_report"); expect(JSON.parse(String(init?.body))).toMatchObject({p_kind:"safety",p_target_id:"peer",p_reason:"spam"});
    return Response.json("11111111-1111-4111-8111-111111111111");
  }); vi.stubGlobal("fetch", fetcher); mount(); fireEvent.click(screen.getByRole("button",{name:"Submit report"}));
  await waitFor(() => expect(screen.getByText("Report submitted")).toBeInTheDocument());
});
it("does not claim a block if the server returns no matching row", async () => {
  vi.stubGlobal("fetch", vi.fn(async () => Response.json([]))); const done=vi.fn(); mount(done);
  await waitFor(() => expect(screen.getByRole("button",{name:"Block this person"})).toBeEnabled());
  fireEvent.click(screen.getByRole("button",{name:"Block this person"})); fireEvent.click(screen.getByRole("button",{name:"Confirm"}));
  await waitFor(() => expect(screen.getByRole("alert")).toBeInTheDocument()); expect(done).not.toHaveBeenCalled();
});
it("cancels before dispatch if session acquisition finishes after closing", async () => {
  const fetcher=vi.fn(async () => Response.json([]));vi.stubGlobal("fetch",fetcher);const view=mount();
  await waitFor(() => expect(screen.getByRole("button",{name:"Block this person"})).toBeEnabled());
  let resolve: () => void = () => {};fixture.pending=new Promise<void>(done=>{resolve=done;});
  fireEvent.click(screen.getByRole("button",{name:"Block this person"}));fireEvent.click(screen.getByRole("button",{name:"Confirm"}));
  view.unmount(); await act(async()=>{resolve();await Promise.resolve();}); expect(fetcher).toHaveBeenCalledOnce();
});
