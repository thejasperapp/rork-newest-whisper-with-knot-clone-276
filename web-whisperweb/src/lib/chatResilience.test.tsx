import { describe, expect, it, vi } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { decodeCalendarEmbed } from "./calendar";
import { collapseMeetMessages, meetEventID } from "./meetMessageIdentity";
import { sharedStoryID, loadSharedStory } from "./sharedStory";
import { ChatMessageBoundary } from "@/components/ChatMessageBoundary";
import { loadEmberHistory, saveEmberConversation, deleteEmberConversation } from "./emberBrain";
import type { WhisperMessage } from "./types";
vi.mock("@/lib/supabase", () => ({ supabase: { auth: { onAuthStateChange: () => ({data:{subscription:{unsubscribe(){}}}}), getSession: async () => ({data:{session:null},error:null}) } }, supabaseUrl: "https://test.local", supabaseAnonKey: "fixture" }));
vi.mock("./groupThemeSession", () => ({ groupThemeSession: async () => ({ token:"fixture", signal: new AbortController().signal, check(){},dispose(){} }) }));
const id="11111111-1111-4111-8111-111111111111";
describe("chat resilience and parity",()=>{
 it("normalizes omitted and null legacy calendar fields rather than crashing taggedUsernames.length",()=>{
  const result=decodeCalendarEmbed('::whisper-calendar-v1::'+JSON.stringify({eventID:id,title:"Fixture",taggedUsernames:null}));
  expect(result?.taggedUsernames).toEqual([]);expect(result?.createdByUsername).toBe("organizer");
  expect(decodeCalendarEmbed('::whisper-calendar-v1::{"title":"bad","eventID":null}')).toBeNull();
 });
 it("recognizes ID-only Meet envelopes without inventing a title from private metadata",()=>{
  const body='::whisper-calendar-v1::'+JSON.stringify({kind:"chat-meet",eventID:id});
  expect(meetEventID(body)).toBe(id);expect(decodeCalendarEmbed(body)?.kind).toBe("chat-meet");
  expect(()=>collapseMeetMessages([{body,from_user_id:null,to_user_id:null} as unknown as WhisperMessage])).not.toThrow();
  expect(meetEventID(null)).toBeNull();
 });
 it("isolates a broken attachment while preserving the rest of a conversation",()=>{
  const log=vi.spyOn(console,"error").mockImplementation(()=>{});
  function Broken():never{throw new Error("fixture malformed attachment");}
  try { render(<><p>Other message</p><ChatMessageBoundary><Broken/></ChatMessageBoundary></>);expect(screen.getByText("Other message")).toBeInTheDocument();expect(screen.getByRole("status")).toHaveTextContent(/couldn't be displayed/); }
  finally{cleanup();log.mockRestore();}
 });
 it("keeps Intelligence history account-bound, without adopting old unowned history",()=>{
  localStorage.clear();saveEmberConversation("legacy",[{role:"user",text:"Unowned"}]);
  expect(loadEmberHistory("alice")).toEqual([]);
  saveEmberConversation("a",[{role:"user",text:"Alice's private question"}],"alice");
  expect(loadEmberHistory("bob")).toEqual([]);expect(loadEmberHistory("alice")).toHaveLength(1);
  deleteEmberConversation("a","bob");expect(loadEmberHistory("alice")).toHaveLength(1);
  deleteEmberConversation("a","alice");expect(loadEmberHistory("alice")).toEqual([]);localStorage.clear();
 });
 it("does not accept caller-supplied Story preview JSON or quote a tag as a live story",()=>{
  expect(sharedStoryID(`::whisper-storytag-v1::${id}`)).toBe(id);
  expect(sharedStoryID(`::whisper-story-v1::${id}`)).toBe(id);
  expect(sharedStoryID(`Quote: ::whisper-story-v1::${id}`)).toBeNull();
  expect(sharedStoryID('::whisper-story-v1::{"image_url":"https://wrong.test"}')).toBeNull();
 });
 it("rejects expired and rebound Story resolver responses",async()=>{
  const value={id,user_id:id,username:"fixture",image_url:"https://test.local/story.jpg",caption:null,created_at:null,expires_at:new Date(Date.now()-1000).toISOString(),metadata:null,music_url:null,music_title:null,music_artist:null,music_artwork:null};
  const fetcher=vi.fn().mockResolvedValueOnce(Response.json(value)).mockResolvedValueOnce(Response.json({...value,id:"22222222-2222-4222-8222-222222222222",expires_at:new Date(Date.now()+3600000).toISOString()}));
  vi.stubGlobal("fetch",fetcher);
  try {await expect(loadSharedStory(id,id,new AbortController().signal)).rejects.toThrow();await expect(loadSharedStory(id,id,new AbortController().signal)).rejects.toThrow();expect(fetcher.mock.calls[0][1].redirect).toBe("error");}
  finally{vi.unstubAllGlobals();}
 });
});
