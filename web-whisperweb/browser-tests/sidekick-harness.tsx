import { createRoot } from "react-dom/client";
import { useState } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MeetingJasperButton } from '../src/components/MeetingJasperButton';
import { MeetingWorkspace } from '../src/components/MeetingWorkspace';
import { MeetingActivities } from '../src/components/MeetingActivities';
import { MeetingSidekick } from "../src/components/MeetingSidekick";
import "../src/index.css";

const owner = "00000000-0000-4000-8000-000000000001";
const meetingID = "00000000-0000-4000-8000-000000000002";
const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
function Harness(): JSX.Element {
  const [visible, setVisible] = useState<boolean>(false);
  const [tools, setTools] = useState<boolean>(false);
  const [regular, setRegular] = useState<boolean>(false);
  const [draft, setDraft] = useState<string>('');
  const [sent, setSent] = useState<number>(0);
  return <QueryClientProvider client={client}><main className="fixed inset-0 flex h-dvh flex-col bg-[#202124] text-white"><header className="absolute inset-x-4 top-2 flex items-center justify-between"><p className="text-sm">Product weekly</p><MeetingJasperButton open={visible || regular} draft={draft} onDraftChange={setDraft} onToggle={() => { setTools(false); setRegular(true); }} onSubmit={() => { setSent(value => value + 1); setDraft(''); setRegular(true); }} /><button className="min-h-11 rounded-full bg-white/10 px-4" onClick={() => { setVisible(false); setTools(true); }}>Tools</button></header>{regular && <section aria-label="Jasper questions" className="absolute bottom-28 left-4 z-30 rounded-2xl bg-slate-800 p-4"><p>Jasper questions</p><p>Sent: {sent}</p><button className="min-h-11" onClick={() => setRegular(false)}>Close questions</button></section>}<MeetingWorkspace open={visible} drawer={<MeetingSidekick docked owner={owner} meetingID={meetingID} title="Product weekly" visible={visible} captureStatus="Transcribing your microphone" interim="Provisional speech" onRetryCapture={() => { throw new Error("Unexpected microphone interaction"); }} onHide={() => setVisible(false)} />}><div data-recording-stage className="grid h-full min-h-0 grid-cols-2 gap-3"><div className="flex items-center justify-center rounded-[28px] bg-[#34383e] text-xl">Alex</div><div className="flex items-center justify-center rounded-[28px] bg-[#49454a] text-xl">Josh</div></div></MeetingWorkspace><footer data-call-controls className="absolute inset-x-4 bottom-4 flex h-14 items-center justify-center rounded-full bg-white/10">Call controls remain available</footer>{tools && <MeetingActivities onClose={() => setTools(false)} onLayout={() => setTools(false)} onNotes={() => { setTools(false); setVisible(true); }} />}</main></QueryClientProvider>;
}
createRoot(document.getElementById("root")!).render(<Harness />);
