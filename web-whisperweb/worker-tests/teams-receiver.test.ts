// @vitest-environment node
import { createHmac, createHash } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
import { parseTeamsEvent, receiveTeamsEvent, teamsEventPath } from "../../functions/teams-invitations";

const now = Date.now();
const secret = "ab".repeat(32); // Synthetic key, never used outside isolated tests.
const env = { WHISPER_TEAMS_RECEIVER_ENABLED: "true", WHISPER_TEAMS_SIGNING_KEYS: JSON.stringify({ test: secret }), SUPABASE_SERVICE_ROLE_KEY: "test-only-db-key" };
const event = { schemaVersion: 1, source: "whisper-teams", eventId: "11111111-1111-4111-8111-111111111111", invitationId: "22222222-2222-4222-8222-222222222222", invitationVersion: "1", teamId: "33333333-3333-4333-8333-333333333333", teamName: "Test team", inviterId: "44444444-4444-4444-8444-444444444444", recipientId: "55555555-5555-4555-8555-555555555555", status: "pending", occurredAt: now, expiresAt: now + 60000 };
function request(raw = JSON.stringify(event), timestamp = String(Math.floor(now/1000)), keyId = "test"): Request {
  // Independently construct Teams' signing example (do not copy a production verifier).
  const digest = createHash("sha256").update(raw).digest("hex");
  const input = ["whisper-social-teams-v1", "POST", teamsEventPath, keyId, timestamp, digest].join("\n");
  const signature = createHmac("sha256", Buffer.from(secret,"hex")).update(input).digest("hex");
  return new Request(`https://social.example${teamsEventPath}`, { method:"POST", headers:{"Content-Type":"application/json","X-Whisper-Teams-Key-Id":keyId,"X-Whisper-Teams-Timestamp":timestamp,"X-Whisper-Teams-Signature":`v1=${signature}`},body:raw });
}
describe("Social Teams receiver", () => {
  it("validates the signed envelope and waits for a durable DB result with pinned origin and no redirects",async()=>{
    const transport = vi.fn<typeof fetch>().mockResolvedValue(Response.json({eventId:event.eventId,result:"applied"}));
    const result = await receiveTeamsEvent(request(),env,transport,now);
    expect(await result.json()).toEqual({eventId:event.eventId,acknowledged:true,result:"applied"});
    expect(transport).toHaveBeenCalledTimes(1);
    expect(transport.mock.calls[0][0]).toBe("https://uryyyegnbtlmyhqlgndy.supabase.co/rest/v1/rpc/whisper_social_teams_receive");
    expect(transport.mock.calls[0][1]?.redirect).toBe("error");
    expect(result.headers.get("cache-control")).toBe("no-store");
  });
  it("does not accept user JWTs or unsigned caller identity",async()=>{
    const req=request(); req.headers.delete("X-Whisper-Teams-Signature"); req.headers.set("Authorization","Bearer user-jwt");
    const transport=vi.fn<typeof fetch>();
    expect((await receiveTeamsEvent(req,env,transport,now)).status).toBe(401); expect(transport).not.toHaveBeenCalled();
  });
  it.each(["stale","future","key","body"])("rejects %s signatures before any DB request",async kind=>{
    const req=kind==="stale" ? request(undefined,String(Math.floor(now/1000)-301)) : kind==="future" ? request(undefined,String(Math.floor(now/1000)+301)) : kind==="key" ? request(undefined,undefined,"unknown") : request();
    const changed=kind==="body" ? new Request(req.url,{method:"POST",headers:req.headers,body:JSON.stringify({...event,status:"accepted"})}) : req;
    const transport=vi.fn<typeof fetch>(); expect((await receiveTeamsEvent(changed,env,transport,now)).status).toBe(401); expect(transport).not.toHaveBeenCalled();
  });
  it("fails closed when disabled, oversized or malformed",async()=>{
    const transport=vi.fn<typeof fetch>();
    expect((await receiveTeamsEvent(request(),{},transport,now)).status).toBe(503);
    expect((await receiveTeamsEvent(request(" ".repeat(8193)),env,transport,now)).status).toBe(413);
    expect((await receiveTeamsEvent(request("{"),env,transport,now)).status).toBe(422);
    expect(transport).not.toHaveBeenCalled();
  });
  it("rejects arbitrary return links, privileges, self invites and lossy versions",()=>{
    for(const patch of [{returnUrl:"https://evil.example"},{role:"owner"},{recipientId:event.inviterId},{invitationVersion:2},{invitationVersion:"9223372036854775808"},{teamName:"<script>"},{status:"joined"}]) expect(parseTeamsEvent({...event,...patch},now)).toBeNull();
    expect(parseTeamsEvent({...event,invitationVersion:"9007199254740993"},now)).not.toBeNull();
  });
  it.each(["duplicate","stale","suppressed"])("acknowledges %s without exposing private notification or message details",async result=>{
    const transport=vi.fn<typeof fetch>().mockResolvedValue(Response.json({eventId:event.eventId,result,messageId:"private",reason:"blocked"}));
    const response=await receiveTeamsEvent(request(),env,transport,now);
    expect(await response.json()).toEqual({eventId:event.eventId,acknowledged:true,result});
  });
  it("returns conflict without retry and never treats DB failure or malformed success as delivery",async()=>{
    const conflict=vi.fn<typeof fetch>().mockResolvedValue(Response.json({code:"PT409"},{status:409}));
    expect((await receiveTeamsEvent(request(),env,conflict,now)).status).toBe(409); expect(conflict).toHaveBeenCalledTimes(1);
    const failed=vi.fn<typeof fetch>().mockRejectedValue(new Error("timeout"));
    expect((await receiveTeamsEvent(request(),env,failed,now)).status).toBe(503);
    const malformed=vi.fn<typeof fetch>().mockResolvedValue(Response.json({ok:true}));
    expect((await receiveTeamsEvent(request(),env,malformed,now)).status).toBe(503);
  });
});
