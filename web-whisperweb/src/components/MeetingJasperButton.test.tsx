import { useState } from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { MeetingJasperButton } from './MeetingJasperButton';
vi.mock('./EmberMascot', () => ({ EmberMascot: () => null }));
vi.mock('./JasperIntelKit', () => ({ JasperKitKeyframes: () => null, JasperMintPill: ({ children }: { children: React.ReactNode }) => <span>{children}</span> }));
describe('normal meeting Jasper pill', () => {
  it('typing and opening do not submit a question or start Sidekick', () => {
    const submit = vi.fn(), open = vi.fn();
    function Harness(): JSX.Element {
      const [draft, setDraft] = useState<string>('');
      return <MeetingJasperButton open={false} onToggle={open} draft={draft} onDraftChange={setDraft} onSubmit={submit} />;
    }
    render(<Harness />);
    fireEvent.change(screen.getByRole('textbox', { name: 'Ask Jasper question' }), { target: { value: 'Help me prepare' } });
    expect(submit).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Ask Jasper' }));
    expect(open).toHaveBeenCalledTimes(1);
    expect(submit).not.toHaveBeenCalled();
    fireEvent.submit(screen.getByRole('form', { name: 'Ask Jasper question' }));
    expect(submit).toHaveBeenCalledExactlyOnceWith('Help me prepare');
  });
  it('blocks empty or busy submissions', () => {
    const submit = vi.fn();
    const { rerender } = render(<MeetingJasperButton open={false} onToggle={() => {}} draft="  " onDraftChange={() => {}} onSubmit={submit} />);
    fireEvent.submit(screen.getByRole('form', { name: 'Ask Jasper question' }));
    rerender(<MeetingJasperButton open={false} onToggle={() => {}} draft="Hello" onDraftChange={() => {}} onSubmit={submit} busy />);
    fireEvent.submit(screen.getByRole('form', { name: 'Ask Jasper question' }));
    expect(submit).not.toHaveBeenCalled();
  });
});
