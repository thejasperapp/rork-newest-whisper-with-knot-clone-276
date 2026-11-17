import { useRef, useState } from "react";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Palette, Loader2 } from "lucide-react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { GroupThemeSurface } from "@/components/GroupThemeSurface";
import { groupThemePresets, saveGroupTheme, themeTitle, type GroupThemeDesign, type GroupThemeRecord } from "@/lib/groupThemes";
import { cn } from "@/lib/utils";

export function GroupThemePicker({ groupID, accountID, record }: { groupID: string; accountID: string; record: GroupThemeRecord }) {
  const [open, setOpen] = useState<boolean>(false);
  const [draft, setDraft] = useState<GroupThemeDesign>(record.theme);
  const [baseline, setBaseline] = useState<number>(record.revision);
  const operation = useRef<string>(crypto.randomUUID());
  const queryClient = useQueryClient();
  const capture = useChatOperationGuard(accountID, groupID);
  const acceptance = useRef<(() => void) | null>(null);
  const mutation = useMutation({
    mutationFn: async () => {
      const check = capture(); acceptance.current = check;
      const row = await saveGroupTheme(groupID, accountID, baseline, draft, operation.current);
      check(); return row;
    },
    onSuccess: (row: GroupThemeRecord) => { try { acceptance.current?.(); } catch { return; } queryClient.setQueryData(["group-theme", accountID, groupID], row); setOpen(false); },
  });
  return <Dialog open={open} onOpenChange={value => { if (!mutation.isPending) setOpen(value); }}>
    <button type="button" className="mb-2 flex min-h-11 items-center gap-2 rounded-xl border border-border px-3 text-sm font-medium" onClick={() => { setDraft(record.theme); setBaseline(record.revision); operation.current = crypto.randomUUID(); mutation.reset(); setOpen(true); }}><Palette className="h-4 w-4"/>Themes · {record.theme.title}</button>
    <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-xl"><DialogHeader><DialogTitle>Set the mood for everyone</DialogTitle></DialogHeader>
      <GroupThemeSurface design={draft} className="space-y-4 p-6"><p className="text-center text-xs font-medium">{draft.title}</p><p className="group-incoming w-fit rounded-2xl px-4 py-3 text-sm">A little change of scenery?</p><p className="group-outgoing ml-auto w-fit rounded-2xl px-4 py-3 text-sm">This feels like us.</p></GroupThemeSurface>
      <div className="grid grid-cols-3 gap-3">{groupThemePresets.map(preset => <button key={preset} type="button" disabled={mutation.isPending} aria-pressed={draft.preset === preset && !draft.accent_hex} className={cn("min-h-11 rounded-xl border px-2 py-3 text-sm", draft.preset === preset && !draft.accent_hex ? "border-foreground font-semibold" : "border-border")} onClick={() => { setDraft({ version: 1, preset, title: themeTitle(preset) }); operation.current = crypto.randomUUID(); mutation.reset(); }}>{themeTitle(preset)}</button>)}</div>
      <p className="text-xs text-muted-foreground">Shared with every member, including iPhone and iPad. AI colorways created in the app appear here too.</p>
      {mutation.error && <p role="alert" className="text-sm text-destructive">{mutation.error.message}</p>}
      <button type="button" disabled={mutation.isPending} className="flex min-h-12 items-center justify-center gap-2 rounded-full bg-foreground px-4 font-semibold text-background disabled:opacity-50" onClick={() => mutation.mutate()}>{mutation.isPending && <Loader2 className="h-4 w-4 animate-spin"/>}Apply for everyone</button>
    </DialogContent>
  </Dialog>;
}
