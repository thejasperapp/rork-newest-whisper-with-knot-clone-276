import { useRef, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { Camera, Loader2, X } from "lucide-react";
import { toast } from "sonner";
import { Avatar } from "@/components/Avatar";
import { uploadMedia } from "@/lib/api";
import { upsertRecruiterGroup, type RecruiterGroup } from "@/lib/recruiter";

interface GroupPhotoUploaderProps {
  group: RecruiterGroup | null | undefined;
  recruiterId: string | undefined;
  onUpdated: () => void;
}

export function GroupPhotoUploader({
  group,
  recruiterId,
  onUpdated,
}: GroupPhotoUploaderProps) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<string | null>(group?.photo_url ?? null);

  const uploadMutation = useMutation({
    mutationFn: async (file: File): Promise<void> => {
      if (!recruiterId) throw new Error("Not signed in");
      const url = await uploadMedia(file, recruiterId);
      await upsertRecruiterGroup(recruiterId, { photo_url: url });
      setPreview(url);
      onUpdated();
      toast("Group photo updated");
    },
    onError: () => toast("Couldn't upload group photo"),
  });

  const removeMutation = useMutation({
    mutationFn: async (): Promise<void> => {
      if (!recruiterId) throw new Error("Not signed in");
      await upsertRecruiterGroup(recruiterId, { photo_url: null });
      setPreview(null);
      onUpdated();
      toast("Group photo removed");
    },
    onError: () => toast("Couldn't remove group photo"),
  });

  const handlePick = (e: React.ChangeEvent<HTMLInputElement>): void => {
    const file = e.target.files?.[0];
    if (!file) return;
    uploadMutation.mutate(file);
  };

  return (
    <div className="flex items-center gap-4">
      <div className="relative">
        <Avatar
          url={preview}
          name={group?.name ?? "Group"}
          size={72}
          className="ring-2 ring-border"
        />
        {preview && (
          <button
            onClick={() => removeMutation.mutate()}
            disabled={removeMutation.isPending}
            className="absolute -right-1 -top-1 flex h-6 w-6 items-center justify-center rounded-full bg-destructive text-destructive-foreground shadow transition-transform active:scale-90 disabled:opacity-50"
          >
            {removeMutation.isPending ? (
              <Loader2 className="h-3 w-3 animate-spin" />
            ) : (
              <X className="h-3 w-3" />
            )}
          </button>
        )}
      </div>
      <div className="min-w-0 flex-1">
        <p className="text-[14px] font-bold">{group?.name ?? "My Recruiting Group"}</p>
        <p className="text-[12px] text-muted-foreground">
          This photo appears on every globe pin for your territories.
        </p>
        <button
          onClick={() => fileRef.current?.click()}
          disabled={uploadMutation.isPending}
          className="mt-2 inline-flex items-center gap-1.5 rounded-full bg-secondary px-3 py-1.5 text-[12px] font-bold transition-colors hover:bg-secondary/80 disabled:opacity-50"
        >
          {uploadMutation.isPending ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <Camera className="h-3.5 w-3.5" />
          )}
          {uploadMutation.isPending ? "Uploading…" : "Upload group photo"}
        </button>
      </div>
      <input
        ref={fileRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={handlePick}
      />
    </div>
  );
}
