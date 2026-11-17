export interface WhisperProfile {
  user_id: string;
  username: string;
  display_name: string | null;
  bio: string | null;
  interests: string[] | null;
  profile_image_url: string | null;
  is_private: boolean | null;
  /** Instagram-style account split — personal | creator | business (account-types.sql). */
  account_type?: string | null;
  professional_category?: string | null;
  contact_email?: string | null;
  contact_phone?: string | null;
  is_verified?: boolean | null;
  /** Team checkmark tiers — columns on whisper_profiles (account-status.sql). */
  is_moderator?: boolean | null;
  is_admin?: boolean | null;
  is_owner?: boolean | null;
  is_coach?: boolean | null;
  is_athlete?: boolean | null;
  is_recruiter?: boolean | null;
  /** Whisper media team member — wears the Director badge. */
  is_director?: boolean | null;
  /** Whisper blogger — dedicated writer role for articles & film reviews. */
  is_blogger?: boolean | null;
  is_liar?: boolean | null;
  liar_reason?: string | null;
  /** Whisper One membership (set by the Stripe webhook). */
  is_one?: boolean | null;
  one_plan?: string | null;
  /** Whisper Plus — the Jasper Intelligence pro pack (supabase/whisper-plus.sql). */
  is_plus?: boolean | null;
}

/** Active "Liar Liar" badge state for a username (mirrors iOS `whisper_liar_badges`). */
export interface WhisperLiarBadge {
  username: string;
  reason: string | null;
  strike_count: number | null;
  acknowledged_at: string | null;
  appeal_status: string | null;
  /** True when sourced from a manual profiles.is_liar flag. */
  manualOverride?: boolean;
}

export interface WhisperPost {
  id: string;
  user_id: string;
  username: string | null;
  kind: string | null;
  caption: string;
  symbol: string | null;
  accent_hex: string | null;
  media_count: number | null;
  media_urls: string[] | null;
  is_ghost: boolean | null;
  is_reel: boolean | null;
  likes_count: number | null;
  comments_count: number | null;
  created_at: string | null;
  /** Community this post was explicitly filed into (picker, not hashtag). */
  community_id?: string | null;
  /** Display name of that community at post time (no # — shown as-is). */
  community_name?: string | null;
}

export interface WhisperComment {
  id: string;
  post_id: string;
  user_id: string;
  username: string;
  body: string;
  created_at: string | null;
  parent_comment_id: string | null;
  likes_count: number | null;
}

export interface WhisperStory {
  id: string;
  user_id: string;
  username: string;
  image_url: string;
  caption: string | null;
  created_at: string | null;
  expires_at: string | null;
  /** JSON-encoded WhisperStoryMetadata (interactive sticker overlays). */
  metadata: string | null;
  /** 30s preview URL for the attached song, if any. */
  music_url: string | null;
  music_title: string | null;
  music_artist: string | null;
  music_artwork: string | null;
  /** Round 77 — video stories: the clip; `image_url` stays the poster. */
  video_url?: string | null;
}

export interface WhisperMessage {
  id: string;
  logical_group_message_id?: string | null;
  thread_id?: string | null;
  embed?: unknown;
  from_user_id: string;
  from_username: string | null;
  to_user_id: string;
  to_username: string | null;
  body: string;
  created_at: string | null;
  read_at: string | null;
}

/** A user surfaced in a followers/following list or suggestions row. */
export interface WhisperFollowUser {
  userId: string;
  username: string;
  profile: WhisperProfile | null;
}

/** A single derived activity event for the Notifications feed. */
export interface WhisperActivity {
  id: string;
  kind: "like" | "comment" | "repost" | "follow";
  actorUserId: string;
  actorUsername: string;
  actorProfile: WhisperProfile | null;
  postId: string | null;
  /** Short preview text (comment body, post caption, etc.). */
  preview: string | null;
  createdAt: string | null;
}

/** A post enriched with its live engagement counts. */
export interface WhisperPostStat {
  post: WhisperPost;
  likes: number;
  comments: number;
  reposts: number;
}

/** Aggregate creator analytics across all of a user's posts. */
export interface WhisperCreatorStats {
  posts: number;
  likes: number;
  comments: number;
  reposts: number;
  followers: number;
  topPosts: WhisperPostStat[];
  /** Every post enriched with engagement counts (for algorithm ranking). */
  entries: WhisperPostStat[];
}

export interface WhisperConversation {
  kind?: "direct" | "dating";
  threadId?: string | null;
  otherUserId: string;
  otherUsername: string;
  otherProfile: WhisperProfile | null;
  lastMessage: string;
  lastDate: string | null;
  lastFromMe: boolean;
  unread: number;
  messages: WhisperMessage[];
}
