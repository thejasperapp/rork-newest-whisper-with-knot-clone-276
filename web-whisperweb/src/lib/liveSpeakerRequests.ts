/**
 * Live room speaker request system.
 *
 * Any user can request to speak. The request includes a role-specific
 * questionnaire (athletes, coaches, creators). Hosts / recruiters can accept
 * or deny the request; on acceptance the user is added to the speakers table
 * and can publish audio/video in the live room.
 */

import { supabase } from "@/lib/supabase";

export type SpeakerRole = "athlete" | "coach" | "creator" | "general";

export type SpeakerRequestStatus = "pending" | "accepted" | "rejected";

export interface SpeakerRequest {
  id: string;
  room_id: string;
  user_id: string;
  desired_role: SpeakerRole;
  answers: Record<string, string>;
  status: SpeakerRequestStatus;
  requested_at: string;
  reviewed_by: string | null;
  reviewed_at: string | null;
}

export const ROLE_QUESTIONS: Record<
  SpeakerRole,
  { label: string; fields: { id: string; label: string; type: "text" | "textarea" | "number"; placeholder?: string; required?: boolean }[] }
> = {
  athlete: {
    label: "Athlete",
    fields: [
      { id: "sport", label: "Primary sport or discipline", type: "text", required: true },
      { id: "experience", label: "Years competing / training", type: "number", required: true },
      { id: "level", label: "Current level (e.g. high school, collegiate, pro, recreational)", type: "text", required: true },
      { id: "goals", label: "What are your athletic goals?", type: "textarea", required: true },
    ],
  },
  coach: {
    label: "Coach",
    fields: [
      { id: "certifications", label: "Certifications or credentials", type: "textarea", required: true },
      { id: "specialty", label: "Specialty or niche", type: "text", required: true },
      { id: "experience", label: "Years coaching", type: "number", required: true },
      { id: "approach", label: "Describe your coaching philosophy", type: "textarea", required: true },
    ],
  },
  creator: {
    label: "Creator",
    fields: [
      { id: "platforms", label: "Primary platforms and handles", type: "textarea", required: true },
      { id: "followers", label: "Approximate follower count", type: "text", required: true },
      { id: "content", label: "What kind of content do you make?", type: "textarea", required: true },
      { id: "goal", label: "What do you want to share in this live?", type: "textarea", required: true },
    ],
  },
  general: {
    label: "General",
    fields: [
      { id: "topic", label: "What topic would you like to speak about?", type: "textarea", required: true },
      { id: "background", label: "What is your background?", type: "textarea", required: true },
    ],
  },
};

export async function createSpeakerRequest(input: {
  roomId: string;
  userId: string;
  desiredRole: SpeakerRole;
  answers: Record<string, string>;
}): Promise<void> {
  const { error } = await supabase.from("whisper_live_speaker_requests").insert({
    room_id: input.roomId,
    user_id: input.userId,
    desired_role: input.desiredRole,
    answers: input.answers,
    status: "pending",
  });
  if (error) throw error;
}

export async function fetchSpeakerRequests(roomId: string): Promise<SpeakerRequest[]> {
  const { data, error } = await supabase
    .from("whisper_live_speaker_requests")
    .select("*")
    .eq("room_id", roomId)
    .order("requested_at", { ascending: false });
  if (error) throw error;
  return (data as SpeakerRequest[] | null) ?? [];
}

export async function decideSpeakerRequest(
  requestId: string,
  decision: "accepted" | "rejected",
  reviewedBy: string
): Promise<void> {
  const { error } = await supabase
    .from("whisper_live_speaker_requests")
    .update({
      status: decision,
      reviewed_by: reviewedBy,
      reviewed_at: new Date().toISOString(),
    })
    .eq("id", requestId);
  if (error) throw error;
}

export async function addSpeakerToRoom(input: {
  roomId: string;
  userId: string;
  isHost?: boolean;
  isCohost?: boolean;
  canVideo?: boolean;
}): Promise<void> {
  const { error } = await supabase.from("whisper_live_room_speakers").insert({
    room_id: input.roomId,
    user_id: input.userId,
    is_host: input.isHost ?? false,
    is_cohost: input.isCohost ?? false,
    can_video: input.canVideo ?? true,
  });
  if (error) throw error;
}

export async function removeSpeaker(roomId: string, userId: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_live_room_speakers")
    .delete()
    .eq("room_id", roomId)
    .eq("user_id", userId);
  if (error) throw error;
}

export function subscribeToSpeakerRequests(
  roomId: string,
  callback: (request: SpeakerRequest) => void
): () => void {
  const channel = supabase
    .channel(`speaker-requests:${roomId}`)
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table: "whisper_live_speaker_requests", filter: `room_id=eq.${roomId}` },
      (payload) => callback(payload.new as SpeakerRequest)
    )
    .subscribe();
  return () => {
    void supabase.removeChannel(channel);
  };
}
