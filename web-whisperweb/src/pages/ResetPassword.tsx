import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { ArrowLeft, CheckCircle2, LockKeyhole } from "lucide-react";

import { supabase } from "@/lib/supabase";
import { WhisperLogo } from "@/components/WhisperLogo";

/**
 * Landing page for the branded password-reset email. The recovery link signs
 * the user in with a short-lived session (detectSessionInUrl), and this page
 * lets them choose a new password via supabase.auth.updateUser.
 */
export default function ResetPassword() {
  const navigate = useNavigate();
  const [password, setPassword] = useState<string>("");
  const [confirm, setConfirm] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<boolean>(false);
  const [done, setDone] = useState<boolean>(false);
  const [hasSession, setHasSession] = useState<boolean | null>(null);

  useEffect(() => {
    // The recovery hash may still be getting exchanged when we mount — give
    // supabase-js a beat, then check for the recovery session.
    let cancelled = false;
    const check = async (): Promise<void> => {
      // Branded reset emails link here with ?token_hash=… so the link never
      // routes through Supabase's redirect (which used to dump users on
      // localhost). Exchange it for a session directly.
      const params = new URLSearchParams(window.location.search);
      const tokenHash = params.get("token_hash");
      if (tokenHash) {
        const { error: otpError } = await supabase.auth.verifyOtp({
          type: "recovery",
          token_hash: tokenHash,
        });
        if (!cancelled && !otpError) {
          setHasSession(true);
          return;
        }
      }
      const { data } = await supabase.auth.getSession();
      if (!cancelled && data.session) {
        setHasSession(true);
        return;
      }
      // Retry once after the URL exchange settles.
      await new Promise((r) => setTimeout(r, 900));
      const { data: retry } = await supabase.auth.getSession();
      if (!cancelled) setHasSession(Boolean(retry.session));
    };
    void check();
    const { data: sub } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY" || event === "SIGNED_IN") {
        setHasSession(true);
      }
    });
    return () => {
      cancelled = true;
      sub.subscription.unsubscribe();
    };
  }, []);

  const submit = async (e: React.FormEvent): Promise<void> => {
    e.preventDefault();
    setError(null);
    if (password.length < 6) {
      setError("Password must be at least 6 characters.");
      return;
    }
    if (password !== confirm) {
      setError("Passwords don't match.");
      return;
    }
    setBusy(true);
    try {
      const { error: err } = await supabase.auth.updateUser({ password });
      if (err) throw err;
      setDone(true);
      setTimeout(() => navigate("/"), 1600);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center px-6">
      <Link
        to="/welcome"
        className="absolute left-4 top-4 flex h-10 w-10 items-center justify-center rounded-full bg-secondary text-foreground transition-colors hover:bg-secondary/80"
        aria-label="Back to home"
      >
        <ArrowLeft className="h-5 w-5" />
      </Link>
      <div className="w-full max-w-sm animate-rise">
        <div className="mb-8 flex flex-col items-center gap-5 text-center">
          <WhisperLogo size={56} />
          <div>
            <h1 className="text-lg font-bold">Choose a new password</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Pick something at least 6 characters long.
            </p>
          </div>
        </div>

        {done ? (
          <div className="flex flex-col items-center gap-3 rounded-2xl border border-border bg-card px-6 py-8 text-center">
            <CheckCircle2 className="h-8 w-8 text-green-600" />
            <p className="text-sm font-semibold">Password updated</p>
            <p className="text-sm text-muted-foreground">
              You're signed in — taking you to your feed…
            </p>
          </div>
        ) : hasSession === false ? (
          <div className="flex flex-col items-center gap-3 rounded-2xl border border-border bg-card px-6 py-8 text-center">
            <LockKeyhole className="h-8 w-8 text-muted-foreground" />
            <p className="text-sm font-semibold">This reset link has expired</p>
            <p className="text-sm text-muted-foreground">
              Reset links only work once and expire after an hour. Request a
              fresh one from the sign-in page.
            </p>
            <Link
              to="/auth"
              className="mt-2 rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-primary-foreground"
            >
              Back to sign in
            </Link>
          </div>
        ) : (
          <form onSubmit={submit} className="space-y-3">
            <input
              type="password"
              required
              minLength={6}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="New password"
              autoComplete="new-password"
              className="w-full rounded-2xl border border-border bg-card px-4 py-3.5 text-[15px] outline-none focus:border-foreground/40"
            />
            <input
              type="password"
              required
              minLength={6}
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              placeholder="Confirm new password"
              autoComplete="new-password"
              className="w-full rounded-2xl border border-border bg-card px-4 py-3.5 text-[15px] outline-none focus:border-foreground/40"
            />

            {error && (
              <p className="rounded-xl bg-destructive/15 px-3 py-2 text-sm text-destructive">
                {error}
              </p>
            )}

            <button
              type="submit"
              disabled={busy || hasSession !== true}
              className="w-full rounded-2xl bg-primary py-3.5 text-[15px] font-semibold text-primary-foreground transition-opacity disabled:opacity-60"
            >
              {busy
                ? "Updating…"
                : hasSession === null
                  ? "Checking your link…"
                  : "Update password"}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
