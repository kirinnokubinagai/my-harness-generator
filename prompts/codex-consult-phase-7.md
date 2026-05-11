Phase 7 (data model) normalization review. The user has just finished the per-entity drill (lifecycle / GDPR / permissions / cardinality / migration). Point out:

- Normalization issues (denormalized fields that should be separate entities; one-to-many fanout missing a junction table).
- GDPR / privacy gaps — entities that hold PII without a documented retention or deletion path.
- Permission contradictions between entities (e.g., two entities each claim to own the same field).
- Cardinality the chosen backend can't sustain (e.g., 1 M rows on a table the framework joins eagerly).

Data model with drills:
<PASTE_DATA_MODEL_HERE>
