import { afterEach, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { PostInsightMetrics } from "./PostInsightMetrics";
vi.mock("@/lib/supabase", () => ({ supabaseUrl: "https://fixture.invalid", supabaseAnonKey: "fixture" }));
vi.mock("@/lib/groupThemeSession", () => ({ groupThemeSession: async () => ({ token: "fixture", signal: new AbortController().signal, check() {}, dispose() {} }) }));
vi.mock("@/hooks/useDocumentVisible", () => ({ useDocumentVisible: () => true }));
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
function mount() { render(<QueryClientProvider client={new QueryClient({defaultOptions:{queries:{retry:false}}})}><PostInsightMetrics accountID="owner" postID="post" /></QueryClientProvider>); }
it("uses independent exact HEAD counts and keeps unavailable distinct from zero", async () => {
  const fetcher = vi.fn(async (input: string, init?: RequestInit) => {
    if (input.includes("whisper_posts?")) return Response.json([{id:"post"}]);
    expect(init?.method).toBe("HEAD");
    if (input.includes("whisper_post_views")) return new Response(null, {status:503});
    return new Response(null, {headers:{"content-range":input.includes("likes") ? "*/12001" : "*/0"}});
  }); vi.stubGlobal("fetch", fetcher); mount();
  await waitFor(() => expect(screen.getByText("12,001")).toBeInTheDocument());
  expect(screen.getByText("0")).toBeInTheDocument(); expect(screen.getAllByText("—")).toHaveLength(1);
});
it("does not request metrics after failed owner admission", async () => {
  const fetcher = vi.fn(async () => Response.json([])); vi.stubGlobal("fetch", fetcher); mount();
  await waitFor(() => expect(screen.getByRole("button",{name:"Refresh insights"})).toBeEnabled());
  expect(fetcher).toHaveBeenCalledOnce(); expect(screen.getAllByText("—")).toHaveLength(3);
});
