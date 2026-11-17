import { useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";

import { ProfileView } from "@/components/ProfileView";
import { ProfileEditor } from "@/components/ProfileEditor";
import { useAuth } from "@/hooks/useAuth";

export default function Profile() {
  const { profile } = useAuth();
  const [searchParams, setSearchParams] = useSearchParams();
  const [editing, setEditing] = useState<boolean>(false);

  // Settings → "Edit profile" deep-links here with ?edit=1 (mirrors the iOS
  // settings row that opens the profile editor sheet).
  useEffect(() => {
    if (searchParams.get("edit") === "1") {
      setEditing(true);
      setSearchParams({}, { replace: true });
    }
  }, [searchParams, setSearchParams]);

  // No profile row yet → force onboarding editor.
  if (!profile || editing) {
    return (
      <ProfileEditor
        existing={profile}
        onDone={() => setEditing(false)}
        isOnboarding={!profile}
      />
    );
  }

  return <ProfileView profile={profile} isMe onEdit={() => setEditing(true)} />;
}
