import { createRoot } from 'react-dom/client';
import { useState } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { WorkspaceWorkBoard } from '../src/pages/WorkspaceWork';
import '../src/index.css';
const owner = '10000000-0000-4000-8000-000000000001';
const client = '10000000-0000-4000-8000-000000000003';
const cache = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
function Harness(): JSX.Element {
  const [account, setAccount] = useState<string>(owner);
  const [selected, setSelected] = useState<string>('');
  return <MemoryRouter><QueryClientProvider client={cache}><nav className="flex gap-4 p-4"><button onClick={() => setAccount(owner)}>Test owner</button><button onClick={() => setAccount(client)}>Test client</button></nav><WorkspaceWorkBoard key={account} owner={account} scope={{ space: owner, team: false }} selectedId={selected} navigate={(next) => setSelected(next.id ?? '')} /></QueryClientProvider></MemoryRouter>;
}
createRoot(document.getElementById('root')!).render(<Harness />);
