---
name: harness-hono-clean-arch
description: Hono バックエンドで Clean Architecture を強制する。domain / application / infrastructure / interfaces の 4 層分離と依存方向の規約。「Hono で API を書く」「ハンドラを追加」「ユースケースを実装」「リポジトリを書く」等の文脈で発火。
---

# harness-hono-clean-arch

Hono アプリで Clean Architecture を **厳格に** 適用する。

## 4 層構造

```
src/
├── domain/          エンティティ / 値オブジェクト / ポート（インターフェース）
├── application/     ユースケース（オーケストレーション）
├── infrastructure/  Drizzle 実装 / 外部 API / Resend / Hono ハンドラ
└── interfaces/      Hono ルーター / 入出力 DTO（Zod）
```

## 依存方向（厳守）

```
interfaces → application → domain ← infrastructure
```

- **domain は外側に依存しない**（純粋なビジネスルールのみ）
- **infrastructure は domain の I/F を実装**（具体実装は外側、抽象は内側）
- application は domain を使い、infrastructure を I/F 経由で呼ぶ
- interfaces は application を呼ぶだけ（ロジックを書かない）

## 各層の責務

### domain
- エンティティ / 値オブジェクト
- リポジトリ I/F（`UserRepository` 等）
- 外部依存ゼロ（npm 依存も最小、Zod は OK）

### application
- ユースケース 1 つ = 1 関数 / クラス
- 「何をするか」をコード化、「どうやるか」は I/F 経由
- 副作用は依存性注入で受け取る

### infrastructure
- Drizzle / Resend / R2 / 外部 HTTP の具体実装
- domain のリポジトリ I/F を `implements`
- フレームワーク（Hono ハンドラ等）もここ

### interfaces
- Hono ルーター
- Zod スキーマ（入力検証）
- DTO 変換

## 禁止パターン

- domain がフレームワーク・DB・HTTP に依存
- ハンドラの中でビジネスロジック
- repository が application のことを知る
- application から `import { db }` を直接書く（必ず I/F 経由）

## 例

```ts
// domain/user/user-repository.ts
export interface UserRepository {
  findById(id: UserId): Promise<User | null>;
}

// application/auth/login.ts
export async function login(email: Email, password: string, deps: { userRepo: UserRepository }) { ... }

// infrastructure/persistence/d1-user-repository.ts
export function createD1UserRepository(db: DrizzleClient): UserRepository { ... }

// interfaces/http/auth-router.ts
authRouter.post('/login', zValidator('json', LoginSchema), async (c) => {
  const result = await login(c.req.valid('json').email, c.req.valid('json').password, deps);
  return c.json(result);
});
```

## チェック

- [ ] domain/ から外側への import は無い（grep で検証可能）
- [ ] application/ は infrastructure/ を直接 import しない
- [ ] interfaces/ は application/ だけ import
