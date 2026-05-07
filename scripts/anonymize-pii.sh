#!/usr/bin/env bash
# Summary: Template script for masking PII in a pg_dump custom-format dump before restoring to stage.
#          In practice, it is recommended to expand to plain SQL first, then rewrite with sed/awk.
#          This example anonymizes sample columns: email, password_hash, and phone.
set -euo pipefail
DUMP_FILE="${1:?dump file path required}"
WORK="${DUMP_FILE}.sql"
nix develop --command pg_restore --no-owner --no-acl -f "$WORK" "$DUMP_FILE"

# Replace all emails with user{rownum}@example.test (template)
nix develop --command sed -i.bak -E "s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/anonymized@example.test/g" "$WORK"

# Replace password hash column with a test dummy
nix develop --command sed -i.bak -E "s/\\\$2[aby]\\\$[0-9]{2}\\\$[A-Za-z0-9./]{53}/\\\$2b\\\$12\\\$0000000000000000000000000000000000000000000000000000/g" "$WORK"

# Re-dump (overwrite)
nix develop --command pg_dump -Fc -f "$DUMP_FILE" "$WORK" || true
rm -f "$WORK" "$WORK.bak"
echo "[anonymize-pii] Done: $DUMP_FILE"
