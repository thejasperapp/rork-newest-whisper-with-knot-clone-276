import { z } from "zod";
import { groupThemeSession } from "./groupThemeSession";
import { supabaseUrl, supabaseAnonKey } from "./supabase";
import type { GroupPerson, GroupThread } from "./groupChats";

const rosterSchema = z.object({ id: z.string().uuid(), owner_id: z.string().uuid(), name: z.string(), member_ids: z.array(z.string().uuid()), member_usernames: z.array(z.string()), business_id: z.string().nullable(), created_at: z.string().nullable() }).passthrough();
const arrayLiteral = (items: string[]): string => `{${items.map(value => `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`).join(",")}}`;

/** Reauthorizes current membership before selecting recipients for a new send. */
export async function freshGroupForSend(groupID: string, accountID: string): Promise<GroupThread> {
  const session = await groupThemeSession(accountID);
  try {
    const params = new URLSearchParams({ id: `eq.${groupID}`, select: "*" });
    const result = await fetch(`${supabaseUrl}/rest/v1/whisper_group_threads?${params}`, { headers: { apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}` }, signal: AbortSignal.any([session.signal, AbortSignal.timeout(15_000)]), cache: "no-store", redirect: "error" });
    session.check();
    if (!result.ok) throw new Error("Couldn't verify the current group. Please try again.");
    const rows = z.array(rosterSchema).length(1).safeParse(await result.json()); session.check();
    if (!rows.success || rows.data[0].id.toLowerCase() !== groupID.toLowerCase() || ![rows.data[0].owner_id, ...rows.data[0].member_ids].some(id => id.toLowerCase() === accountID.toLowerCase())) throw new Error("This group is no longer available to you.");
    return rows.data[0] as GroupThread;
  } finally { session.dispose(); }
}

/** Fresh owner-bound compare-and-swap; never replaces a roster from an old UI snapshot. */
export async function changeGroupRoster(groupID: string, ownerID: string, change: { add: GroupPerson[] } | { remove: string }): Promise<GroupThread> {
  if (!z.string().uuid().safeParse(groupID).success) throw new Error("This group is unavailable.");
  const session = await groupThemeSession(ownerID);
  const signal = AbortSignal.any([session.signal, AbortSignal.timeout(15_000)]);
  const headers = { apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}`, "Content-Type": "application/json", Prefer: "return=representation" };
  try {
    const query = new URLSearchParams({ id: `eq.${groupID}`, select: "*" });
    const response = await fetch(`${supabaseUrl}/rest/v1/whisper_group_threads?${query}`, { headers, signal, cache: "no-store", redirect: "error" });
    session.check();
    if (!response.ok) throw new Error("Couldn't refresh the group. Please try again.");
    const rows = z.array(rosterSchema).length(1).safeParse(await response.json());
    session.check();
    if (!rows.success || rows.data[0].owner_id.toLowerCase() !== ownerID.toLowerCase()) throw new Error("Only the group owner can change its members.");
    const current = rows.data[0];
    if (current.id.toLowerCase() !== groupID.toLowerCase() || current.member_ids.length !== current.member_usernames.length) throw new Error("Couldn't verify the group roster.");
    const members = current.member_ids.map((id, index) => ({ id, username: current.member_usernames[index] ?? "member" }));
    let nextMembers: GroupPerson[];
    if ("add" in change) {
      const seen = new Set([ownerID.toLowerCase(), ...members.map(p => p.id.toLowerCase())]);
      nextMembers = [...members];
      for (const person of change.add) {
        if (!z.string().uuid().safeParse(person.id).success || seen.has(person.id.toLowerCase())) continue;
        seen.add(person.id.toLowerCase());
        nextMembers.push({ id: person.id.toLowerCase(), username: person.username });
      }
    } else {
      if (change.remove.toLowerCase() === ownerID.toLowerCase()) throw new Error("The owner cannot be removed.");
      nextMembers = members.filter(p => p.id.toLowerCase() !== change.remove.toLowerCase());
    }
    if (JSON.stringify(nextMembers) === JSON.stringify(members)) return current as GroupThread;
    query.set("owner_id", `eq.${ownerID}`);
    query.set("member_ids", `eq.${arrayLiteral(current.member_ids)}`);
    query.set("member_usernames", `eq.${arrayLiteral(current.member_usernames)}`);
    session.check();
    const saved = await fetch(`${supabaseUrl}/rest/v1/whisper_group_threads?${query}`, { method: "PATCH", headers, signal, redirect: "error", body: JSON.stringify({ member_ids: nextMembers.map(p => p.id), member_usernames: nextMembers.map(p => p.username) }) });
    session.check();
    if (!saved.ok) throw new Error("Member update wasn't confirmed. Refresh before retrying.");
    const receipt = z.array(rosterSchema).length(1).safeParse(await saved.json());
    session.check();
    if (!receipt.success || receipt.data[0].id !== current.id || JSON.stringify(receipt.data[0].member_ids) !== JSON.stringify(nextMembers.map(p => p.id))) throw new Error("The roster changed elsewhere. Refresh and try again.");
    return receipt.data[0] as GroupThread;
  } finally { session.dispose(); }
}
