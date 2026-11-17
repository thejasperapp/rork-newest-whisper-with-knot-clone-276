import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  CalendarDays,
  Check,
  CircleDot,
  ClipboardCheck,
  Handshake,
  Loader2,
  MessageCircleHeart,
  Plus,
  Send,
  Sparkles,
  UserPlus,
  UsersRound,
} from "lucide-react";
import { toast } from "sonner";

import { Header } from "@/components/Header";
import { useAuth } from "@/hooks/useAuth";
import {
  addCollabActivity,
  createCollabProject,
  fetchCollabDetail,
  fetchCollabProjects,
  inviteToCollab,
  updateCollabActivityStatus,
  type CollabActivity,
  type CollabActivityKind,
  type CollabActivityStatus,
  type CollabFormat,
  type CollabProject,
} from "@/lib/collabs";
import { cn } from "@/lib/utils";

const FORMAT_OPTIONS: { id: CollabFormat; label: string; description: string }[] = [
  { id: "content_sprint", label: "Content sprint", description: "Create, review, and ship together." },
  { id: "community_challenge", label: "Community challenge", description: "Run a friendly week of shared momentum." },
  { id: "feedback_swap", label: "Feedback swap", description: "Trade profile, post, or portfolio notes." },
  { id: "brand_campaign", label: "Brand campaign", description: "Coordinate creators and a clear deliverable." },
  { id: "scouting_room", label: "Scouting room", description: "Bring coaches, athletes, and recruiters together." },
  { id: "custom", label: "Custom project", description: "Start with a blank, focused room." },
];

const KIND_LABEL: Record<CollabActivityKind, string> = {
  task: "Task",
  post: "Post",
  review: "Review",
  meeting: "Meet-up",
  challenge: "Challenge",
};

function formatLabel(format: CollabFormat): string {
  return FORMAT_OPTIONS.find((item) => item.id === format)?.label ?? "Project";
}

function statusLabel(status: CollabActivityStatus): string {
  if (status === "doing") return "In motion";
  if (status === "done") return "Done";
  return "Ready";
}

function ActivityCard({
  activity,
  onStatus,
  busy,
}: {
  activity: CollabActivity;
  onStatus: (status: CollabActivityStatus) => void;
  busy: boolean;
}) {
  const next: CollabActivityStatus =
    activity.status === "open" ? "doing" : activity.status === "doing" ? "done" : "open";
  return (
    <div className="rounded-2xl border border-border bg-card p-3.5">
      <div className="flex items-start gap-3">
        <button
          type="button"
          disabled={busy}
          aria-label={`Mark ${activity.title} ${next}`}
          onClick={() => onStatus(next)}
          className={cn(
            "mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full border transition-colors",
            activity.status === "done"
              ? "border-foreground bg-foreground text-background"
              : activity.status === "doing"
                ? "border-foreground bg-secondary"
                : "border-border bg-background"
          )}
        >
          {activity.status === "done" ? <Check className="h-3.5 w-3.5" /> : <CircleDot className="h-3.5 w-3.5" />}
        </button>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-1.5">
            <p className={cn("text-[14px] font-bold", activity.status === "done" && "text-muted-foreground line-through")}>{activity.title}</p>
            <span className="rounded-full bg-secondary px-2 py-0.5 text-[10px] font-bold text-muted-foreground">{KIND_LABEL[activity.kind]}</span>
          </div>
          {activity.detail && <p className="mt-1 text-[12.5px] leading-snug text-muted-foreground">{activity.detail}</p>}
          <p className="mt-2 text-[10.5px] font-medium text-muted-foreground">
            {statusLabel(activity.status)} · added by @{activity.created_by_username || "a collaborator"}
            {activity.due_on ? ` · due ${new Date(`${activity.due_on}T12:00:00`).toLocaleDateString(undefined, { month: "short", day: "numeric" })}` : ""}
          </p>
        </div>
      </div>
    </div>
  );
}

function ProjectDetail({
  project,
  token,
  canManage,
  onBack,
}: {
  project: CollabProject;
  token: string;
  canManage: boolean;
  onBack: () => void;
}) {
  const client = useQueryClient();
  const [activityTitle, setActivityTitle] = useState<string>("");
  const [activityDetail, setActivityDetail] = useState<string>("");
  const [activityKind, setActivityKind] = useState<CollabActivityKind>("task");
  const [invitee, setInvitee] = useState<string>("");
  const detail = useQuery({
    queryKey: ["collab-detail", project.id],
    queryFn: () => fetchCollabDetail(token, project.id),
    enabled: !!token,
  });
  const refresh = (): void => {
    void client.invalidateQueries({ queryKey: ["collab-detail", project.id] });
    void client.invalidateQueries({ queryKey: ["collabs"] });
  };
  const addActivity = useMutation({
    mutationFn: () => addCollabActivity(token, { projectId: project.id, title: activityTitle.trim(), detail: activityDetail.trim(), kind: activityKind, dueOn: null }),
    onSuccess: () => { setActivityTitle(""); setActivityDetail(""); refresh(); },
    onError: () => toast.error("Couldn't add that activity yet."),
  });
  const invite = useMutation({
    mutationFn: () => inviteToCollab(token, project.id, invitee.trim()),
    onSuccess: () => { setInvitee(""); refresh(); toast.success("Invite sent — they can now enter this project."); },
    onError: (error) => toast.error(error instanceof Error && error.message === "member_not_found" ? "We couldn't find that @username." : "Couldn't send that invite."),
  });
  const setStatus = useMutation({
    mutationFn: ({ activityId, status }: { activityId: string; status: CollabActivityStatus }) => updateCollabActivityStatus(token, project.id, activityId, status),
    onSuccess: refresh,
    onError: () => toast.error("Couldn't update that activity."),
  });

  const activities = detail.data?.activities ?? [];
  const members = detail.data?.members ?? [];
  const done = activities.filter((activity) => activity.status === "done").length;

  return (
    <div className="mx-auto max-w-2xl px-4 pb-20 pt-4 sm:px-6">
      <button type="button" onClick={onBack} className="mb-5 inline-flex items-center gap-1 text-[13px] font-bold text-muted-foreground hover:text-foreground"><ArrowLeft className="h-4 w-4" /> All projects</button>
      <div className="rounded-[28px] border border-border bg-card p-5 sm:p-6">
        <div className="flex items-start justify-between gap-4">
          <div>
            <span className="inline-flex items-center gap-1.5 rounded-full bg-secondary px-2.5 py-1 text-[10px] font-extrabold uppercase tracking-wider text-muted-foreground"><Handshake className="h-3 w-3" /> {formatLabel(project.format)}</span>
            <h1 className="mt-3 text-[25px] font-extrabold tracking-tight">{project.title}</h1>
            {project.summary && <p className="mt-2 max-w-xl text-[14px] leading-relaxed text-muted-foreground">{project.summary}</p>}
          </div>
          <span className="shrink-0 rounded-full border border-border px-2.5 py-1 text-[11px] font-bold">{done}/{activities.length} done</span>
        </div>
        <div className="mt-5 flex flex-wrap gap-1.5">
          {members.map((member) => <span key={member.user_id} className="rounded-full bg-secondary px-2.5 py-1 text-[11px] font-bold">@{member.username || "member"}</span>)}
          {detail.isLoading && <span className="text-[12px] text-muted-foreground">Loading collaborators…</span>}
        </div>
      </div>

      {canManage && (
        <form onSubmit={(event) => { event.preventDefault(); if (invitee.trim()) invite.mutate(); }} className="mt-4 rounded-2xl border border-border bg-card p-3.5">
          <p className="flex items-center gap-1.5 text-[12px] font-extrabold"><UserPlus className="h-4 w-4" /> Invite a collaborator</p>
          <div className="mt-2 flex gap-2"><input value={invitee} onChange={(event) => setInvitee(event.target.value)} placeholder="@username" className="h-10 min-w-0 flex-1 rounded-xl border border-border bg-background px-3 text-sm outline-none focus:border-foreground" /><button disabled={invite.isPending} className="rounded-xl bg-foreground px-3 text-sm font-bold text-background disabled:opacity-60">Invite</button></div>
          <p className="mt-2 text-[10.5px] text-muted-foreground">Only moderators and higher can open the door. Invitees can add and complete shared activities.</p>
        </form>
      )}

      <section className="mt-6">
        <div className="mb-3 flex items-center justify-between"><h2 className="text-[16px] font-extrabold">Shared activities</h2><span className="text-[12px] text-muted-foreground">Everyone can move these forward</span></div>
        <div className="space-y-2.5">
          {detail.isLoading && <div className="flex justify-center py-8"><Loader2 className="h-5 w-5 animate-spin text-muted-foreground" /></div>}
          {!detail.isLoading && activities.length === 0 && <div className="rounded-2xl border border-dashed border-border p-6 text-center"><ClipboardCheck className="mx-auto h-6 w-6 text-muted-foreground" /><p className="mt-2 text-sm font-bold">Give the room its first move.</p><p className="mt-1 text-xs text-muted-foreground">A post, feedback round, check-in, or simple task is enough to start.</p></div>}
          {activities.map((activity) => <ActivityCard key={activity.id} activity={activity} busy={setStatus.isPending} onStatus={(status) => setStatus.mutate({ activityId: activity.id, status })} />)}
        </div>
      </section>

      <form onSubmit={(event) => { event.preventDefault(); if (activityTitle.trim().length >= 2) addActivity.mutate(); }} className="mt-4 rounded-[22px] border border-border bg-card p-4">
        <p className="flex items-center gap-1.5 text-[13px] font-extrabold"><Plus className="h-4 w-4" /> Add a shared activity</p>
        <div className="mt-3 grid gap-2 sm:grid-cols-[1fr_auto]"><input value={activityTitle} onChange={(event) => setActivityTitle(event.target.value)} placeholder="What can the group do next?" className="h-10 rounded-xl border border-border bg-background px-3 text-sm outline-none focus:border-foreground" /><select value={activityKind} onChange={(event) => setActivityKind(event.target.value as CollabActivityKind)} className="h-10 rounded-xl border border-border bg-background px-3 text-sm outline-none"><option value="task">Task</option><option value="post">Post</option><option value="review">Review</option><option value="meeting">Meet-up</option><option value="challenge">Challenge</option></select></div>
        <textarea value={activityDetail} onChange={(event) => setActivityDetail(event.target.value)} rows={2} placeholder="Add a little context, if the group needs it." className="mt-2 w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm outline-none focus:border-foreground" />
        <button disabled={addActivity.isPending} className="mt-2 flex h-10 w-full items-center justify-center gap-1.5 rounded-full bg-foreground text-sm font-bold text-background disabled:opacity-60"><Send className="h-3.5 w-3.5" /> {addActivity.isPending ? "Adding…" : "Add to the board"}</button>
      </form>
    </div>
  );
}

/** Invite-only collaboration hub. Mods create rooms; only their invitees can join the work. */
export default function Collabs() {
  const { session } = useAuth();
  const token = session?.access_token ?? "";
  const client = useQueryClient();
  const [selected, setSelected] = useState<CollabProject | null>(null);
  const [creating, setCreating] = useState<boolean>(false);
  const [title, setTitle] = useState<string>("");
  const [summary, setSummary] = useState<string>("");
  const [format, setFormat] = useState<CollabFormat>("content_sprint");
  const projects = useQuery({ queryKey: ["collabs"], queryFn: () => fetchCollabProjects(token), enabled: !!token });
  const create = useMutation({
    mutationFn: () => createCollabProject(token, { title: title.trim(), summary: summary.trim(), format }),
    onSuccess: () => { setTitle(""); setSummary(""); setCreating(false); void client.invalidateQueries({ queryKey: ["collabs"] }); toast.success("Project created. Invite the right people when you open it."); },
    onError: () => toast.error("Couldn't create that project."),
  });
  const allProjects = projects.data?.projects ?? [];
  const canManage = projects.data?.canManage ?? false;
  const templates = useMemo(() => FORMAT_OPTIONS.slice(0, 4), []);

  return (
    <><Header title="Collab Projects" />
      {selected ? <ProjectDetail project={selected} token={token} canManage={canManage} onBack={() => setSelected(null)} /> :
        <main className="mx-auto max-w-2xl px-4 pb-20 pt-5 sm:px-6">
          <section className="rounded-[30px] bg-foreground px-5 py-6 text-background sm:px-7"><div className="flex items-start justify-between gap-4"><div><span className="inline-flex items-center gap-1.5 rounded-full bg-background/10 px-2.5 py-1 text-[10px] font-extrabold uppercase tracking-wider text-background/70"><UsersRound className="h-3 w-3" /> Invite-only rooms</span><h1 className="mt-3 text-[27px] font-extrabold tracking-tight">Make good work together.</h1><p className="mt-2 max-w-lg text-[14px] leading-relaxed text-background/70">Creators, coaches, athletes, recruiters, and the Whisper team can build a campaign, challenge, feedback round, or real community moment together.</p></div><MessageCircleHeart className="h-7 w-7 shrink-0 text-background/70" /></div></section>
          {canManage && <div className="mt-4"><button type="button" onClick={() => setCreating((open) => !open)} className="flex h-11 w-full items-center justify-center gap-2 rounded-full bg-foreground text-sm font-bold text-background"><Plus className="h-4 w-4" /> Start a project</button>{creating && <form onSubmit={(event) => { event.preventDefault(); if (title.trim().length >= 2) create.mutate(); }} className="mt-3 rounded-[24px] border border-border bg-card p-4"><p className="text-[14px] font-extrabold">Set the room up</p><input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Project name" className="mt-3 h-10 w-full rounded-xl border border-border bg-background px-3 text-sm outline-none focus:border-foreground" /><textarea value={summary} onChange={(event) => setSummary(event.target.value)} placeholder="What are people making or moving forward?" rows={2} className="mt-2 w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm outline-none focus:border-foreground" /><div className="mt-2 grid grid-cols-2 gap-1.5">{templates.map((item) => <button key={item.id} type="button" onClick={() => setFormat(item.id)} className={cn("rounded-xl border p-2 text-left", format === item.id ? "border-foreground bg-secondary" : "border-border")}><span className="block text-[11px] font-bold">{item.label}</span><span className="mt-0.5 block text-[10px] leading-snug text-muted-foreground">{item.description}</span></button>)}</div><button disabled={create.isPending} className="mt-3 flex h-10 w-full items-center justify-center gap-1.5 rounded-full bg-foreground text-sm font-bold text-background disabled:opacity-60"><Sparkles className="h-3.5 w-3.5" /> {create.isPending ? "Creating…" : "Create invite-only room"}</button></form>}</div>}
          {!canManage && <p className="mt-4 flex items-start gap-2 rounded-2xl border border-border bg-card px-3.5 py-3 text-[12.5px] leading-snug text-muted-foreground"><CalendarDays className="mt-0.5 h-4 w-4 shrink-0" /> A moderator or higher can invite you into a project. Once you're in, every activity board is yours to move forward with the group.</p>}
          <section className="mt-6"><div className="mb-3 flex items-center justify-between"><h2 className="text-[16px] font-extrabold">Your projects</h2>{projects.isLoading && <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />}</div><div className="space-y-2.5">{!projects.isLoading && allProjects.length === 0 && <div className="rounded-[24px] border border-dashed border-border px-5 py-8 text-center"><Handshake className="mx-auto h-7 w-7 text-muted-foreground" /><p className="mt-3 text-sm font-bold">No rooms yet.</p><p className="mt-1 text-xs text-muted-foreground">{canManage ? "Start one for a campaign, feedback swap, or community challenge." : "When a moderator invites you, it will show up right here."}</p></div>}{allProjects.map((project) => <button key={project.id} type="button" onClick={() => setSelected(project)} className="w-full rounded-[22px] border border-border bg-card p-4 text-left transition-colors hover:bg-secondary/50"><div className="flex items-start justify-between gap-3"><div><p className="text-[14px] font-extrabold">{project.title}</p><p className="mt-1 text-[12.5px] leading-snug text-muted-foreground">{project.summary || "A focused Whisper collaboration."}</p></div><span className="shrink-0 rounded-full bg-secondary px-2 py-1 text-[10px] font-bold text-muted-foreground">{formatLabel(project.format)}</span></div><p className="mt-3 text-[10.5px] font-medium text-muted-foreground">Started by @{project.created_by_username || "Whisper team"}</p></button>)}</div></section>
        </main>}
    </>
  );
}
