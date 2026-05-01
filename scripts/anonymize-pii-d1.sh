#!/usr/bin/env bash
# 概要: D1（SQLite）から export した SQL ファイルに対し、stage 復元前に PII を書き換える。
#       perl で in-place 置換することで macOS / Linux 両対応にする。
# 引数: 対象 SQL ファイル
set -euo pipefail
SQL_FILE="${1:?sql file path required}"
[ -f "$SQL_FILE" ] || { echo "::error:: $SQL_FILE が存在しません"; exit 1; }

# email を anonymized@example.test に置換（@ は perl で配列変数として補間されるため必ずエスケープする）
perl -i -pe 's/[A-Za-z0-9._%+-]+\@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/anonymized\@example.test/g' "$SQL_FILE"

# bcrypt password_hash をテスト用ダミーへ
perl -i -pe 's/\$2[aby]\$[0-9]{2}\$[A-Za-z0-9.\/]{53}/\$2b\$12\$0000000000000000000000000000000000000000000000000000/g' "$SQL_FILE"

# 電話番号（日本のフォーマット）を 0000000000 に
perl -i -pe 's/\b0\d{9,10}\b/0000000000/g' "$SQL_FILE"

# 表示名と住所はテーブル単位で UPDATE を末尾に追記する（雛形）
cat >> "$SQL_FILE" <<'EOS'
-- 復元後の追加サニタイズ（プロジェクト固有のテーブルがあれば足す）
UPDATE users SET display_name = 'テスト ユーザー' WHERE display_name IS NOT NULL;
EOS

echo "[anonymize-pii-d1] 完了: $SQL_FILE"
