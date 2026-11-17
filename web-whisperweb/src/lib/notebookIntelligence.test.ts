import { afterEach, describe, expect, it, vi } from "vitest";
import { newNotebookDocument } from "./notebookDocument";
import { runNotebookIntelligence } from "./notebookIntelligence";
import type { NotebookWorkflow } from "./notebookWorkflow";
const owner = "00000000-0000-4000-8000-000000000001";
vi.mock("./supabase", () => ({ supabase: { auth: { getSession: async () => ({ data: { session: { access_token: "synthetic-session", user: { id: "00000000-0000-4000-8000-000000000001" } } } }) } } }));
afterEach(() => vi.unstubAllGlobals());
describe("explicit Notebook task requests", () => {
  it.each<NotebookWorkflow>(["ask", "enhance", "summarize", "compare", "followups"])("sends %s semantics even with optional guidance and only supplied passages", async (workflow) => {
    const note = { ...newNotebookDocument(owner), notes: "This raw content was not selected", instructions: "Highlight blockers", templateId: "project" };
    const sources = [{ id: "M1-N1", kind: "notes" as const, text: "Selected evidence" }];
    const fetcher = vi.fn().mockResolvedValue(new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ insufficient: false, sections: [{ title: "Result", items: [{ text: "Supported", sourceIds: ["M1-N1"] }] }], actions: [] }) } }] }), { status: 200 }));
    vi.stubGlobal("fetch", fetcher);
    await runNotebookIntelligence(note, "Keep it brief", () => {}, new AbortController().signal, sources, workflow);
    const payload = JSON.parse(fetcher.mock.calls[0][1].body as string) as { messages: { role: string; content: string }[] };
    const context = JSON.parse(payload.messages[1].content) as { taskType: string; task: string; sources: unknown[]; outlinePreferences: string };
    expect(fetcher.mock.calls[0][0]).toMatch(/\/ai\/chat$/);
    expect(fetcher.mock.calls[0][1].headers.Authorization).toBe("Bearer synthetic-session");
    expect(context.taskType).toBe(workflow); expect(context.sources).toEqual(sources);
    expect(context.outlinePreferences).toBe(workflow === "enhance" ? "Highlight blockers" : "");
    expect(JSON.stringify(payload)).not.toContain(note.notes);
    if (workflow === "followups") expect(context.task).toContain("actions");
    if (workflow === "compare") expect(context.task).toContain("conflicts");
  });
});
