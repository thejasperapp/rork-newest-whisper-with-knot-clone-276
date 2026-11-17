import { createContext, useContext, useCallback, useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import type { Session, User } from "@supabase/supabase-js";
import { useQueryClient } from "@tanstack/react-query";

import { supabase } from "@/lib/supabase";
import { setMessageCacheOwner } from "@/lib/messageCache";
import { setJasperAudience } from "@/lib/ember";
import { forgetCurrentOnSignOut, rememberSession } from "@/lib/accountSwitcher";
import type { WhisperProfile } from "@/lib/types";

interface AuthContextValue {
  session: Session | null;
  user: User | null;
  profile: WhisperProfile | null;
  loading: boolean;
  profileError: string | null;
  refreshProfile: () => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<WhisperProfile | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [profileError, setProfileError] = useState<string | null>(null);

  const liveSession = useRef<Session | null>(null);
  const generation = useRef<number>(0);
  const profileRequest = useRef<number>(0);
  const loadProfile = useCallback(async (userId: string): Promise<void> => {
    const version = generation.current, request = ++profileRequest.current;
    const isCurrent = () => version === generation.current && request === profileRequest.current && liveSession.current?.user.id === userId;
    try {
    const { data, error } = await supabase
      .from("whisper_profiles")
      .select("*")
      .eq("user_id", userId)
      .limit(1)
      .maybeSingle();
    if (!isCurrent()) return;
    if (error) throw error;
    const p = (data as WhisperProfile | null) ?? null;
    if (p && p.user_id !== userId) throw new Error("Profile owner changed");
    setProfileError(null);
    setProfile(p);
    rememberSession(liveSession.current, p);
    // Jasper adapts to who he's talking to — account type + roles.
    setJasperAudience(
      p
        ? {
            username: p.username,
            accountType: p.account_type ?? null,
            isCoach: !!p.is_coach,
            isAthlete: !!p.is_athlete,
            isVerified: !!p.is_verified,
            isRecruiter: !!p.is_recruiter,
          }
        : null
    );
    } catch {
      if (isCurrent()) setProfileError("Your profile couldn’t load just now. Please try again.");
    }
  }, []);

  useEffect(() => {
    let active = true;
    const adopt = (next: Session | null): void => {
      const changed = liveSession.current?.user.id !== next?.user.id;
      generation.current++;
      const version = generation.current;
      liveSession.current = next;
      setMessageCacheOwner(next?.user.id ?? null);
      // Cancel and destroy outgoing account queries before the next account
      // renders, including older keys that predate explicit owner scoping.
      // Removing queries also prevents late responses restoring their cache.
      if (changed || !next) {
        void queryClient.cancelQueries();
        queryClient.clear();
      }
      setSession(next);
      if (changed || !next) { setProfile(null); setProfileError(null); setJasperAudience(null); }
      if (!next) { setLoading(false); return; }
      if (changed) setLoading(true);
      // Never await auth work from inside Supabase's synchronous auth callback.
      queueMicrotask(() => {
        if (!active || version !== generation.current) return;
        void loadProfile(next.user.id).catch(() => { /* Leave the cleared profile unresolved, never adopt another account. */ }).finally(() => { if (active && version === generation.current) setLoading(false); });
      });
    };
    const initialGeneration = generation.current;
    void supabase.auth.getSession().then(({ data }) => { if (active && generation.current === initialGeneration) adopt(data.session); }).catch(() => { if (active && generation.current === initialGeneration) setLoading(false); });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => { if (active) adopt(next); });
    return () => { active = false; generation.current++; sub.subscription.unsubscribe(); };
  }, [loadProfile, queryClient]);

  const refreshProfile = async (): Promise<void> => {
    if (session?.user) await loadProfile(session.user.id);
  };

  const signOut = async (): Promise<void> => {
    // A real sign-out revokes the session — the switcher must forget it too.
    forgetCurrentOnSignOut(session?.user?.id);
    setMessageCacheOwner(null);
    await supabase.auth.signOut();
    setProfile(null);
    setJasperAudience(null);
  };

  const value: AuthContextValue = {
    session,
    user: session?.user ?? null,
    profile,
    loading,
    profileError,
    refreshProfile,
    signOut,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}
