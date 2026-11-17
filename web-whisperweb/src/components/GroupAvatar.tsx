import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { useAuth } from "@/hooks/useAuth";
import type { GroupThread } from "@/lib/groupChats";

/** Native groups use private storage. Never turn their photo into a public URL. */
export function GroupAvatar({ group, size = 44 }: { group: GroupThread; size?: number }) {
  const { user } = useAuth();
  const accountID = user?.id;
  const [photo, setPhoto] = useState<{ key: string; url: string } | null>(null);
  const key = `${user?.id}:${group.id}:${group.avatar_path ?? ""}`;
  useEffect(() => {
    let active = true;
    let url: string | undefined;
    const path = group.avatar_path;
    if (accountID && path?.startsWith(`${group.id.toLowerCase()}/`) && !path.includes("..")) {
      void supabase.storage.from("whisper-group-avatars").download(path).then(({ data, error }) => {
        if (!active || error || !data) return;
        url = URL.createObjectURL(data);
        setPhoto({ key, url });
      }).catch(() => undefined);
    }
    return () => { active = false; if (url) URL.revokeObjectURL(url); };
  }, [key, accountID, group.id, group.avatar_path]);
  return <span role="img" aria-label={`${group.name} group picture`} className="inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full border border-border bg-secondary text-foreground" style={{ width: size, height: size, fontSize: size * .3, fontWeight: 600 }}>
    {photo?.key === key ? <img src={photo.url} alt="" className="h-full w-full object-cover" /> : group.name.split(/\s+/).filter(Boolean).slice(0, 2).map(word => word[0]).join("").toUpperCase()}
  </span>;
}
