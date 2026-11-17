import { supabase, supabaseUrl, supabaseAnonKey } from "@/lib/supabase";
import { groupThemeSession } from "@/lib/groupThemeSession";

export const groupThemePresets = ["classic", "midnight", "rose", "ocean", "forest", "sand", "dusk", "cherry", "lavender", "mint", "coffee", "sky", "lantern", "tide", "nocturne", "wildflower", "blueprint", "terracotta"] as const;
export type GroupThemePreset = typeof groupThemePresets[number];
export interface GroupThemeDesign { version: 1; preset: GroupThemePreset; title: string; accent_hex?: string | null }
export interface GroupThemeRecord { group_id: string; theme: GroupThemeDesign; revision: number }
export const defaultGroupTheme: GroupThemeDesign = { version: 1, preset: "classic", title: "Classic" };
export const themeTitle = (preset: GroupThemePreset): string => ({ lantern: "Paper lantern", tide: "Tidal glass", nocturne: "After hours" }[preset as "lantern" | "tide" | "nocturne"] ?? preset.charAt(0).toUpperCase() + preset.slice(1));

export function isGroupTheme(value: unknown): value is GroupThemeDesign {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  return v.version === 1 && groupThemePresets.includes(v.preset as GroupThemePreset) && typeof v.title === "string" && v.title.trim().length > 0 && v.title.length <= 48 && (v.accent_hex == null || (typeof v.accent_hex === "string" && /^#[0-9a-fA-F]{6}$/.test(v.accent_hex)));
}

export async function loadGroupTheme(groupID: string, accountID: string): Promise<GroupThemeRecord> {
  const session = await groupThemeSession(accountID);
  try {
  const membership = await supabase.from("whisper_group_threads").select("id").eq("id", groupID).maybeSingle();
  session.check();
  if (membership.error || !membership.data) throw new Error("This group is unavailable.");
  const { data, error } = await supabase.from("whisper_group_themes").select("group_id,theme,revision").eq("group_id", groupID).maybeSingle();
  session.check();
  if (error) throw new Error("Couldn't load the shared theme.");
  if (!data) return { group_id: groupID, revision: 0, theme: defaultGroupTheme };
  return { group_id: data.group_id, revision: data.revision, theme: isGroupTheme(data.theme) ? data.theme : defaultGroupTheme };
  } finally { session.dispose(); }
}

export async function saveGroupTheme(groupID: string, accountID: string, revision: number, theme: GroupThemeDesign, operationID: string): Promise<GroupThemeRecord> {
  if (!isGroupTheme(theme)) throw new Error("Refresh the group before changing its theme.");
  const session = await groupThemeSession(accountID);
  try {
  session.check();
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/whisper_set_group_theme`, {
    method: "POST", signal: session.signal,
    headers: { apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_group_id: groupID, p_expected_revision: revision, p_theme: theme, p_operation_id: operationID }),
  });
  session.check();
  if (!response.ok) throw new Error(response.status === 409 ? "Someone changed the theme. Close and reopen Themes to review it, then try again." : "Couldn't save for everyone. Your preview is still here; try again.");
  const row = await response.json() as GroupThemeRecord;
  session.check();
  if (!row || row.group_id !== groupID || !isGroupTheme(row.theme)) throw new Error("Couldn't confirm the shared theme.");
  return row;
  } finally { session.dispose(); }
}

/** Opaque colors mirror native presets; arbitrary AI pigments are brightness-bounded. */
export function groupThemeColors(design: GroupThemeDesign): { light: string; dark: string; sent: string; received: string; raised: string; accent: string; accentDark: string; sentDark: string; sentTextDark: string; sentText: string; receivedText: string; receivedTextDark: string } {
  // Native WhisperChatAppearance.classic: quiet blue/gray, with dark text on sent bubbles in both modes.
  if (design.preset === "classic" && !design.accent_hex) return {
    light: "#FFFFFF", dark: "#14171C", sent: "#D3E1F6", received: "#EAE9EE",
    raised: "#2C3038", accent: "#5279AB", accentDark: "#5279AB",
    sentDark: "#B7CCE9", sentText: "#161D28", sentTextDark: "#161D28", receivedText: "#17171B", receivedTextDark: "#FFFFFF",
  };
  const presets: Record<GroupThemePreset, string[]> = {
    classic: ["#FAF9F6", "#141719", "#202729", "#EFEEEA", "#202527", "#647071"],
    midnight: ["#EAEFF8", "#101724", "#293D67", "#F7F9FF", "#263349", "#334A7D"], rose: ["#FAEFF0", "#25171F", "#863C56", "#FFF9F7", "#452D3A", "#BF597A"],
    ocean: ["#E9F3F4", "#10232B", "#165A70", "#F5FCFA", "#233E49", "#1F78AB"], forest: ["#EDF1E8", "#14251E", "#315B45", "#F8FAF2", "#2A3F31", "#407857"],
    sand: ["#F6EEE0", "#29221A", "#705035", "#FFFAF0", "#43382A", "#A37D52"], dusk: ["#F4EAEF", "#251E31", "#684460", "#FCF6F8", "#403147", "#945E6B"],
    cherry: ["#FAEDEC", "#2B171E", "#923347", "#FFF8F3", "#492B34", "#B3304A"], lavender: ["#F0ECF7", "#211E30", "#5E4C81", "#FAF8FF", "#37314B", "#826EA8"],
    mint: ["#E8F4EF", "#152923", "#246451", "#F4FFF9", "#2A4439", "#429E87"], coffee: ["#F2EAE2", "#241D19", "#604332", "#FFF8ED", "#403228", "#6E4F3D"],
    sky: ["#EDF4FC", "#172536", "#325E88", "#FAFCFF", "#2D3F54", "#4F96C4"], lantern: ["#F9F1DF", "#262019", "#78512C", "#FFFCF4", "#403428", "#AE7042"],
    tide: ["#EDF7F3", "#102825", "#245B58", "#F8FFFC", "#28433F", "#3C8380"], nocturne: ["#F0ECE8", "#191C23", "#5F493E", "#FAF8F4", "#32323A", "#AA795F"],
    wildflower: ["#F3F3E7", "#20281B", "#465C32", "#FDFFF3", "#36452C", "#718457"], blueprint: ["#EAF0F8", "#112237", "#264D77", "#F8FBFF", "#263C55", "#4477A3"], terracotta: ["#F9EDE5", "#2C201D", "#7D4635", "#FFF8F1", "#47322B", "#AB604B"],
  };
  let [light, dark, sent, received, raised, accent] = presets[design.preset] ?? presets.classic;
  // Reduce pigment on the reading surfaces; retain opaque, high-contrast bubbles.
  const soften = (hex: string, base: string, amount: number): string => "#" + [1, 3, 5].map(offset => Math.round(parseInt(hex.slice(offset, offset + 2), 16) * amount + parseInt(base.slice(offset, offset + 2), 16) * (1 - amount)).toString(16).padStart(2, "0")).join("");
  if (design.preset !== "classic") {
    light = soften(light, "#FAF9F6", .5); dark = soften(dark, "#141719", .6);
    received = soften(received, "#FFFFFF", .3); raised = soften(raised, "#202527", .5);
    sent = soften(sent, "#202729", .8);
  }
  let accentDark = accent;
  if (design.accent_hex && /^#[0-9a-fA-F]{6}$/.test(design.accent_hex)) {
    const rgb = [1, 3, 5].map(offset => parseInt(design.accent_hex!.slice(offset, offset + 2), 16) / 255);
    const mix = (base: number, amount: number): string => `rgb(${rgb.map(v => Math.round((base * (1 - amount) + v * amount) * 255)).join(" ")})`;
    light = mix(.98, .08); dark = mix(.055, .12); sent = mix(0, .46); received = mix(1, .035); raised = mix(.12, .15); accent = mix(.2, .5); accentDark = mix(.6, .5);
  }
  return { light, dark, sent, received, raised, accent, accentDark, sentDark: sent, sentText: "#FFFFFF", sentTextDark: "#FFFFFF", receivedText: "#202729", receivedTextDark: "#F3F3EE" };
}
