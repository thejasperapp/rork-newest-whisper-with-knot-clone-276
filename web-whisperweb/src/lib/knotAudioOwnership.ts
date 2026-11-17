// Shared audio exclusion only; no session contents, credentials or persistence.
let owner: object | null = null;
export const knotVoiceAudioBusy = (): boolean => owner !== null;
export function claimKnotVoiceAudio(candidate: object): boolean {
  if (owner && owner !== candidate) return false;
  owner = candidate; return true;
}
export function releaseKnotVoiceAudio(candidate: object): void { if (owner === candidate) owner = null; }
