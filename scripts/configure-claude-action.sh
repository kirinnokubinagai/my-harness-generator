#!/usr/bin/env bash
# 概要: bootstrap.env の選択に応じて、Claude Code Action の認証部分を生成する。
#       USE_CLAUDE_ACTION=no なら workflow から該当ジョブを除去する。
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${1:?root required}"
# shellcheck disable=SC1091
source "$ROOT/.harness/.bootstrap.env"
cd "$ROOT/dev"

WF=".github/workflows/pr-to-dev.yml"

if [ "$USE_CLAUDE_ACTION" = "no" ]; then
  # claude-review ジョブを除去
  python3 - "$WF" <<'PY'
import sys, yaml, io
path = sys.argv[1]
with open(path) as f:
    data = yaml.safe_load(f)
if 'jobs' in data and 'claude-review' in data['jobs']:
    del data['jobs']['claude-review']
    needs = data['jobs'].get('auto-merge', {}).get('needs', [])
    if isinstance(needs, list) and 'claude-review' in needs:
        needs.remove('claude-review')
with open(path, 'w') as f:
    yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)
PY
  exit 0
fi

# 認証種別に応じた env を埋める
AUTH_BLOCK=""
if [ "$CLAUDE_AUTH" = "oauth" ]; then
  AUTH_BLOCK='
        env:
          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}'
else
  AUTH_BLOCK='
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}'
fi

# 既存ワークフローの claude-review ジョブを正しい構文で書き換える
python3 - "$WF" "$AUTH_BLOCK" <<'PY'
import sys, yaml, re
path = sys.argv[1]
auth_block_yaml = sys.argv[2].strip()

content = open(path).read()
data = yaml.safe_load(content)

review_step = {
    'uses': 'anthropics/claude-code-action@v1',
    'with': {
        'prompt': (
            'このPRのコード変更を以下のエンジニア規約に対して厳格にレビューしてください。\n'
            '- any 型 / else 文 / 関数内コメント / JSDoc 欠落\n'
            '- Hono Clean Architecture 違反 / Drizzle push の使用\n'
            '- Lucide 以外のアイコン / 絵文字 / ハードコード機密値\n'
            '- 説明文が日本語以外\n'
            '違反は ファイル:行 の形でリスト化してください。'
        ),
        'claude_args': '{"model": "claude-opus-4-7"}',
    },
}

# OAuth or API Key 環境変数
auth_kind = 'oauth' if 'OAUTH' in auth_block_yaml else 'api'
env = ({'CLAUDE_CODE_OAUTH_TOKEN': '${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}'}
       if auth_kind == 'oauth'
       else {'ANTHROPIC_API_KEY': '${{ secrets.ANTHROPIC_API_KEY }}'})

data.setdefault('jobs', {})
data['jobs']['claude-review'] = {
    'runs-on': 'ubuntu-latest',
    'permissions': {'contents': 'read', 'pull-requests': 'write'},
    'steps': [
        {'uses': 'actions/checkout@v5', 'with': {'fetch-depth': 0}},
        {**review_step, 'env': env},
    ],
}

with open(path, 'w') as f:
    yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)
PY

echo "[configure-claude-action] 認証=$CLAUDE_AUTH を適用"
