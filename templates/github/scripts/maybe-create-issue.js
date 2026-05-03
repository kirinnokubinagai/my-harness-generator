/**
 * 概要: USE_GITHUB_ISSUES=yes のときだけ GitHub Issue を作成するヘルパー。
 *       .my-harness/.config を読んでフラグを確認し、no なら logs/dev/docs/task/auto/ に
 *       マークダウンファイルとして記録する（USE_GITHUB_ISSUES=no 用フォールバック）。
 *
 * 呼び出し元（GitHub Actions の github-script から）:
 *   const helper = require('./.github/scripts/maybe-create-issue.js');
 *   await helper({ github, context, core }, {
 *     title: '[e2e] failed',
 *     labels: ['e2e', 'priority/p1'],
 *     body: '...',
 *   });
 */

const fs = require('fs');
const path = require('path');

module.exports = async ({ github, context, core }, { title, labels, body }) => {
  // .my-harness/.config から USE_GITHUB_ISSUES を読む（無ければ既定 yes）
  let useGithubIssues = 'yes';
  try {
    const configContent = fs.readFileSync('.my-harness/.config', 'utf8');
    const match = configContent.match(/^USE_GITHUB_ISSUES=(\w+)/m);
    if (match) {
      useGithubIssues = match[1];
    }
  } catch (error) {
    core.warning('.my-harness/.config が読めなかったため、USE_GITHUB_ISSUES=yes として扱います');
  }

  if (useGithubIssues === 'yes') {
    await github.rest.issues.create({
      ...context.repo,
      title,
      labels,
      body,
    });
    core.info(`Issue を作成: ${title}`);
    return;
  }

  // フォールバック: docs/task/auto/<timestamp>.md に書き出す
  const taskDirectory = 'docs/task/auto';
  fs.mkdirSync(taskDirectory, { recursive: true });
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const safeFileName = title.replace(/[^a-zA-Z0-9_\-]/g, '_').slice(0, 80);
  const targetPath = path.join(taskDirectory, `${timestamp}-${safeFileName}.md`);
  const fileContent = [
    '---',
    `title: ${JSON.stringify(title)}`,
    `labels: ${JSON.stringify(labels)}`,
    `created_at: ${new Date().toISOString()}`,
    `run_id: ${context.runId}`,
    `repository: ${context.payload.repository.full_name}`,
    '---',
    '',
    body,
  ].join('\n');
  fs.writeFileSync(targetPath, fileContent);
  core.info(`USE_GITHUB_ISSUES=${useGithubIssues} のため、Issue ではなくファイルに記録: ${targetPath}`);
};
