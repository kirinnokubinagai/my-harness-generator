Phase 8 (final spec) cross-check. The user has reviewed the consolidated spec (dev/docs/spec/0[1-7]-*.md) and approved it. Read all spec files and the design mocks via --context (already attached). Point out:

- Inconsistencies between the spec, the mocks, and the chosen tech stack.
- Logical contradictions inside the spec.
- Missing functionality — features named in spec/04-features.md that have no corresponding entity in spec/07-data-model.md, no UI in spec/05-visual.md, or no tool in spec/06-tools.md.

Pay special attention to:
- Tool choices in spec/06-tools.md that contradict any visualMocks[].decisionsRevealed entry.
- spec/07-data-model.md gaps in GDPR / permissions / cardinality / migration drills.
