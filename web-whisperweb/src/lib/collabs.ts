import { BACKEND_URL } from "@/lib/billing";

export type CollabFormat =
  | "content_sprint"
  | "community_challenge"
  | "feedback_swap"
  | "brand_campaign"
  | "scouting_room"
  | "custom";
export type CollabActivityKind = "task" | "post" | "review" | "meeting" | "challenge";
export type CollabActivityStatus = "open" | "doing" | "done";

export interface CollabProject {
  id: string;
  title: string;
  summary: string;
  format: CollabFormat;
  status: "draft" | "active" | "complete" | "archived";
  created_by: string;
  created_by_username: string;
  created_at: string;
  updated_at: string;
}

export interface CollabMember {
  project_id: string;
  user_id: string;
  username: string;
  role: "lead" | "collaborator";
  status: "active" | "removed";
  created_at: string;
}

export interface CollabActivity {
  id: string;
  project_id: string;
  title: string;
  detail: string;
  kind: CollabActivityKind;
  status: CollabActivityStatus;
  due_on: string | null;
  created_by: string;
  created_by_username: string;
  created_at: string;
}

interface CollabListResponse {
  projects: CollabProject[];
  canManage: boolean;
}

interface CollabDetailResponse {
  project: CollabProject;
  members: CollabMember[];
  activities: CollabActivity[];
}

async function collabFetch<T>(
  path: string,
  token: string,
  init?: RequestInit
): Promise<T> {
  const res = await fetch(`${BACKEND_URL}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  const data = (await res.json()) as T & { error?: string };
  if (!res.ok) throw new Error(data.error ?? "collab_request_failed");
  return data;
}

/** Lists only projects the caller is invited to; moderators see every project. */
export function fetchCollabProjects(token: string): Promise<CollabListResponse> {
  return collabFetch<CollabListResponse>("/collabs", token);
}

export function fetchCollabDetail(token: string, projectId: string): Promise<CollabDetailResponse> {
  return collabFetch<CollabDetailResponse>(`/collabs/detail?projectId=${encodeURIComponent(projectId)}`, token);
}

export function createCollabProject(
  token: string,
  input: { title: string; summary: string; format: CollabFormat }
): Promise<{ ok: boolean }> {
  return collabFetch<{ ok: boolean }>("/collabs/create", token, {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export function inviteToCollab(
  token: string,
  projectId: string,
  username: string
): Promise<{ ok: boolean }> {
  return collabFetch<{ ok: boolean }>("/collabs/invite", token, {
    method: "POST",
    body: JSON.stringify({ projectId, username }),
  });
}

export function addCollabActivity(
  token: string,
  input: {
    projectId: string;
    title: string;
    detail: string;
    kind: CollabActivityKind;
    dueOn: string | null;
  }
): Promise<{ ok: boolean }> {
  return collabFetch<{ ok: boolean }>("/collabs/activity", token, {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export function updateCollabActivityStatus(
  token: string,
  projectId: string,
  activityId: string,
  status: CollabActivityStatus
): Promise<{ ok: boolean }> {
  return collabFetch<{ ok: boolean }>("/collabs/activity/status", token, {
    method: "POST",
    body: JSON.stringify({ projectId, activityId, status }),
  });
}
