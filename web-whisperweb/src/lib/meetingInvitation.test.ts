import { describe, expect, it } from "vitest";
import { meetingInvitationFromText, meetingInvitationLink, parseMeetingInvitation } from "./meetingInvitation";

describe("public meeting invitations", () => {
  it.each(["ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456", "wsp-Ab12-Cd34"])("preserves %s across canonical and legacy hosts", (identity) => {
    const canonical = `https://meet.mydailywhisper.com/meet/${identity}`;
    expect(meetingInvitationLink(identity)).toBe(canonical);
    for (const host of ["www.mydailywhisper.com", "mydailywhisper.com", "meet.mydailywhisper.com"]) {
      const input = `https://${host}/meet/${identity}?access_token=discard&autoJoin=1#refresh_token=discard`;
      expect(parseMeetingInvitation(input)).toEqual({ idOrCode: identity, social: false, href: canonical });
      expect(meetingInvitationFromText(`Join my meeting: ${input}`)?.href).toBe(canonical);
    }
    expect(meetingInvitationFromText(identity)?.idOrCode).toBe(identity);
    expect(meetingInvitationFromText(`www.mydailywhisper.com/meet/${identity}`)?.href).toBe(canonical);
  });

  it("recognizes the legacy short Meet path without replacing the code", () => {
    expect(parseMeetingInvitation("https://meet.mydailywhisper.com/wsp-Ab12-Cd34")?.href).toBe("https://meet.mydailywhisper.com/meet/wsp-Ab12-Cd34");
  });

  it.each(["https://evil.example/meet/wsp-ab12-cd34", "https://www.mydailywhisper.com.evil.example/meet/wsp-ab12-cd34", "https://user:secret@www.mydailywhisper.com/meet/wsp-ab12-cd34", "https://www.mydailywhisper.com/meet/wsp-ab12-cd34/extra", "wsp-ab12-cd345", "::whisper-date-invite-v1::{\"meetCode\":\"wsp-ab12-cd34\"}", "::whisper-calendar-v1::{\"link\":\"https://www.mydailywhisper.com/meet/wsp-ab12-cd34\"}"])("rejects unrelated or structured input %s", (input) => {
    expect(meetingInvitationFromText(input)).toBeNull();
  });

  it.each(["sd=1", "call=alex&mode=audio", "call=alex&mode=video", "groupCall=1"])("keeps %s in social Whisper", (query) => {
    const result = parseMeetingInvitation(`https://www.mydailywhisper.com/meet/wsp-Ab12-Cd34?${query}&access_token=discard`);
    expect(result?.social).toBe(true);
    expect(result?.href).toBe(`https://www.mydailywhisper.com/meet/wsp-Ab12-Cd34?${query}`);
  });

  it("keeps old group announcements social", () => {
    const result = meetingInvitationFromText("Started a group audio call — join here: https://www.mydailywhisper.com/meet/ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456");
    expect(result?.social).toBe(true);
    expect(result?.href).toBe("https://www.mydailywhisper.com/meet/ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456?groupCall=1");
  });
});
