# Launch decision

Whether the app's nutrition estimates support a broad public launch (ADR 0002, ticket #14), and the evidence
behind each decision. Newest first. [`README.md`](README.md) Section 6 says how to add an entry.

The app's public accuracy claim is `EstimateReliability.published`. It must always match the latest entry.

## 2026-10-24: No broad launch, accuracy not yet validated

**Evidence.** None yet. The tools for the calibration pilot and the validation are built and tested, but they
have only been tested with hand-built records. No consented reference meals have been collected or run, so no
pass criteria are frozen and no validation set has been scored.

**Decision.** Broad public launch is not supported. The app stays a prototype for non-sensitive test photos.

**App claim.** `EstimateReliability.published` is `notValidated`. The photo-analysis disclosure tells people the
estimates have not passed an accuracy test against weighed meals. It makes no claim about how close they are.

**Next.** Run the calibration pilot, freeze the pass criteria, then collect and score a new, diverse validation
set (README Sections 1–5). Then record the result here.
