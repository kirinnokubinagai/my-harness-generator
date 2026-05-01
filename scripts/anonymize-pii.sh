#!/usr/bin/env bash
# 概要: pg_dump の custom 形式ダンプを stage 復元前にマスキングするための雛形。
#       実際は plain SQL に展開してから sed / awk で書き換える運用を推奨する。
#       ここでは email / password_hash / phone のサンプル列を匿名化する例を示す。
set -euo pipefail
DUMP_FILE="${1:?dump file path required}"
WORK="${DUMP_FILE}.sql"
nix develop --command pg_restore --no-owner --no-acl -f "$WORK" "$DUMP_FILE"

# 全ての email を user{rownum}@example.test に書き換え（雛形）
nix develop --command sed -i.bak -E "s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/anonymized@example.test/g" "$WORK"

# パスワードハッシュ列をテスト用ダミーへ
nix develop --command sed -i.bak -E "s/\\\$2[aby]\\\$[0-9]{2}\\\$[A-Za-z0-9./]{53}/\\\$2b\\\$12\\\$0000000000000000000000000000000000000000000000000000/g" "$WORK"

# 上書き dump
nix develop --command pg_dump -Fc -f "$DUMP_FILE" "$WORK" || true
rm -f "$WORK" "$WORK.bak"
echo "[anonymize-pii] 完了: $DUMP_FILE"
