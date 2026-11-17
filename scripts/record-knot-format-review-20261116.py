"""Append supplemental observations; never edit historical outcomes or run tasks.
Inputs are immutable synthetic outcomes, originals and retained browser evidence.
"""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
output = root / 'deliveries/knot-format-matrix-20261116-supplemental-review.json'
if output.exists():
    raise SystemExit('supplemental_record_already_exists')

findings = {
    'c-pdf-plain': ['Readable, but the conclusion is orphaned on an almost-empty second page.'],
    'c-pdf-guide': ['Readable, but the safety note and ending spill onto a mostly-empty second page.'],
    'c-pdf-letter': ['Visible protocol metadata at top: title: Balcony Herb Plan deliveryLabel: Herb Planting Guide. Not a design acceptance pass.'],
    'c-pdf-forest': ['Green accents are present and text is readable; safety callout occupies an otherwise mostly-empty second page.'],
    'c-pdf-mono': ['Subtitle is visibly green rather than strictly monochrome. A paragraph continues onto page two. Not a requested-palette acceptance pass despite the backend visual pass.'],
    'd-pdf-report': ['Readable, but the conclusion is orphaned on a mostly-empty second page.'],
}
records = []
for path in sorted((root / 'deliveries').glob('knot-format-matrix-20261116-[cd]-*-outcome.json')):
    original = path.read_bytes()
    data = json.loads(original)
    key = data['scope'].removeprefix('knot-format-matrix-20261116-')
    document = data.get('document') or {}
    record = dict(scope=data['scope'], taskID=data['taskID'], sourceBuild=data['expectedBuild'],
                  originalOutcome=path.relative_to(root).as_posix(),
                  originalOutcomeSHA256=hashlib.sha256(original).hexdigest(),
                  historicalHarnessPassed=data.get('passed'),
                  historicalAutomatedChecksPassed=data.get('automatedChecksPassed'),
                  backendState=(data.get('terminal') or {}).get('task', {}).get('state'),
                  backendContentStatus=document.get('contentQuality', {}).get('status', 'not_recorded'),
                  backendVisualStatus=document.get('visualReview', {}).get('status', 'not_recorded'),
                  captured=bool(document), observedIssue=data.get('issue'))
    if document:
        captured = root / 'deliveries' / Path(document['originalPath']).name
        actual = captured.read_bytes()
        assert len(actual) == document['size']
        assert hashlib.sha256(actual).hexdigest() == document['sha256'] == document['downloadedSHA256']
        record.update(finalSHA256=document['sha256'], bytes=len(actual), originalFile=captured.relative_to(root).as_posix(),
                      immutableCaptureDownloadByteIdentity='pass', independentFormatChecks=data.get('independentInspection'))
    if key in findings:
        assert document['pages'] == 2
        record.update(independentRenderedPagesOpened=[1, 2], supplementalVisualStatus='issues', observations=findings[key],
                      supplementalWholeTurnAcceptance='not_passed')
    if key in ('c-md', 'd-txt'):
        record.update(qualification='Harness/independent format-content checks passed; backend complete-content review remains unconfirmed. Do not call this an unqualified quality pass.')
    if key == 'd-txt':
        record['additionalObservation'] = 'TXT original contains literal Markdown-style bold markers; independent text checks did not certify plain-text presentation quality.'
    if document.get('format') in ('docx', 'xlsx'):
        record['independentOfficeRendering'] = 'not_exercised_local_libreoffice_unavailable'
    if key == 'd-html':
        browser_path = root / '.rork/html-delivery-inspection-20261116-d/browser-inspection.json'
        browser = json.loads(browser_path.read_bytes())
        assert browser['sha256'] == document['sha256'] and browser['loadedAndScrolled']
        assert all(not v['horizontalOverflow'] and not v['pageErrors'] and v['blockedNetworkRequests'] == 0 and v['actualEndScroll'] for v in browser['viewports'])
        record.update(browserEvidence=browser_path.relative_to(root).as_posix(),
                      browserViewports=[v['viewport'] for v in browser['viewports']],
                      supplementalBrowserLoadScrollAndVisualStatus='pass',
                      screenshotsOpened=[v[k] for v in browser['viewports'] for k in ('fullScreenshot', 'endScreenshot')],
                      observations=['All four screenshots opened: legible text, no visible clipping or overlap.',
                                    'Actual Chromium load and scroll to document end at phone and desktop widths; scripts disabled, external network blocked; no requests observed.',
                                    'Historical optional review-unavailable event and passed:false outcome remain unchanged. Backend content status is not recorded; no new content-review pass is inferred.'])
    assert path.read_bytes() == original
    records.append(record)

result = dict(observationDate='2026-11-16', syntheticOnly=True, ownerAccessed=False,
              newExecutionOrReplay=False, immutableOriginalOutcomesPreserved=True,
              nativeOrWhisperBrowserUITested=False, allFormatsAccepted=False, records=records,
              readOnlyDiagnoses={
                  'd-docx': {
                      'taskID': 'fab407b9-92ff-4abe-8f6e-fdf222e2a0f7',
                      'buildProposalID': '8326c966-d42a-4d37-9ac6-8e9e4bbab95c',
                      'declaredMeasuredPath': 'balcony_herb_plan.mdx2.docx',
                      'authoredSavePath': 'balcony_herb_plan.docx',
                      'observedFailure': 'Generated wrapper line 42 calls measured; line 14 fails file existence/nonempty/bounded size assertion after child exit zero.',
                      'conclusion': 'Authored save path differs from declared measured path. This establishes an output-contract mismatch; no unmeasured neighbor is adopted and no renderer failure is inferred.',
                      'furtherRisk': 'Retained authored program also inserts literal Markdown bold markers into Word paragraphs.',
                  },
                  'd-pptx': {
                      'taskID': '4eac43e9-ef99-47a7-be53-bfeff373dba8',
                      'buildProposalID': '56d42ade-ea92-4178-a42d-253f32f57205',
                      'proofProposalID': '301d1d1b-aeed-4144-9eb3-f3f18ee6597b',
                      'unacceptedMeasuredBytes': 31519,
                      'unacceptedMeasuredSHA256': '38b7d59b34462421f8f83b449800f2ca6f5b9fec08cc68eff5bf29fc4b672f9e',
                      'observedFailure': 'Proof stdin line 33 rejects at least one archive entry matching vbaProject, .bin or /embeddings/.',
                      'unknown': 'Actual offending archive name/type has not been observed. Benign printer settings remain only a hypothesis.',
                      'notDelivered': True,
                      'proofGateChanged': False,
                  },
              },
              museQuestions=[
                  'For h task 2627847c-f135-454c-b7bb-ee50235ea35d / build 36f70d26-b9c6-4f39-baa0-1216021a6447, can you provide owner-scoped pinned-utility stderr, bounded failure phase and journal evidence without rerunning it?',
                  'What are the documented pinned-utility proof-root lifecycle/reuse semantics? Must the task root be absent before the first utility call, and which directories does a successful or failed call leave? No collision cause is established for h.',
                  'For quarantined proposal 3d6d6c3f-29f1-45ab-b00e-6fd700755e28 / task 34cf36a2-9dcd-42c4-b457-1c52997dda7e, what authoritative owner-filtered lookup can correlate the exact startup intent with a session ID and terminal state without principal-wide enumeration, rebinding or a new start?',
                  'Can the exact existing d-pptx unaccepted measured archive be inspected read-only for entry names, Content_Types and relationships under its original synthetic owner/task? Any follow-up command must be separately authorized, not a replay or adoption.',
              ],
              limitations=['Selected regression suites only; inherited type diagnostics and stale unrelated fixtures remain.',
                           'Independent Office XML/cell inspection is not a rendering pass.',
                           'File browser inspection is not Whisper chat/card, signed-in phone, avatar or playback QA.',
                           'Observed capture or a historical harness pass does not certify all content/style requirements.'])
with output.open('x') as handle:
    json.dump(result, handle, indent=2)
    handle.write('\n')
print(json.dumps(dict(supplementalRecord=output.relative_to(root).as_posix(), reviewedOutcomes=len(records), allFormatsAccepted=False)))
