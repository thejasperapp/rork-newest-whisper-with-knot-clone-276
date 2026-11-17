import { useEffect, useState } from "react";
import { Check, ChevronDown, Plus, X } from "lucide-react";
import { toast } from "sonner";

import { Avatar } from "@/components/Avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  MAX_ACCOUNTS,
  beginAddAccount,
  forgetAccount,
  switchToAccount,
  useSwitchableAccounts,
} from "@/lib/accountSwitcher";
import { WHISPER_BRAND_ACCENT } from "@/lib/brand";
import type { WhisperProfile } from "@/lib/types";
import { cn } from "@/lib/utils";

interface AccountSwitcherMenuProps {
  profile: WhisperProfile;
  children: React.ReactNode;
  className?: string;
}

/**
 * The profile header's username → account switcher (Instagram grammar):
 * the current account checked on top, every other saved account beneath
 * (click to switch, × to forget), then "Add Whisper account". Mirrors the
 * iOS sheet on the same saved-session model.
 */
const SWITCHED_KEY = "whisper.accounts.switched";

export function AccountSwitcherMenu({ profile, children, className }: AccountSwitcherMenuProps) {
  const accounts = useSwitchableAccounts();
  const [switching, setSwitching] = useState<string | null>(null);

  const currentId = profile.user_id.toLowerCase();
  const others = accounts.filter((a) => a.userId.toLowerCase() !== currentId);

  // The switch reloads the page (so realtime channels, module caches, and
  // query state can't leak across accounts) — greet the user once it lands.
  useEffect(() => {
    try {
      const name = sessionStorage.getItem(SWITCHED_KEY);
      if (name) {
        sessionStorage.removeItem(SWITCHED_KEY);
        toast.success(`Switched to @${name}`);
      }
    } catch {
      /* ignore */
    }
  }, []);

  const handleSwitch = async (userId: string): Promise<void> => {
    const account = accounts.find((a) => a.userId === userId);
    if (!account || switching) return;
    setSwitching(userId);
    const result = await switchToAccount(account);
    if (result.ok === false) {
      setSwitching(null);
      if (result.needsSignIn) {
        toast.error(result.error, {
          action: {
            label: `Sign in to @${account.username}`,
            onClick: () => {
              void beginAddAccount(account).then(() => {
                window.location.assign("/auth?add=1");
              });
            },
          },
        });
      } else {
        toast.error(result.error);
      }
      return;
    }
    try {
      sessionStorage.setItem(SWITCHED_KEY, account.username);
    } catch {
      /* ignore */
    }
    window.location.assign("/profile");
  };

  const handleAdd = async (): Promise<void> => {
    await beginAddAccount();
    window.location.assign("/auth?add=1");
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        className={cn(
          "flex min-w-0 items-center gap-1 rounded-full px-1 transition-colors hover:bg-secondary/60",
          className
        )}
        aria-label="Switch account"
      >
        {children}
        <ChevronDown className="h-3.5 w-3.5 shrink-0" strokeWidth={2.6} />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="center" className="w-72 p-1.5">
        <div className="flex items-center gap-3 rounded-lg px-2 py-2">
          <Avatar url={profile.profile_image_url} name={profile.username} size={40} />
          <div className="min-w-0 flex-1">
            <p className="truncate text-[14px] font-bold leading-tight">{profile.username}</p>
            <p className="truncate text-[12px] text-muted-foreground">
              {profile.display_name || "Signed in"}
            </p>
          </div>
          <Check className="h-5 w-5 shrink-0" style={{ color: WHISPER_BRAND_ACCENT }} />
        </div>
        {others.length > 0 && <DropdownMenuSeparator />}
        {others.map((a) => (
          <DropdownMenuItem
            key={a.userId}
            onSelect={(e) => {
              e.preventDefault();
              void handleSwitch(a.userId);
            }}
            className="flex items-center gap-3 py-2"
          >
            <Avatar url={a.avatarUrl ?? undefined} name={a.username} size={36} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-[14px] font-semibold leading-tight">{a.username}</p>
              <p className="truncate text-[12px] text-muted-foreground">
                {switching === a.userId ? "Switching…" : a.displayName || a.email || "Tap to switch"}
              </p>
            </div>
            <button
              onClick={(e) => {
                e.stopPropagation();
                e.preventDefault();
                forgetAccount(a.userId);
                toast(`Removed @${a.username} from this browser`);
              }}
              aria-label={`Remove @${a.username} from this browser`}
              className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </DropdownMenuItem>
        ))}
        <DropdownMenuSeparator />
        <DropdownMenuItem
          disabled={accounts.length >= MAX_ACCOUNTS}
          onSelect={(e) => {
            e.preventDefault();
            void handleAdd();
          }}
          className="flex items-center gap-3 py-2"
        >
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-border">
            <Plus className="h-4 w-4" />
          </span>
          <span className="text-[14px] font-semibold">Add Whisper account</span>
        </DropdownMenuItem>
        <p className="px-2 pb-1 pt-1.5 text-[11px] leading-snug text-muted-foreground">
          {accounts.length >= MAX_ACCOUNTS
            ? `You can keep up to ${MAX_ACCOUNTS} accounts in one browser.`
            : "Switch without signing out — logins are remembered on this browser."}
        </p>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
