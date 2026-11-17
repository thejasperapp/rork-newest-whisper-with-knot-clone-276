/**
 * Canonical public origin for every shareable link.
 *
 * `window.location.origin` is wrong for share links: in preview/staging the
 * origin is a random deployment URL, so "Copy link" hands users gibberish.
 * Every link that leaves the app (copy link, share sheet, invite codes,
 * coaching links) must use the production domain instead.
 */
export const SITE_ORIGIN = "https://mydailywhisper.com";

/** Build an absolute, shareable URL on the canonical Whisper domain. */
export function siteUrl(path: string): string {
  return `${SITE_ORIGIN}${path.startsWith("/") ? "" : "/"}${path}`;
}

/**
 * The signup link for an invite / creator / recruiter code — one canonical
 * format everywhere (iOS creator sheet, web recruiter dashboard, profile
 * invites) so links always match: /auth?mode=signup&code=CODE
 */
export function inviteLink(code: string): string {
  return siteUrl(`/auth?mode=signup&code=${encodeURIComponent(code)}`);
}

/**
 * Recruiter QR code / application link. Leads always land on the applicant
 * questionnaire first. Signed-out users are redirected to signup, then brought
 * back. Signed-up users who are not already verified continue straight into the
 * application. This ensures the recruiter gets credit in every case.
 */
export function recruiterApplicationLink(code: string): string {
  return siteUrl(`/apply/questionnaire?code=${encodeURIComponent(code)}`);
}
