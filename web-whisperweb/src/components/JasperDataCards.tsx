import { memo, useEffect, useState, type ReactNode } from "react";
import { Droplets, FlaskConical, Gauge, Hourglass, MoonStar, Sparkles, Minus, Plus } from "lucide-react";

import { EmberGlowCard, EmberGlowIcon, EmberKicker } from "@/components/JasperPlanCards";
import { JasperWaterCup } from "@/components/JasperWaterCup";
import { fetchProfileByUsername } from "@/lib/api";
import type { EmberJasperLook } from "@/lib/emberBrain";
import {
  coachDashboard,
  dashLockedScope,
  dashRows,
  ownDashboard,
  type JasperClientDashboard,
} from "@/lib/jasperCoachConnect";
import { fetchWaterToday, jasperDeleteRow, logWaterCup, type JasperWaterRow } from "@/lib/jasperConnect";

/**
 * Jasper Intelligence's NATIVE data cards — the web render of the ```jasper
 * fenced block: live API-backed looks (readiness ring, sleep hypnogram,
 * bio-age vitality, tap-to-log water cup, PhenoAge blood panel) inside the
 * ember glow box. Mirrors iOS `WhisperEmberJasperLookCards.swift`.
 */

// Jasper's published readiness spec colors (≥75 primed · ≥50 steady · low).
const READY_MINT = "#5CDBB8";
const READY_BLUE = "#3394E0";
const READY_RED = "#F26659";

// Sleep stage colors from the published `sleep` look spec.
const STAGE_COLORS: Record<string, string> = {
  AWAKE: "#FF9500",
  REM: "#32ADE6",
  CORE: "#5856D6",
  DEEP: "#AF52DE",
};

type Row = Record<string, unknown>;

function numAny(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

function strAny(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 ? v : null;
}

function readyColor(score: number): string {
  if (score >= 75) return READY_MINT;
  if (score >= 50) return READY_BLUE;
  return READY_RED;
}

function readyWord(score: number): string {
  if (score >= 75) return "Primed";
  if (score >= 50) return "Steady";
  return "Run down";
}

function fmtDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

const CONNECT_HINT = "Jasper isn't connected — Settings → Sync with Jasper (one tap) turns this card live.";

// MARK: - Shared shell + data hook

function LookShell({
  icon,
  kicker,
  clientName,
  loading,
  children,
}: {
  icon: ReactNode;
  kicker: string;
  clientName: string | null;
  loading: boolean;
  children: ReactNode;
}) {
  return (
    <EmberGlowCard glow={0.5} radius={20} breathing={loading} className="my-1 w-full max-w-[430px] p-3.5">
      <div className="flex items-center gap-2.5">
        <EmberGlowIcon size={34}>{icon}</EmberGlowIcon>
        <div className="min-w-0">
          <EmberKicker text={kicker} />
          <p className="text-[11px] text-muted-foreground">
            {clientName ? `@${clientName} · live from their Jasper` : "Live from your Jasper"}
          </p>
        </div>
      </div>
      <div className="mt-3">{children}</div>
    </EmberGlowCard>
  );
}

function Note({ text }: { text: string }) {
  return <p className="text-[13px] leading-relaxed text-muted-foreground">{text}</p>;
}

/** Resolves the dashboard — own token, or the coach token when a client is named. */
function useJasperDash(client: string | null): {
  dash: JasperClientDashboard | null;
  loading: boolean;
} {
  const [state, setState] = useState<{ dash: JasperClientDashboard | null; loading: boolean }>({
    dash: null,
    loading: true,
  });

  useEffect(() => {
    let alive = true;
    void (async () => {
      let dash: JasperClientDashboard | null = null;
      try {
        if (client) {
          const profile = await fetchProfileByUsername(client.replace(/^@/, ""));
          const record = profile as { user_id?: string; id?: string } | null;
          const uid = record?.user_id ?? record?.id ?? null;
          dash = uid ? await coachDashboard(uid) : null;
        } else {
          dash = await ownDashboard();
        }
      } catch {
        dash = null;
      }
      if (alive) setState({ dash, loading: false });
    })();
    return () => {
      alive = false;
    };
  }, [client]);

  return state;
}

// MARK: - Readiness (recovery ring + 14-day trend)

function ReadyRing({ score, size = 86 }: { score: number; size?: number }) {
  const stroke = size * 0.1;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const clamped = Math.min(100, Math.max(0, score));
  const frac = Math.max(0.02, clamped / 100);
  const color = readyColor(clamped);
  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="currentColor" strokeOpacity={0.1} strokeWidth={stroke} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={color}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={`${c * frac} ${c}`}
          style={{ filter: `drop-shadow(0 0 ${size * 0.07}px ${color}73)` }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-[26px] font-bold tabular-nums leading-none" style={{ color }}>
          {clamped}
        </span>
        <span className="mt-0.5 text-[8px] font-black uppercase tracking-[0.1em] text-muted-foreground">
          {readyWord(clamped)}
        </span>
      </div>
    </div>
  );
}

function ReadinessLookCard({ client }: { client: string | null }) {
  const { dash, loading } = useJasperDash(client);

  let body: ReactNode;
  if (loading) {
    body = <Note text="Reading readiness live…" />;
  } else if (!dash) {
    body = <Note text={client ? "Couldn't reach this client's Jasper right now." : CONNECT_HINT} />;
  } else {
    const scope = dashLockedScope(dash, "readiness");
    if (scope) {
      body = <Note text={`Readiness isn't shared on this token (needs ${scope}) — their choice, never guessed.`} />;
    } else {
      const rows = (dashRows(dash, "readiness") as Row[])
        .slice()
        .sort((a, b) => (strAny(b.recorded_on) ?? "").localeCompare(strAny(a.recorded_on) ?? ""));
      const latest = rows[0];
      const score = latest ? (numAny(latest.score) ?? numAny(latest.readiness_score)) : (dash.summary.readinessScore ?? null);
      if (score === null) {
        body = <Note text="No readiness synced yet — it lands here the moment Jasper scores a day." />;
      } else {
        const trend = rows
          .slice(0, 14)
          .reverse()
          .map((row, i) => ({ id: strAny(row.recorded_on) ?? `d${i}`, score: numAny(row.score) ?? numAny(row.readiness_score) ?? 0 }));
        body = (
          <div className="flex items-center gap-4">
            <ReadyRing score={Math.round(score)} />
            <div className="min-w-0 flex-1">
              <div className="flex h-[42px] items-end gap-[3px]">
                {trend.map((point, i) => (
                  <div
                    key={point.id}
                    className="flex-1 rounded-full"
                    style={{
                      height: `${Math.max(12, point.score)}%`,
                      background: readyColor(point.score),
                      opacity: i === trend.length - 1 ? 1 : 0.55,
                    }}
                  />
                ))}
              </div>
              <p className="mt-1.5 text-[9px] font-semibold text-muted-foreground">14-day trend · newest right</p>
            </div>
          </div>
        );
      }
    }
  }

  return (
    <LookShell icon={<Gauge className="h-4 w-4" />} kicker="READINESS" clientName={client} loading={loading}>
      {body}
    </LookShell>
  );
}

// MARK: - Sleep (stage hypnogram)

function SleepLookCard({ client }: { client: string | null }) {
  const { dash, loading } = useJasperDash(client);

  let body: ReactNode;
  if (loading) {
    body = <Note text="Reading last night live…" />;
  } else if (!dash) {
    body = <Note text={client ? "Couldn't reach this client's Jasper right now." : CONNECT_HINT} />;
  } else {
    const scope = dashLockedScope(dash, "sleep");
    if (scope) {
      body = <Note text={`Sleep isn't shared on this token (needs ${scope}).`} />;
    } else {
      const rows = (dashRows(dash, "sleep") as Row[])
        .slice()
        .sort((a, b) => (strAny(b.started_at) ?? "").localeCompare(strAny(a.started_at) ?? ""));
      const night = rows[0];
      if (!night) {
        body = <Note text="No sleep sessions synced yet." />;
      } else {
        const stages = [
          { name: "AWAKE", seconds: numAny(night.awake_seconds) ?? 0 },
          { name: "REM", seconds: numAny(night.rem_seconds) ?? 0 },
          { name: "CORE", seconds: numAny(night.light_seconds) ?? 0 },
          { name: "DEEP", seconds: numAny(night.deep_seconds) ?? 0 },
        ];
        const longest = Math.max(1, ...stages.map((s) => s.seconds));
        const total = stages.reduce((n, s) => n + s.seconds, 0);
        const quality = numAny(night.quality_score);
        body = (
          <div className="flex items-center gap-3.5">
            <div className="min-w-0 flex-1 space-y-1.5">
              {stages.map((stage) => (
                <div key={stage.name} className="flex items-center gap-2">
                  <span className="w-10 text-[8px] font-black tracking-wide" style={{ color: STAGE_COLORS[stage.name] }}>
                    {stage.name}
                  </span>
                  <div className="h-[8px] flex-1 overflow-hidden rounded-full" style={{ background: `${STAGE_COLORS[stage.name]}21` }}>
                    {stage.seconds > 0 && (
                      <div
                        className="h-full rounded-full"
                        style={{ width: `${Math.max(5, (stage.seconds / longest) * 100)}%`, background: STAGE_COLORS[stage.name] }}
                      />
                    )}
                  </div>
                  <span className="w-10 text-right text-[9px] font-bold tabular-nums text-muted-foreground">
                    {fmtDuration(stage.seconds)}
                  </span>
                </div>
              ))}
              {total > 0 && (
                <div className="flex h-[6px] gap-[2px] overflow-hidden rounded">
                  {stages
                    .filter((s) => s.seconds > 0)
                    .map((stage) => (
                      <div key={stage.name} style={{ width: `${(stage.seconds / total) * 100}%`, background: STAGE_COLORS[stage.name] }} />
                    ))}
                </div>
              )}
              <p className="text-[9px] text-muted-foreground">{fmtDuration(total)} asleep + awake</p>
            </div>
            {quality !== null && (
              <div className="relative h-[56px] w-[56px] shrink-0">
                <svg width={56} height={56} className="-rotate-90">
                  <circle cx={28} cy={28} r={24} fill="none" stroke="#5856D6" strokeOpacity={0.15} strokeWidth={6} />
                  <circle
                    cx={28}
                    cy={28}
                    r={24}
                    fill="none"
                    stroke="#5856D6"
                    strokeWidth={6}
                    strokeLinecap="round"
                    strokeDasharray={`${2 * Math.PI * 24 * Math.max(0.02, Math.min(1, quality / 100))} ${2 * Math.PI * 24}`}
                  />
                </svg>
                <div className="absolute inset-0 flex flex-col items-center justify-center">
                  <span className="text-[15px] font-bold tabular-nums" style={{ color: "#5856D6" }}>
                    {Math.round(quality)}
                  </span>
                  <span className="text-[5.5px] font-black tracking-wide text-muted-foreground">QUALITY</span>
                </div>
              </div>
            )}
          </div>
        );
      }
    }
  }

  return (
    <LookShell icon={<MoonStar className="h-4 w-4" />} kicker="SLEEP" clientName={client} loading={loading}>
      {body}
    </LookShell>
  );
}

// MARK: - Bio age (vitality)

function BioAgeLookCard({ client }: { client: string | null }) {
  const { dash, loading } = useJasperDash(client);

  let body: ReactNode;
  if (loading) {
    body = <Note text="Reading the vitality score live…" />;
  } else if (!dash) {
    body = <Note text={client ? "Couldn't reach this client's Jasper right now." : CONNECT_HINT} />;
  } else {
    const bio = dash.summary.biologicalAge;
    const delta = dash.summary.bioageDeltaYears;
    if (bio === null) {
      body = <Note text="No biological age synced yet — it appears once the partner Jasper app computes one." />;
    } else {
      const younger = (delta ?? 0) <= 0;
      const blobFrom = younger ? "#5CDBB8" : "#F2B14D";
      const blobTo = younger ? "#3394E0" : "#F26659";
      body = (
        <div className="flex flex-col items-center gap-2.5">
          <div
            className="relative flex h-[128px] w-[128px] items-center justify-center rounded-full"
            style={{
              background: `radial-gradient(circle at 38% 32%, ${blobFrom}E6, ${blobTo}CC 72%, transparent 100%)`,
              boxShadow: `0 10px 34px ${blobTo}59`,
            }}
          >
            <div className="flex flex-col items-center">
              <span className="text-[40px] font-bold leading-none text-white" style={{ textShadow: `0 0 18px ${blobTo}` }}>
                {Number.isInteger(bio) ? bio : bio.toFixed(1)}
              </span>
              <span className="mt-1 text-[8px] font-black tracking-[0.2em] text-white/75">BIOLOGICAL AGE</span>
            </div>
          </div>
          {delta !== null && (
            <span
              className="rounded-full px-3 py-1 text-[13px] font-bold"
              style={{ background: `${blobTo}24`, color: blobTo }}
            >
              {Math.abs(delta).toFixed(1)} yrs {younger ? "younger" : "older"} than real age
            </span>
          )}
          <p className="text-center text-[10px] text-muted-foreground">
            An estimate from synced health data — not a medical measurement.
          </p>
        </div>
      );
    }
  }

  return (
    <LookShell icon={<Hourglass className="h-4 w-4" />} kicker="BIOLOGICAL AGE" clientName={client} loading={loading}>
      {body}
    </LookShell>
  );
}

// MARK: - Water (own live tap-to-log cup)

function WaterLookCard() {
  const [rows, setRows] = useState<JasperWaterRow[] | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [connected, setConnected] = useState<boolean>(true);
  const [busy, setBusy] = useState<boolean>(false);
  const goal = 8;

  const load = async (): Promise<void> => {
    try {
      setRows(await fetchWaterToday());
      setConnected(true);
    } catch {
      setConnected(false);
    }
    setLoading(false);
  };

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const add = async (): Promise<void> => {
    if (busy) return;
    setBusy(true);
    try {
      await logWaterCup(250);
      await load();
    } catch {
      /* honest no-op — the count simply doesn't move */
    }
    setBusy(false);
  };

  const remove = async (): Promise<void> => {
    if (busy || !rows || rows.length === 0) return;
    setBusy(true);
    try {
      await jasperDeleteRow("water", rows[rows.length - 1].id);
      await load();
    } catch {
      /* honest no-op */
    }
    setBusy(false);
  };

  const cups = rows?.length ?? 0;

  return (
    <LookShell icon={<Droplets className="h-4 w-4" />} kicker="WATER" clientName={null} loading={loading}>
      {!connected ? (
        <Note text={CONNECT_HINT} />
      ) : (
        <div className="flex items-center gap-4">
          <div className="min-w-0 flex-1">
            <div className="flex items-baseline gap-1.5">
              <span className="text-[36px] font-black tabular-nums leading-none">{cups}</span>
              <span className="text-[14px] font-semibold text-muted-foreground">of {goal}</span>
            </div>
            {cups > goal && (
              <p className="mt-0.5 text-[11px] font-bold" style={{ color: "#338FDB" }}>
                +{cups - goal} beyond goal
              </p>
            )}
            <div className="mt-2 flex items-center gap-2">
              <button
                onClick={() => void remove()}
                disabled={busy || cups === 0}
                aria-label="Remove last cup"
                className="flex h-8 w-8 items-center justify-center rounded-full bg-foreground/5 text-foreground/70 disabled:opacity-40"
              >
                <Minus className="h-3.5 w-3.5" />
              </button>
              <button
                onClick={() => void add()}
                disabled={busy}
                aria-label="Log one cup"
                className="flex h-8 w-8 items-center justify-center rounded-full bg-foreground/5 disabled:opacity-40"
                style={{ color: "#338FDB" }}
              >
                <Plus className="h-3.5 w-3.5" />
              </button>
            </div>
            <p className="mt-1.5 text-[9.5px] text-muted-foreground">
              Tap the glass to log a 250 ml cup — it lands in Jasper instantly.
            </p>
          </div>
          <button onClick={() => void add()} disabled={busy} aria-label="Log one cup of water" className="shrink-0">
            <JasperWaterCup level={cups / goal} width={70} height={98} />
          </button>
        </div>
      )}
    </LookShell>
  );
}

// MARK: - Blood (PhenoAge + nine markers)

const BLOOD_MARKERS: { label: string; key: string; unit: string }[] = [
  { label: "Albumin", key: "albumin_g_dl", unit: "g/dL" },
  { label: "Creatinine", key: "creatinine_mg_dl", unit: "mg/dL" },
  { label: "Glucose", key: "glucose_mg_dl", unit: "mg/dL" },
  { label: "CRP", key: "crp_mg_l", unit: "mg/L" },
  { label: "Lymph", key: "lymphocyte_pct", unit: "%" },
  { label: "MCV", key: "mcv_fl", unit: "fL" },
  { label: "RDW", key: "rdw_pct", unit: "%" },
  { label: "ALP", key: "alp_u_l", unit: "U/L" },
  { label: "WBC", key: "wbc_1000_ul", unit: "10³/µL" },
];

function BloodLookCard({ client }: { client: string | null }) {
  const { dash, loading } = useJasperDash(client);

  let body: ReactNode;
  if (loading) {
    body = <Note text="Reading the latest panel live…" />;
  } else if (!dash) {
    body = <Note text={client ? "Couldn't reach this client's Jasper right now." : CONNECT_HINT} />;
  } else if (client && (dash.summary.bloodLocked || dashLockedScope(dash, "blood_panels"))) {
    body = (
      <Note text="Blood never rides a coach token unless the client grants read:blood explicitly — ask them to share it from Jasper's Coach access." />
    );
  } else if (dashLockedScope(dash, "blood_panels")) {
    body = <Note text="Blood panels aren't shared on this token — grant read:blood from Jasper to see them here." />;
  } else {
    const rows = (dashRows(dash, "blood_panels") as Row[])
      .slice()
      .sort((a, b) => (strAny(b.drawn_on) ?? "").localeCompare(strAny(a.drawn_on) ?? ""));
    const latest = rows[0];
    if (!latest) {
      body = <Note text="No blood panels synced yet — they appear the moment one lands in Jasper." />;
    } else {
      const pheno = numAny(latest.pheno_age_years);
      const present = BLOOD_MARKERS.filter((m) => numAny(latest[m.key]) !== null);
      body = (
        <div className="space-y-2.5">
          <div className="flex items-baseline justify-between">
            {pheno !== null && <span className="text-[17px] font-bold">PhenoAge {pheno.toFixed(1)}</span>}
            {strAny(latest.drawn_on) && (
              <span className="text-[10px] text-muted-foreground">Drawn {strAny(latest.drawn_on)?.slice(0, 10)}</span>
            )}
          </div>
          <div className="grid grid-cols-3 gap-2">
            {present.map((marker) => {
              const value = numAny(latest[marker.key]) ?? 0;
              return (
                <div key={marker.key} className="rounded-lg bg-foreground/5 px-1.5 py-1.5 text-center">
                  <p className="text-[8px] font-black tracking-wide text-muted-foreground">{marker.label.toUpperCase()}</p>
                  <p className="text-[12px] font-bold tabular-nums">
                    {Number.isInteger(value) ? value : value.toFixed(1)} {marker.unit}
                  </p>
                </div>
              );
            })}
          </div>
          {present.length === 0 && <Note text="Panel synced, but no marker values decoded." />}
        </div>
      );
    }
  }

  return (
    <LookShell icon={<FlaskConical className="h-4 w-4" />} kicker="BLOOD WORK" clientName={client} loading={loading}>
      {body}
    </LookShell>
  );
}

// MARK: - Router

function EmberJasperLookCardBase({ look }: { look: EmberJasperLook }) {
  const client = look.client?.replace(/^@/, "") ?? null;
  switch (look.kind) {
    case "bioage":
    case "bio_age":
    case "vitality":
    case "biological_age":
      return <BioAgeLookCard client={client} />;
    case "readiness":
    case "recovery":
    case "stress":
    case "strain":
      return <ReadinessLookCard client={client} />;
    case "sleep":
      return <SleepLookCard client={client} />;
    case "water":
    case "hydration":
      return <WaterLookCard />;
    case "blood":
    case "bloodwork":
    case "blood_panels":
    case "labs":
      return <BloodLookCard client={client} />;
    default:
      return (
        <LookShell icon={<Sparkles className="h-4 w-4" />} kicker="JASPER DATA" clientName={null} loading={false}>
          <Note text={`No native card for "${look.kind}" yet — ask me for the numbers instead.`} />
        </LookShell>
      );
  }
}

export const EmberJasperLookCard = memo(EmberJasperLookCardBase);
