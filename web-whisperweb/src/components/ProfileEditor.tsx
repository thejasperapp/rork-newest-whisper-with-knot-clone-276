import { useRef, useState } from "react";
import { Camera } from "lucide-react";

import { Avatar } from "@/components/Avatar";
import { AvatarCropDialog } from "@/components/AvatarCropDialog";
import { upsertProfile, uploadMedia } from "@/lib/api";
import { useAuth } from "@/hooks/useAuth";
import type { WhisperProfile } from "@/lib/types";

interface ProfileEditorProps {
  existing: WhisperProfile | null;
  onDone: () => void;
  isOnboarding: boolean;
}

export function ProfileEditor({
  existing,
  onDone,
  isOnboarding,
}: ProfileEditorProps) {
  const { user, refreshProfile } = useAuth();
  const fileRef = useRef<HTMLInputElement>(null);

  const [username, setUsername] = useState<string>(existing?.username ?? "");
  const [displayName, setDisplayName] = useState<string>(
    existing?.display_name ?? ""
  );
  const [bio, setBio] = useState<string>(existing?.bio ?? "");
  const [avatarUrl, setAvatarUrl] = useState<string | null>(
    existing?.profile_image_url ?? null
  );
  const [busy, setBusy] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  // The picked file goes through the crop dialog before it ever uploads —
  // Instagram grammar: frame the face first, then save.
  const [cropFile, setCropFile] = useState<File | null>(null);
  const [uploadingAvatar, setUploadingAvatar] = useState<boolean>(false);

  const handlePick = (e: React.ChangeEvent<HTMLInputElement>): void => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !user) return;
    setCropFile(file);
  };

  const handleCropped = async (blob: Blob): Promise<void> => {
    if (!user) return;
    setUploadingAvatar(true);
    try {
      const cropped = new File([blob], "avatar.jpg", { type: "image/jpeg" });
      const url = await uploadMedia(cropped, user.id);
      setAvatarUrl(url);
      setCropFile(null);
    } catch {
      setError("Couldn't upload that image.");
    } finally {
      setUploadingAvatar(false);
    }
  };

  const save = async (e: React.FormEvent): Promise<void> => {
    e.preventDefault();
    if (!user) return;
    const handle = username.trim().replace(/^@/, "").toLowerCase();
    if (!handle) {
      setError("Pick a username.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await upsertProfile({
        userId: user.id,
        username: handle,
        displayName: displayName.trim() || handle,
        bio: bio.trim(),
        profileImageUrl: avatarUrl,
      });
      await refreshProfile();
      onDone();
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Couldn't save your profile."
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <div>
      <header className="glass sticky top-0 z-30 flex h-14 items-center justify-between rounded-b-[22px] border-b border-border px-4">
        <h1 className="font-display text-xl font-extrabold">
          {isOnboarding ? "Set up profile" : "Edit profile"}
        </h1>
      </header>

      <form onSubmit={save} className="space-y-5 px-4 py-6">
        <div className="flex flex-col items-center gap-3">
          <button
            type="button"
            onClick={() => fileRef.current?.click()}
            className="relative"
          >
            <Avatar url={avatarUrl} name={username || "you"} size={92} />
            <span className="absolute -bottom-1 -right-1 flex h-8 w-8 items-center justify-center rounded-full border-2 border-background bg-primary text-primary-foreground">
              <Camera className="h-4 w-4" />
            </span>
          </button>
          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={handlePick}
          />
        </div>

        <AvatarCropDialog
          file={cropFile}
          busy={uploadingAvatar}
          onCancel={() => setCropFile(null)}
          onCropped={(blob) => void handleCropped(blob)}
        />

        <div>
          <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">
            Username
          </label>
          <input
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="username"
            className="w-full rounded-2xl border border-border bg-card px-4 py-3 text-[15px] outline-none ring-primary/50 focus:ring-2"
          />
        </div>

        <div>
          <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">
            Display name
          </label>
          <input
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            placeholder="Your name"
            className="w-full rounded-2xl border border-border bg-card px-4 py-3 text-[15px] outline-none ring-primary/50 focus:ring-2"
          />
        </div>

        <div>
          <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">
            Bio
          </label>
          <textarea
            value={bio}
            onChange={(e) => setBio(e.target.value)}
            placeholder="Tell people about yourself"
            rows={3}
            className="w-full resize-none rounded-2xl border border-border bg-card px-4 py-3 text-[15px] outline-none ring-primary/50 focus:ring-2"
          />
        </div>

        {error && (
          <p className="rounded-xl bg-destructive/15 px-3 py-2 text-sm text-destructive">
            {error}
          </p>
        )}

        <div className="flex gap-2">
          {!isOnboarding && (
            <button
              type="button"
              onClick={onDone}
              className="flex-1 rounded-2xl bg-secondary py-3 text-sm font-semibold"
            >
              Cancel
            </button>
          )}
          <button
            type="submit"
            disabled={busy}
            className="flex-1 rounded-2xl bg-primary py-3 text-sm font-semibold text-primary-foreground disabled:opacity-60"
          >
            {busy ? "Saving…" : "Save"}
          </button>
        </div>
      </form>
    </div>
  );
}
