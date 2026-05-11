# Lane learnings

このファイルは過去の lane 作業で見つかった「次から避けたい落とし穴」を蓄積する。
全 lane エージェント (analyst / engineer / e2e-reviewer / reviewer) は
**ASSIGNMENT 受信直後にこのファイルを読む**。新しい学びは PR コメント or
`gh issue comment` で残し、reviewer が承認時に本ファイルへ昇格する。

形式: 1 件 1 セクション、`## <短いタイトル>` + `### Context` + `### Fix` の 3 ブロック。
**特定の lane / issue / 担当者の名前は書かない** (blameless)。

---

## 例: 「D1 の `datetime('now')` は UTC を返さない」

### Context
SQLite の `datetime('now')` はサーバの **ローカルタイムゾーン** を返す。Workers は
通常 UTC で動くが、Wrangler local mode はホスト OS の TZ を引き継ぐ。テストと本番で
日時がズレる原因になった。

### Fix
- スキーマ default は `strftime('%Y-%m-%dT%H:%M:%fZ', 'now')` を使い、明示的に
  ISO-8601 + Z 終端で UTC を確定する。
- アプリ側で時刻を扱う場合は `new Date().toISOString()` を直接渡す。

---

(以降、reviewer が承認時に追記)
