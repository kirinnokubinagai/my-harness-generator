/**
 * 概要: Cloudflare 操作用 MCP server。
 *       Claude Code / Cursor / Aider などの MCP クライアントが本 server を介して
 *       Cloudflare API を叩ける。デプロイ後のオペレーション (Worker 一覧 / デプロイ履歴 /
 *       ログ tail / D1 クエリ) を AI から直接実行できる。
 *
 *       MCP SDK: @modelcontextprotocol/sdk
 *
 *       設定例 (Claude Code mcpServers):
 *         {
 *           "cloudflare": {
 *             "command": "node",
 *             "args": ["dist/mcp/cloudflare-server.js"],
 *             "env": { "CLOUDFLARE_API_TOKEN": "..." , "CLOUDFLARE_ACCOUNT_ID": "..." }
 *           }
 *         }
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';

const CF_API = 'https://api.cloudflare.com/client/v4';

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`${name} が未設定です`);
  return v;
}

async function cfFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const token = requireEnv('CLOUDFLARE_API_TOKEN');
  const res = await fetch(`${CF_API}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
  });
  if (!res.ok) {
    throw new Error(`Cloudflare API ${path}: ${res.status} ${await res.text()}`);
  }
  return (await res.json()) as T;
}

const server = new Server(
  { name: 'cloudflare', version: '0.1.0' },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'list_workers',
      description: 'アカウント内の Workers を一覧する',
      inputSchema: { type: 'object', properties: {} },
    },
    {
      name: 'list_deployments',
      description: '指定 Worker のデプロイ履歴を取得する',
      inputSchema: {
        type: 'object',
        properties: { worker_name: { type: 'string' } },
        required: ['worker_name'],
      },
    },
    {
      name: 'rollback_deployment',
      description: '指定 deployment ID にロールバックする',
      inputSchema: {
        type: 'object',
        properties: {
          worker_name: { type: 'string' },
          deployment_id: { type: 'string' },
        },
        required: ['worker_name', 'deployment_id'],
      },
    },
    {
      name: 'd1_query',
      description: 'D1 データベースに SELECT クエリを実行する (DML は許可しない)',
      inputSchema: {
        type: 'object',
        properties: {
          database_id: { type: 'string' },
          sql: { type: 'string', description: '読み取り専用 SQL (SELECT のみ)' },
        },
        required: ['database_id', 'sql'],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const accountId = requireEnv('CLOUDFLARE_ACCOUNT_ID');
  const args = (req.params.arguments ?? {}) as Record<string, string>;

  switch (req.params.name) {
    case 'list_workers': {
      const data = await cfFetch<{ result: Array<{ id: string; created_on: string }> }>(
        `/accounts/${accountId}/workers/scripts`,
      );
      return { content: [{ type: 'text', text: JSON.stringify(data.result, null, 2) }] };
    }
    case 'list_deployments': {
      const data = await cfFetch<{ result: unknown }>(
        `/accounts/${accountId}/workers/scripts/${args.worker_name}/deployments`,
      );
      return { content: [{ type: 'text', text: JSON.stringify(data.result, null, 2) }] };
    }
    case 'rollback_deployment': {
      const body = JSON.stringify({ id: args.deployment_id });
      const data = await cfFetch<{ result: unknown }>(
        `/accounts/${accountId}/workers/scripts/${args.worker_name}/deployments`,
        { method: 'POST', body },
      );
      return { content: [{ type: 'text', text: JSON.stringify(data.result, null, 2) }] };
    }
    case 'd1_query': {
      const sql = args.sql ?? '';
      // 安全弁: SELECT 以外は拒否
      if (!/^\s*SELECT\b/i.test(sql)) {
        throw new Error('d1_query は SELECT のみ許可されています');
      }
      const data = await cfFetch<{ result: unknown }>(
        `/accounts/${accountId}/d1/database/${args.database_id}/query`,
        { method: 'POST', body: JSON.stringify({ sql }) },
      );
      return { content: [{ type: 'text', text: JSON.stringify(data.result, null, 2) }] };
    }
    default:
      throw new Error(`unknown tool: ${req.params.name}`);
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
