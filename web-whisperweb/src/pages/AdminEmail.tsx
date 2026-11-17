import { useRef, useState } from "react";
import {
  Loader2,
  Mail,
  Send,
  Eye,
  FlaskConical,
  Paperclip,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { BACKEND_URL } from "@/lib/billing";

interface BroadcastPreview {
  html: string;
  recipientCount: number | null;
}

interface EmailAttachment {
  filename: string;
  /** Base64-encoded file content. */
  content: string;
  /** Original size in bytes, for the UI only. */
  size: number;
}

const MAX_ATTACHMENTS = 5;
const MAX_TOTAL_BYTES = 15 * 1024 * 1024;

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function readFileAsBase64(file: File): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      resolve(result.slice(result.indexOf(",") + 1));
    };
    reader.onerror = () => reject(new Error(`Couldn't read ${file.name}`));
    reader.readAsDataURL(file);
  });
}

interface BroadcastResult {
  ok?: boolean;
  sent?: number;
  failed?: number;
  error?: string;
}

interface BroadcastPayload {
  mode?: string;
  subject: string;
  headline: string;
  message: string;
  buttonLabel: string;
  buttonUrl: string;
  testEmail?: string;
  attachments?: { filename: string; content: string }[];
}

async function callBroadcast(
  key: string,
  body: BroadcastPayload
): Promise<BroadcastResult & BroadcastPreview> {
  const res = await fetch(`${BACKEND_URL}/admin/broadcast`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify(body),
  });
  const data = (await res.json()) as BroadcastResult & BroadcastPreview;
  if (!res.ok) {
    const messages: Record<string, string> = {
      unauthorized: "That broadcast key is wrong.",
      broadcast_not_configured:
        "The broadcast key isn't set up on the backend yet.",
      resend_not_configured: "Resend isn't connected on the backend.",
      subject_and_message_required: "Add a subject and a message first.",
      test_email_required: "Enter a valid test email address.",
      user_list_failed: "Couldn't load the user list from Supabase.",
    };
    throw new Error(messages[data.error ?? ""] ?? "Something went wrong.");
  }
  return data;
}

/**
 * Hidden admin tool (not linked anywhere in the UI): compose a branded email,
 * preview it, send yourself a test, then broadcast to every Whisper user.
 * Protected by the BROADCAST_SECRET on the backend.
 */
export default function AdminEmail() {
  const [key, setKey] = useState<string>("");
  const [subject, setSubject] = useState<string>("");
  const [headline, setHeadline] = useState<string>("");
  const [message, setMessage] = useState<string>("");
  const [buttonLabel, setButtonLabel] = useState<string>("");
  const [buttonUrl, setButtonUrl] = useState<string>("");
  const [testEmail, setTestEmail] = useState<string>("");
  const [attachments, setAttachments] = useState<EmailAttachment[]>([]);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [previewHtml, setPreviewHtml] = useState<string>("");
  const [recipientCount, setRecipientCount] = useState<number | null>(null);
  const [busy, setBusy] = useState<"preview" | "test" | "send" | null>(null);

  const payload: BroadcastPayload = {
    subject,
    headline,
    message,
    buttonLabel,
    buttonUrl,
    attachments: attachments.map(({ filename, content }) => ({
      filename,
      content,
    })),
  };

  const handleFiles = async (files: FileList | null) => {
    if (!files || files.length === 0) return;
    const current = [...attachments];
    let total = current.reduce((sum, a) => sum + a.size, 0);
    for (const file of Array.from(files)) {
      if (current.length >= MAX_ATTACHMENTS) {
        toast.error(`Max ${MAX_ATTACHMENTS} attachments.`);
        break;
      }
      if (total + file.size > MAX_TOTAL_BYTES) {
        toast.error("Attachments can total 15 MB max.");
        break;
      }
      try {
        const content = await readFileAsBase64(file);
        current.push({ filename: file.name, content, size: file.size });
        total += file.size;
      } catch {
        toast.error(`Couldn't read ${file.name}`);
      }
    }
    setAttachments(current);
    if (fileInputRef.current) fileInputRef.current.value = "";
  };

  const handlePreview = async () => {
    setBusy("preview");
    try {
      // Images are embedded inline in the email body, so the preview needs
      // them; other file types are skipped to keep the preview fast.
      const imageExt = /\.(png|jpe?g|gif|webp|bmp|svg)$/i;
      const data = await callBroadcast(key, {
        ...payload,
        attachments: payload.attachments?.filter((a) =>
          imageExt.test(a.filename)
        ),
        mode: "preview",
      });
      setPreviewHtml(data.html);
      setRecipientCount(data.recipientCount);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Preview failed.");
    } finally {
      setBusy(null);
    }
  };

  const handleTest = async () => {
    setBusy("test");
    try {
      await callBroadcast(key, { ...payload, mode: "test", testEmail });
      toast.success(`Test email sent to ${testEmail}`);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Test send failed.");
    } finally {
      setBusy(null);
    }
  };

  const handleSend = async () => {
    setBusy("send");
    try {
      const data = await callBroadcast(key, { ...payload, mode: "send" });
      toast.success(
        `Sent to ${data.sent ?? 0} users${
          data.failed ? ` (${data.failed} failed)` : ""
        }`
      );
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Broadcast failed.");
    } finally {
      setBusy(null);
    }
  };

  const canCompose = subject.trim().length > 0 && message.trim().length > 0;

  return (
    <div className="min-h-screen bg-stone-100 py-10 px-4">
      <div className="mx-auto grid max-w-5xl gap-8 lg:grid-cols-2">
        <div className="space-y-5">
          <div className="flex items-center gap-2">
            <Mail className="h-5 w-5" />
            <h1 className="text-xl font-extrabold tracking-tight">
              Email all Whisper users
            </h1>
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="bkey">Broadcast key</Label>
            <Input
              id="bkey"
              type="password"
              value={key}
              onChange={(e) => setKey(e.target.value)}
              placeholder="Your secret broadcast key"
              autoComplete="off"
            />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="subject">Subject line</Label>
            <Input
              id="subject"
              value={subject}
              onChange={(e) => setSubject(e.target.value)}
              placeholder="e.g. New this week on Whisper"
            />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="headline">Headline (inside the email)</Label>
            <Input
              id="headline"
              value={headline}
              onChange={(e) => setHeadline(e.target.value)}
              placeholder="Defaults to the subject line"
            />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="message">Message</Label>
            <Textarea
              id="message"
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              rows={8}
              placeholder={"Write your message here.\n\nBlank lines start a new paragraph."}
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="btnLabel">Button label (optional)</Label>
              <Input
                id="btnLabel"
                value={buttonLabel}
                onChange={(e) => setButtonLabel(e.target.value)}
                placeholder="Open Whisper"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="btnUrl">Button link</Label>
              <Input
                id="btnUrl"
                value={buttonUrl}
                onChange={(e) => setButtonUrl(e.target.value)}
                placeholder="mydailywhisper.com"
              />
            </div>
          </div>

          <div className="space-y-1.5">
            <Label>Attachments (optional)</Label>
            <input
              ref={fileInputRef}
              type="file"
              multiple
              className="hidden"
              onChange={(e) => void handleFiles(e.target.files)}
            />
            <Button
              type="button"
              variant="outline"
              className="w-full justify-start text-stone-500"
              onClick={() => fileInputRef.current?.click()}
            >
              <Paperclip className="h-4 w-4" />
              Add files ({attachments.length}/{MAX_ATTACHMENTS}, 15 MB total)
            </Button>
            {attachments.length > 0 && (
              <ul className="space-y-1">
                {attachments.map((att, index) => (
                  <li
                    key={`${att.filename}-${index}`}
                    className="flex items-center justify-between rounded-lg border border-stone-200 bg-white px-3 py-1.5 text-sm"
                  >
                    <span className="truncate">
                      {att.filename}{" "}
                      <span className="text-xs text-stone-400">
                        {formatBytes(att.size)}
                      </span>
                    </span>
                    <button
                      type="button"
                      aria-label={`Remove ${att.filename}`}
                      className="ml-2 shrink-0 text-stone-400 hover:text-stone-700"
                      onClick={() =>
                        setAttachments((prev) =>
                          prev.filter((_, i) => i !== index)
                        )
                      }
                    >
                      <X className="h-4 w-4" />
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="flex flex-wrap items-center gap-2 pt-2">
            <Button
              variant="outline"
              onClick={handlePreview}
              disabled={!key || busy !== null}
            >
              {busy === "preview" ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Eye className="h-4 w-4" />
              )}
              Preview
            </Button>

            <div className="flex items-center gap-2">
              <Input
                value={testEmail}
                onChange={(e) => setTestEmail(e.target.value)}
                placeholder="you@example.com"
                className="w-44"
                type="email"
              />
              <Button
                variant="outline"
                onClick={handleTest}
                disabled={!key || !canCompose || !testEmail || busy !== null}
              >
                {busy === "test" ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <FlaskConical className="h-4 w-4" />
                )}
                Send test
              </Button>
            </div>
          </div>

          <AlertDialog>
            <AlertDialogTrigger asChild>
              <Button
                className="w-full"
                disabled={!key || !canCompose || busy !== null}
              >
                {busy === "send" ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Send className="h-4 w-4" />
                )}
                Send to all users
                {recipientCount !== null ? ` (${recipientCount})` : ""}
              </Button>
            </AlertDialogTrigger>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>Send to every user?</AlertDialogTitle>
                <AlertDialogDescription>
                  This emails &ldquo;{subject}&rdquo; to{" "}
                  {recipientCount !== null
                    ? `${recipientCount} users`
                    : "all Whisper users"}
                  . This can&apos;t be undone — send yourself a test first if
                  you haven&apos;t.
                </AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel>Cancel</AlertDialogCancel>
                <AlertDialogAction onClick={handleSend}>
                  Yes, send it
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        </div>

        <div className="space-y-2">
          <p className="text-sm font-semibold text-stone-500">
            Preview
            {recipientCount !== null && (
              <span className="ml-2 rounded-full bg-stone-200 px-2 py-0.5 text-xs font-bold text-stone-700">
                {recipientCount} recipients
              </span>
            )}
          </p>
          {previewHtml ? (
            <iframe
              title="Email preview"
              srcDoc={previewHtml}
              className="h-[640px] w-full rounded-2xl border border-stone-200 bg-white"
              sandbox=""
            />
          ) : (
            <div className="flex h-[640px] w-full items-center justify-center rounded-2xl border border-dashed border-stone-300 text-sm text-stone-400">
              Enter your key and hit Preview
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
