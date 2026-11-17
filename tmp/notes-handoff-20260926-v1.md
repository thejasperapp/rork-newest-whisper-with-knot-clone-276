# Whisper Notes → Whisper DM document cards

Version 1 · 26 September 2026 · Implementation handoff for the Whisper agent

## Recommendation

Use the existing Whisper inbox and shared Supabase identity. Add two native message cards: **Document invitation** and **Signature request**. Do not build another inbox, copy the editable document into chat, or give chat membership document permissions.

The sender reviews one recipient, the card and its link before sending. Default to **title only**; offer **Include a preview** containing up to 280 characters of sender-approved plain text. The recipient can see that deliberately shared excerpt before accepting the document invitation. This is a separate, permanent chat copy, not permission to fetch the private document. Show the sender: “This preview will be sent into the conversation. Removing document access cannot recall copies already seen or saved.”

For signing, the card opens **Review signing request**, never an inline Sign button. Keep signing in the Notes review flow. The recipient verifies the invited mailbox even when already signed into Whisper. Do not infer signing authority from Viewer/Commenter/Editor or from receiving a DM.

## Current versus proposed

Implemented in Notes source: owner preparation of a reviewed fixed signing copy, self-signing, one named email recipient, email-code verification, consent, separate signed PDF and history. Signing is ordinary electronic signing; no paid signing-provider API, qualified certificate, or government-verified identity claim.

Existing invitation DM sends only the restricted `/shared/<document UUID>` link. Existing selected-snippet DM requires the recipient already to have active document access. **Neither currently sends these structured cards or previews to pending invitees.** The schema and fixtures in this handoff are a proposed integration contract, not a deployed card-delivery API. Keep new card send controls disabled until both delivery/resolver endpoints and the receiving Whisper client pass the acceptance checks below.

## Exact message structure

Keep the existing `whisper_messages` row and its `body` text fallback. Store this object in its existing nullable `embed` JSON column. Do not serialize JSON as visible chat text or reuse the unrelated meeting-notes message format.

### Document invitation example

```json
{
  "kind": "whisper.notes.invitation",
  "version": 1,
  "source_app": "whisper-notes",
  "delivery_id": "30000000-0000-4000-8000-000000000001",
  "document_id": "20000000-0000-4000-8000-000000000001",
  "invitation_id": "40000000-0000-4000-8000-000000000001",
  "source_seq": 7,
  "role_at_send": "commenter",
  "preview": {
    "mode": "approved_excerpt",
    "title": "Launch review",
    "excerpt": "The launch decisions, owners and next steps we agreed to review together.",
    "captured_at": "2026-09-26T12:00:00Z"
  }
}
```

### Signature request example

```json
{
  "kind": "whisper.sign.request",
  "version": 1,
  "source_app": "whisper-notes",
  "delivery_id": "30000000-0000-4000-8000-000000000002",
  "request_id": "50000000-0000-4000-8000-000000000001",
  "source_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "page_count": 2,
  "expires_at": "2026-10-26T12:00:00Z",
  "preview": {
    "mode": "title_only",
    "title": "Launch agreement",
    "excerpt": null,
    "captured_at": "2026-09-26T12:00:00Z"
  }
}
```

All IDs and hashes above are synthetic. Required fields are exactly those shown for each variant. Reject unknown versions and unknown keys in v1, rather than guessing their meaning. Optional preview means `mode:"title_only", excerpt:null`; do not omit those fields. `source_seq` is the document revision at send time, distinct from schema `version`. It is not proof the excerpt occurs verbatim in the document. Label it **Sender-approved preview**, not a verified document summary. For signature cards, the hash and page count refer only to the fixed source PDF, never the current editable original.

Validation: UUIDs; title 1–160 UTF-16 code units; excerpt 1–280 UTF-16 code units when included; ISO-8601 UTC timestamps; nonnegative safe integer sequence; role exactly `viewer | commenter | editor`; lowercase 64-hex SHA-256; page count 1–10. Reject control/format characters and `<`/`>` in preview text. Normalize user input to a single line before review; never silently alter it after approval. Render as literal text, never HTML/Markdown or clickable links inside excerpts. Swift must apply the same UTF-16 limits, not grapheme-count limits. Cap the entire embed at 8 KB UTF-8.

Keep message identity on the existing row: `id = delivery_id`, `from_user_id`, `to_user_id`, `thread_id`, `created_at`. These are derived/validated by the server; do not accept caller-supplied sender IDs or arbitrary thread IDs. Display sender attribution from the row/current profile, not from the embed. Store the fallback in `body`: “Document invitation: <approved title>\n<approved excerpt, if included>\n<restricted document URL>”, or “Signature request: <approved title>\n<approved excerpt, if included>\n<restricted signing URL>”. Legacy recipients see readable text, not raw JSON. No new permission is conferred by either fallback.

## Exact card layout

- Header: original Notes icon, **Whisper Notes**, and **Document invitation** or **Signature request**.
- Title: 17-point semibold, two lines; show the full title in accessibility text/details.
- Optional excerpt: 14-point body, three lines, labeled **Sender-approved preview**. A tap may expand only this already-sent text without fetching the document.
- Detail: “Invited as commenter” for invitations; “2-page fixed copy · Email verification required” for signatures. `role_at_send` is historical, not current authority.
- Primary action: **Review invitation** / **Review signing request**. At least 44×44 points. Respect Dynamic Type and dark appearance.
- Footer: **Restricted access**. No automatic preview fetch, read receipt, acceptance, email-code send, or signing side effect.
- Missing/unverified delivery: plain fallback message; never add an official badge. Unknown/denied current state: “Unavailable or access changed,” not invented success. Offline: show the approved historical preview only, labeled “Status not checked.”

Use a document icon, not a public thumbnail URL, in v1. A small screenshot can still expose confidential text and has additional storage/revocation/caching risks. A future image preview needs explicit crop approval, private per-delivery storage, server-checked reads and a new schema version—not a public bucket or signed URL embedded permanently in a message.

## Required server integration (NEW, not yet implemented)

Implement these under the Notes Worker, keeping native Supabase Auth. Suggested reserved contracts:

1. `POST /notes-cards/v1/prepare`: authenticated owner submits either `{kind:"whisper.notes.invitation",document_id,invitation_id,expected_seq,preview_mode,excerpt}` or `{kind:"whisper.sign.request",request_id,recipient_user_id,preview_mode,excerpt}`. Return `{draft_id,expires_at,recipient_user_id,card,body}`. Draft is server-held, owner-bound, valid for 10 minutes. Allocate `delivery_id` once. Derive title, role, sequence, fixed hash/page count, recipient and canonical URL server-side. Freeze exactly the returned card/body for review. This action sends nothing.
2. `POST /notes-cards/v1/send`: `{draft_id,confirmed:true}` with the same authenticated owner. Atomically recheck ownership, deletion, invitation/request status, intended recipient, both-direction blocks, DM-specific blocks and delivery limits. Reject changed invitation roles or changed source revision; require a fresh review, never silently update the preview. A signing request must be `sent`, unexpired and match the selected account’s confirmed email; do not return that private email. Write the immutable delivery receipt plus `whisper_messages` row in one transaction, using `delivery_id` as the message ID. No source-content grants, email send or signature happens here. Return `{delivery_id,message_id,state:"persisted"}`; this is not proof of push/inbox reading.
3. `POST /notes-cards/v1/resolve`: `{message_id}` authenticated as its sender or its direct recipient. Check actual message visibility, delivery receipt binding and blocks. Return the trusted stored card plus `{state,checked_at,open_url}`. Do not accept caller-supplied card fields as truth. Invitation states: `pending | active | unavailable`; signature states before mailbox verification: `verification_required | unavailable` only—do not expose receipt, email or signing history merely because a DM exists. The signing review endpoint remains authoritative after verification. No content from the editable original is returned by this resolver.

Use a new private receipt table rather than overloading the snippet receipt. Suggested fields: `delivery_id`, `message_id`, `sender_id`, `recipient_id`, `draft_id`, `kind`, `document_id`/`request_id`, `invitation_id`, `card`, `body`, `fingerprint`, `created_at`. Enable RLS, deny direct client writes, use a narrow service transaction. Fingerprint the exact frozen draft including sender, recipient, kind, targets, preview, body and authority snapshot. Reuse the same ID on network retry; changed bytes conflict. Receipt survives message deletion, but resolve of a deleted message is unavailable and retry must not recreate it. Rate-limit new deliveries to 30/day/sender initially; retries do not consume another slot.

Do not let the existing broadly writable `embed` column establish provenance. Clients can otherwise manufacture an official-looking card. Renderer must resolve the receipt and compare row sender/recipient/message ID before showing official actions/status. Audit UPDATE policies too; protect system-authored fields while keeping recipient read-state changes and existing message types working. No wholesale replacement of parent chat policies.

Lock/order invitation or signing request and delivery receipt consistently. Block/revocation mutations must use compatible serialization if promising atomic race prevention; client checks followed by an unrestricted insert are not sufficient. Reject unsupported group recipients in v1. Group chats never imply source access, and no batch group invitation DMs are authorized here.

## Existing contracts to preserve

- Supabase project: `uryyyegnbtlmyhqlgndy`; native Supabase `auth.uid()` identities. Do not introduce Rork Auth or another account store.
- Invitation creation: `whisper_notes_invite_person({p_doc,p_invitation,p_user,p_role})`. Document owner only; stable account ID. Keep existing invitations and accepted grants, not replacements.
- Invitation acceptance: `whisper_notes_action({p_doc,p_action:"accept"|"decline",p_payload:{id:invitation_id}})` after the recipient deliberately chooses it. Prefer the existing `/shared/<UUID>` review screen, not auto-accept on card tap.
- Existing DM invitation files: `src/lib/notesInvitationDM.ts`, native `WhisperNotesInvitationDMService.swift`; native bridge `notes-invite-dm`. Current send is link-only, uses invitation UUID as message ID, and client-side reconciliation. Do not add excerpts to that legacy insert.
- Existing selected-snippet RPC: `whisper_notes_message({p_doc,p_id,p_recipient,p_body,p_quote})`; requires active recipient access, body 1–1500, quote ≤2000, final text ≤4000, 60 new sends/hour. Transactional receipt checks sender/fingerprint. It is not a preview-to-pending-invite endpoint.
- Pair thread ID: first 32 lowercase hex characters of SHA-256 of sorted lowercase user UUIDs joined with `|`, formatted as UUID. Not UUIDv5. Match the parent app’s actual thread routing before enabling.
- Parent receiver surfaces: `WhisperBackendService.swift` (`WhisperMessageRow` decode), `WhisperDMThreadView.swift`, `WhisperInboxView.swift`, `WhisperMessagePreview.swift`, and push notification construction. Extend all relevant surfaces; do not reactivate Notes’ retired social shell.
- Existing Notes links: `https://notes.mydailywhisper.com/shared/<UUID>`. Signing links must use the deployed signing origin from Notes’ `SIGN_SITE`, path `/sign/<request UUID>`. Do not substitute a hostname until its signing route is verified. Use HTTPS with app/browser fallback; universal-link association still needs signed-device acceptance.

## Signing handoff details

Current API prefix: `/whisper-sign/v1/` on the configured Notes functions origin. Native reads `Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL`; browser uses the build-configured public functions URL. Owner requests send the existing Supabase session in `X-Whisper-Authorization: Bearer <session>`; do not transfer it through a URL, chat, HTML, clipboard or cross-app query parameter.

Owner actions: `identity`, `list`, `create`, `read`, `send`, `email`, `sign`, `void`. `send` means open the reviewed request, **not DM delivery**. Guest actions: `guest/code` `{id,email}`, `guest/verify` `{id,challenge,code}`, then `guest/read` `{id,token}`. Verification returns a memory-only 30-minute request-scoped capability. Signing requires reviewed fixed hash, exact named signer, explicit consent version and stable operation UUID through the existing UI. Do not put guest tokens/codes, email, PDFs, signature images, storage links, service keys or consent receipts in a DM card. A card is not the agreement or evidence of consent.

## Sender and recipient implementation order

1. Whisper agent builds decode, receipt verification, native cards, plain fallback, notification summaries and safe opening. Push text should say “Document invitation” / “Signature request”; no excerpt, title or email on the lock screen by default.
2. Notes adds the prepare/send/resolver server contracts and owner composer with title-only default, excerpt review, recipient review and persistent delivery outcomes. Keep them disabled until tested together.
3. Enable for individual Whisper accounts first. Guests outside Whisper continue via signing email/restricted link; no account creation required. Do not look up private account emails in the client.
4. Later owned apps hand off to Notes’ reviewed workflow. Separate organization authority, app authentication and external API integrations need their own contracts; do not pass a client `source_app` string to impersonate another app.

## Acceptance checks before enabling card sending

- Pending invitee sees only approved preview, not the document. Acceptance grants only the selected role.
- Revoked, deleted, expired, blocked, wrong-account and forwarded cards cannot fetch source content or sign. Previously disclosed text is not claimed retractable.
- Forged embed, altered sender, wrong delivery ID, substituted hash, arbitrary URL, unknown version and HTML preview cannot produce an official actionable card.
- Double taps and response loss produce one delivery; changed retries conflict; deleted messages stay deleted.
- Account switching hides cached resolved cards. No credential transfer, automatic scraping, read receipts, AI reading or push excerpts.
- Signature DM recipient matches the invited confirmed mailbox; viewing the card never sends a code or commits consent. Test legal name, every page, downloads, decline/void, expiry and retry through Notes.
- Test current and legacy Whisper versions, iPhone/iPad/VoiceOver/Dynamic Type, signed-device link routing, actual consenting-account delivery and denied production reads. Synthetic tests do not establish real delivery or legal validity.

Reference validator in Notes: `src/lib/whisperDocumentCard.ts`. Examples above are automatically validated by `whisperDocumentCard.test.ts`. These tests validate the proposed data shape, not live delivery permissions.
