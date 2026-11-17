import { afterEach, expect, it } from "vitest";
import { act, cleanup, renderHook } from "@testing-library/react";
import { useConversationNickname } from "./useConversationNickname";
afterEach(()=>{cleanup();localStorage.clear();});
it("isolates nicknames across accounts and direct/dating threads",()=>{
  const {result,rerender}=renderHook(({account,thread})=>useConversationNickname(account,thread),{initialProps:{account:"a",thread:"direct:peer"}});
  act(()=>result.current.saveNickname("Friend"));expect(result.current.nickname).toBe("Friend");
  rerender({account:"a",thread:"dating:peer"});expect(result.current.nickname).toBe("");
  rerender({account:"b",thread:"direct:peer"});expect(result.current.nickname).toBe("");
  rerender({account:"a",thread:"direct:peer"});expect(result.current.nickname).toBe("Friend");
  act(()=>result.current.saveNickname(""));expect(result.current.nickname).toBe("");
});
