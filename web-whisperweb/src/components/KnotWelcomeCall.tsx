import { useCallback, useEffect, useRef, useState } from 'react';
import { useLocation } from 'react-router-dom';
import { Mic, MicOff, Phone, PhoneOff } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import { useMeetingHost } from '@/hooks/useMeetingHost';
import { Dialog, DialogContent, DialogDescription, DialogTitle } from '@/components/ui/dialog';
import { KnotPortrait } from '@/components/Knot';
import { KnotVoiceSession } from '@/lib/knotVoiceSession';
import { welcomeRequest, welcomeDeviceID, welcomeConsent, validWelcome, humanCallIsIncoming, humanCallChanged, type KnotWelcomeInvitation } from '@/lib/knotWelcome';
import { supabase } from '@/lib/supabase';
import { consentChanged } from '@/lib/knotService';
import { ACTIVE_PORTAL, MEET_PORTAL } from '@/lib/portal';

const memberRoutes = new Set(['/', '/messages', '/ember', '/search', '/profile', '/reels', '/settings', '/notifications', '/communities', '/saved', '/notebook', '/calendar']);
export function KnotWelcomeCall() {
  const { user, profile, loading, profileError } = useAuth();
  const { active } = useMeetingHost();
  const { pathname } = useLocation();
  if (!user) return null;
  const ready = !loading && !profileError && !!profile?.username && profile.user_id === user.id && !active && !ACTIVE_PORTAL && !MEET_PORTAL && memberRoutes.has(pathname);
  return <WelcomeForAccount key={user.id} owner={user.id} ready={ready} route={pathname} displayName={profile?.user_id === user.id ? profile.display_name ?? '' : ''} />;
}
function WelcomeForAccount({ owner, ready, route, displayName }: { owner: string; ready: boolean; route: string; displayName: string }) {
  const [invitation, setInvitation] = useState<KnotWelcomeInvitation | null>(null);
  const [phase, setPhase] = useState<'invited' | 'connecting' | 'live' | 'error'>('invited');
  const [muted, setMuted] = useState(false);
  const [speaking, setSpeaking] = useState(false);
  const [line, setLine] = useState('');
  const attempted = useRef(false), answered = useRef(false), alive = useRef(true);
  const deviceID = useRef(welcomeDeviceID());
  const controller = useRef(new AbortController());
  const sessionRef = useRef<KnotVoiceSession | null>(null);
  const invitationRef = useRef(invitation); invitationRef.current = invitation;
  const readyRef = useRef(ready); readyRef.current = ready;
  const nameRef = useRef(displayName); nameRef.current = displayName;
  const close = useCallback(() => {
    controller.current.abort();
    // Losing focus before any offer is not a delivered/missed invitation.
    if (!attempted.current) controller.current = new AbortController();
    const session = sessionRef.current; sessionRef.current = null; session?.close();
    if (alive.current) { setInvitation(null); setLine(''); setSpeaking(false); }
  }, []);
  const decline = useCallback(() => {
    const invite = invitationRef.current;
    close();
    if (invite && !answered.current) {
      // Best effort only; server dedup already prevents another invitation.
      void welcomeRequest(owner, 'knot/background/welcome/decline', { invitationID: invite.id, deviceID: deviceID.current }, new AbortController().signal).catch(() => undefined);
    }
  }, [close, owner]);
  useEffect(() => {
    alive.current = true;
    if (!attempted.current) controller.current = new AbortController();
    const auth = supabase.auth.onAuthStateChange((_event, next) => { if (next?.user.id !== owner) { attempted.current = true; close(); } });
    const hidden = () => { if (document.hidden) close(); };
    const human = () => { if (humanCallIsIncoming()) close(); };
    const storage = (event: StorageEvent) => { if (!event.key || event.key.startsWith('knot_ai_consent_v3:' + owner.toLowerCase())) close(); };
    document.addEventListener('visibilitychange', hidden);
    window.addEventListener('pagehide', close);
    window.addEventListener(humanCallChanged, human);
    window.addEventListener(consentChanged, close);
    window.addEventListener('storage', storage);
    return () => {
      alive.current = false; close(); auth.data.subscription.unsubscribe();
      document.removeEventListener('visibilitychange', hidden); window.removeEventListener('pagehide', close);
      window.removeEventListener(humanCallChanged, human); window.removeEventListener(consentChanged, close); window.removeEventListener('storage', storage);
    };
  }, [owner, close]);
  useEffect(() => { if (!ready && attempted.current) close(); }, [ready, close]);
  useEffect(() => { return () => { if (attempted.current) close(); }; }, [route, close]);
  useEffect(() => {
    if (!ready || attempted.current || controller.current.signal.aborted) return;
    const attempt = () => {
      if (attempted.current || !readyRef.current || document.hidden || !document.hasFocus() || humanCallIsIncoming() || KnotVoiceSession.isBusy || document.querySelector('[role="dialog"], [role="alertdialog"]')) return;
      attempted.current = true;
      void welcomeRequest<{ invitation?: unknown }>(owner, 'knot/background/welcome', { deviceID: deviceID.current, platform: 'web' }, controller.current.signal).then(result => {
        if (!alive.current || !readyRef.current || controller.current.signal.aborted || humanCallIsIncoming() || KnotVoiceSession.isBusy || document.querySelector('[role="dialog"], [role="alertdialog"]') || !validWelcome(result.invitation)) return;
        setInvitation(result.invitation);
      }).catch(() => undefined);
    };
    const initial = window.setTimeout(attempt, 3000), timer = window.setInterval(attempt, 10000);
    return () => { window.clearTimeout(initial); window.clearInterval(timer); };
  }, [owner, ready]);
  useEffect(() => {
    if (!invitation || answered.current) return;
    const timer = window.setTimeout(close, Math.max(0, invitation.expiresAt - Date.now()));
    return () => window.clearTimeout(timer);
  }, [invitation, phase, close]);
  useEffect(() => {
    if (phase !== 'live') return;
    const timer = window.setTimeout(close, 20 * 60 * 1000);
    return () => window.clearTimeout(timer);
  }, [phase, close]);
  const answer = async () => {
    if (!invitation || answered.current || !readyRef.current || document.hidden || invitation.expiresAt <= Date.now() || humanCallIsIncoming() || KnotVoiceSession.isBusy) return;
    answered.current = true; setPhase('connecting');
    const answerID = crypto.randomUUID();
    try {
      const acknowledgement = await welcomeRequest<{ ok: boolean; expiresAt: number }>(owner, 'knot/background/welcome/answer', { invitationID: invitation.id, deviceID: deviceID.current, answerID, consentVersion: welcomeConsent }, controller.current.signal);
      if (!acknowledgement.ok || !Number.isFinite(acknowledgement.expiresAt) || acknowledgement.expiresAt <= Date.now() || !readyRef.current || controller.current.signal.aborted || humanCallIsIncoming() || KnotVoiceSession.isBusy) throw new Error('Invitation ended');
      const session = new KnotVoiceSession({ owner, signal: controller.current.signal,
        welcome: { welcomeID: invitation.id, deviceID: deviceID.current, answerID, welcomeConsentVersion: welcomeConsent, displayName: nameRef.current.trim().split(/\s+/)[0].slice(0, 80) },
        callbacks: {
          onState: state => {
            if (sessionRef.current !== session) return;
            if (state === 'error' || state === 'closed') { sessionRef.current = null; session.close(); setPhase('error'); }
          },
          onSpeaking: value => { if (sessionRef.current === session) setSpeaking(value); },
          onAssistantDone: value => { if (sessionRef.current === session) setLine(value.slice(-1200)); },
        },
      });
      sessionRef.current = session;
      await session.connect();
      if (!alive.current || !readyRef.current || document.hidden || controller.current.signal.aborted || humanCallIsIncoming() || sessionRef.current !== session) { session.close(); return; }
      setPhase('live');
    } catch {
      const session = sessionRef.current; sessionRef.current = null; session?.close();
      if (alive.current && !controller.current.signal.aborted) setPhase('error');
    }
  };
  return <Dialog open={!!invitation} onOpenChange={open => { if (!open) decline(); }}>
    <DialogContent className="h-dvh max-h-dvh w-screen max-w-none overflow-y-auto rounded-none border-0 bg-zinc-950 p-0 text-white sm:rounded-none" aria-describedby="knot-welcome-description">
      <div className="pointer-events-none absolute inset-0 overflow-hidden opacity-30" aria-hidden><div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 blur-3xl"><KnotPortrait size={700} /></div></div>
      <div className="relative mx-auto flex min-h-dvh w-full max-w-lg flex-col items-center gap-6 px-7 py-12 text-center">
        <p className="text-sm text-white/65">Whisper Audio · AI {phase === 'invited' ? 'invitation' : 'call'}</p>
        <div className="flex flex-1 flex-col items-center justify-center gap-6 py-8">
          <KnotPortrait size={128} expression={speaking ? 'happy' : 'calm'} />
          <DialogTitle className="text-3xl font-semibold">{phase === 'invited' ? 'Knot is calling' : 'Knot'}</DialogTitle>
          <DialogDescription id="knot-welcome-description" className="text-lg text-white/85">{phase === 'invited' ? 'A quick hello, just for you.' : phase === 'connecting' ? 'Connecting your welcome call…' : phase === 'error' ? 'This welcome call couldn’t connect.' : speaking ? 'Knot is speaking' : muted ? 'Your microphone is muted' : 'Listening — take your time.'}</DialogDescription>
          {phase === 'error' ? <p className="text-sm text-white/70">Check your microphone permission and connection. You can find Knot in Messages; we won’t call again automatically.</p> : phase === 'invited' ? <p className="max-w-sm text-sm leading-relaxed text-white/70">Meet your AI personal assistant, and talk about what would make your day a little easier.</p> : line ? <p className="max-w-sm text-sm leading-relaxed text-white/80" aria-live="polite">{line}</p> : null}
        </div>
        <div className="flex items-center justify-center gap-16">
          {phase === 'invited' ? <><CallControl label="Decline" icon={<PhoneOff />} color="bg-red-500" onClick={decline} /><CallControl label="Answer" icon={<Phone />} color="bg-emerald-500" onClick={() => void answer()} /></> : <>
            {phase === 'live' && <CallControl label={muted ? 'Unmute' : 'Mute'} icon={muted ? <MicOff /> : <Mic />} color="bg-white/15" onClick={() => { sessionRef.current?.setMicEnabled(muted); setMuted(!muted); }} />}
            <CallControl label={phase === 'error' ? 'Done' : 'End'} icon={<PhoneOff />} color="bg-red-500" onClick={close} />
          </>}
        </div>
        {phase === 'invited' && <div className="space-y-3 text-xs leading-relaxed text-white/65"><p>By answering, you agree to share your first name and live audio with ElevenLabs for speech, and call text through Whisper and Rork AI Cloud (via Vercel AI Gateway) to OpenAI, using Knot’s shared chat model. No profile or chat history is shared. The transcript is shown here only, not saved to your text chat. Audio recording is off and provider conversation history expires after one day; other provider processing and retention follow their policies.</p><p className="font-medium text-white/80">No microphone before Answer. No permission for future calls.</p></div>}
      </div>
    </DialogContent>
  </Dialog>;
}
function CallControl({ label, icon, color, onClick }: { label: string; icon: React.ReactNode; color: string; onClick: () => void }) {
  return <div className="flex flex-col items-center gap-3"><button type="button" aria-label={label} onClick={onClick} className={`flex h-16 w-16 items-center justify-center rounded-full text-white transition-transform active:scale-95 ${color}`}>{icon}</button><span className="text-xs">{label}</span></div>;
}
