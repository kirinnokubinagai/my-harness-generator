#!/usr/bin/env bash
# Summary: Rewrites PII in a SQL file exported from D1 (SQLite) before restoring to stage.
#          Uses perl in-place substitution for compatibility on both macOS and Linux.
# Arguments: target SQL file
set -euo pipefail
SQL_FILE="${1:?sql file path required}"
[ -f "$SQL_FILE" ] || { echo "::error:: $SQL_FILE does not exist"; exit 1; }

# Replace emails with anonymized@example.test (@ must be escaped in perl to avoid array interpolation)
perl -i -pe 's/[A-Za-z0-9._%+-]+\@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/anonymized\@example.test/g' "$SQL_FILE"

# Replace bcrypt password_hash with a test dummy
perl -i -pe 's/\$2[aby]\$[0-9]{2}\$[A-Za-z0-9.\/]{53}/\$2b\$12\$0000000000000000000000000000000000000000000000000000/g' "$SQL_FILE"

# Replace phone numbers (Japan format) with 0000000000
perl -i -pe 's/\b0\d{9,10}\b/0000000000/g' "$SQL_FILE"

# Append UPDATE statements for display names and addresses (template — add project-specific tables as needed)
cat >> "$SQL_FILE" <<'EOS'
-- Additional sanitization after restore (add project-specific tables below as needed)
UPDATE users SET display_name = 'Test User' WHERE display_name IS NOT NULL;
EOS

echo "[anonymize-pii-d1] Done: $SQL_FILE"
