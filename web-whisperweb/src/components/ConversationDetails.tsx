import { useMemo, useState } from "react";
import { toast } from "sonner";
import { useConversationNickname } from "@/hooks/useConversationNickname";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { Link } from "react-router-dom";
import { Search, UserRound, Image, Shield } from "lucide-react";
import { Avatar } from "@/components/Avatar";
import { ConversationSafety } from "@/components/ConversationSafety";
import { PersonalChatSettings } from "@/components/PersonalChatSettings";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { conversationKey } from "@/lib/conversationIdentity";
import { contentPreview } from "@/lib/contentPreview";
import { chatVideoUrl } from "@/lib/chatMedia";
import { isBareImageUrl } from "@/lib/linkPreview";
import { splitGroupReply } from "@/lib/groupChats";
import type { WhisperConversation, WhisperMessage } from "@/lib/types";

/** Thread-owned details leave the mounted conversation and its draft intact. */
export function ConversationDetails({ convo, accountID, messages, open, onOpenChange, onSelect, onBlocked }: {
  convo: WhisperConversation; accountID: string; messages: WhisperMessage[]; open: boolean;
  onOpenChange: (open: boolean) => void; onSelect: (id: string) => void; onBlocked: () => void;
}) {
  const { nickname, saveNickname } = useConversationNickname(accountID, conversationKey(convo));
  const capture = useChatOperationGuard(accountID, conversationKey(convo));
  const [nicknameDraft, setNicknameDraft] = useState<string | null>(null);
  const [query, setQuery] = useState<string>("");
  const [tab, setTab] = useState<"all" | "media" | "safety">("all");
  const rows = useMemo(() => messages.filter(m => {
    const body = splitGroupReply(m.body ?? "").text;
    return (tab !== "media" || isBareImageUrl(body) || !!chatVideoUrl(body)) && contentPreview(body).toLocaleLowerCase().includes(query.trim().toLocaleLowerCase());
  }).slice().reverse(), [messages, tab, query]);
  return <Dialog open={open} onOpenChange={onOpenChange}>
    <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-lg">
      <DialogHeader><DialogTitle>Conversation details</DialogTitle><DialogDescription>Manage this conversation without losing your draft.</DialogDescription></DialogHeader>
      <div className="flex flex-col items-center gap-2 py-3"><Avatar name={convo.otherUsername} url={convo.otherProfile?.profile_image_url} size={72} /><h2 className="text-xl font-semibold">{convo.otherProfile?.display_name || convo.otherUsername}</h2><p className="text-sm text-muted-foreground">@{convo.otherUsername}</p></div>
      <div className="grid grid-cols-4 gap-2 text-xs">
        <Link className="flex min-h-14 flex-col items-center gap-2 rounded-xl p-2 hover:bg-secondary" to={`/u/${encodeURIComponent(convo.otherUsername)}?id=${encodeURIComponent(convo.otherUserId)}`}><UserRound className="h-5 w-5" />Profile</Link>
        <button className="flex min-h-14 flex-col items-center gap-2 rounded-xl p-2 hover:bg-secondary" onClick={() => setTab("all")}><Search className="h-5 w-5" />Search</button>
        <button className="flex min-h-14 flex-col items-center gap-2 rounded-xl p-2 hover:bg-secondary" onClick={() => setTab("media")}><Image className="h-5 w-5" />Shared media</button>
        <button className="flex min-h-14 flex-col items-center gap-2 rounded-xl p-2 hover:bg-secondary" onClick={() => setTab("safety")}><Shield className="h-5 w-5" />Safety</button>
      </div>
      <PersonalChatSettings accountID={accountID} thread={conversationKey(convo)} />
      <details className="rounded-xl border border-border px-3"><summary className="min-h-11 cursor-pointer py-3 text-sm font-medium">Nickname · only you, in this browser</summary><form className="space-y-2 pb-3" onSubmit={e => { e.preventDefault(); try { capture()(); saveNickname(nicknameDraft ?? nickname); setNicknameDraft(null); toast.success("Nickname saved"); } catch { toast.error("Couldn't save your nickname."); } }}><Input aria-label="Personal nickname" maxLength={48} placeholder={convo.otherProfile?.display_name || convo.otherUsername} value={nicknameDraft ?? nickname} onChange={e => setNicknameDraft(e.target.value)} /><button className="min-h-11 text-sm font-semibold">Save nickname</button><p className="text-xs text-muted-foreground">Leave blank to restore their name. This does not change their profile or username.</p></form></details>
      {tab === "safety" ? <ConversationSafety accountID={accountID} peerID={convo.otherUserId} username={convo.otherUsername} onBlocked={onBlocked} /> : <>
        <Input aria-label="Search conversation" placeholder={tab === "media" ? "Search shared media" : "Search conversation"} value={query} onChange={e => setQuery(e.target.value)} />
        <p className="text-xs text-muted-foreground">Searches loaded messages. Select a result to return to it.</p>
        <div className="max-h-72 space-y-1 overflow-y-auto">{rows.map(m => <button key={m.id} className="block min-h-11 w-full rounded-xl p-3 text-left hover:bg-secondary" onClick={() => { onOpenChange(false); onSelect(m.id); }}><span className="block text-xs text-muted-foreground">@{m.from_username}</span><span className="line-clamp-2 text-sm">{isBareImageUrl(splitGroupReply(m.body ?? "").text) ? "Photo" : chatVideoUrl(m.body ?? "") ? "Video" : contentPreview(m.body)}</span></button>)}{!rows.length && <p className="py-8 text-center text-sm text-muted-foreground">No matching messages.</p>}</div>
      </>}
    </DialogContent>
  </Dialog>;
}
