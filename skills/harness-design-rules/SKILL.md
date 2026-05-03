---
name: harness-design-rules
description: AI 風デザインを禁止し、Lucide Icons のみ使用、shokasonjuku UX 心理学 47 原則のうち主要 10 を必須適用、WCAG AA 準拠を強制する。「UI を実装」「デザインする」「コンポーネント追加」「色を決める」等の文脈で発火。
---

# harness-design-rules

ハーネス配下のすべての UI / 視覚要素に適用する。

## 禁止（AI 風要素）

- グラデーション（特に紫〜青〜ピンク）
- ネオンカラー / 蛍光色
- グロー / 過度なぼかし / blob 形状
- 宇宙・星空・パーティクル背景
- 浮遊アニメーション / 3D グラデーション球体
- 「AI Powered」「Smart」「Intelligent」等の装飾的バッジ
- 絵文字（特に UI 内）

## 必須（人間らしさ）

- 単色 or 控えめな同系色
- 軽いシャドウ（`shadow-sm` / `shadow-md`）
- 明確な境界線（`border border-neutral-200`）
- 直線 / 適度な角丸
- **Lucide Icons のみ**（`lucide-react`）
- 機能を直接表現するラベル（「保存」「削除」等）

## カラーシステム

ブランドカラー 1 + アクセント 1 + ニュートラル + セマンティック:

```ts
primary: 1 色 + 明度バリエーション（500 がメイン）
secondary: 1 色（補色 / 類似色、使いすぎ注意）
neutral: 50〜950（テキスト / 背景 / 境界線）
semantic: success / error / warning / info
```

純粋なグレーよりも温かみのあるグレー（stone 系）を推奨。

## アクセシビリティ（WCAG AA）

| 項目 | 要件 |
|------|------|
| 本文コントラスト | 4.5:1 以上 |
| 大文字（18pt+ / 14pt bold+） | 3:1 以上 |
| タップ領域 | 44×44pt 以上（Fitts の法則） |
| キーボード操作 | フォーカスリング非削除、Tab 順論理的 |
| `prefers-reduced-motion` | 必ず尊重（アニメーション無効化） |
| `aria-label` | アイコンのみのボタンに必須 |

## UX 心理学 47 原則のうち必須 10（shokasonjuku）

参考: <https://www.shokasonjuku.com/ux-psychology>

1. **Hick の法則**: 1 画面 1 主アクション
2. **Fitts の法則**: タップ領域 44×44pt+、CTA は親指圏内
3. **Miller の法則**: グルーピング 7±2 以内
4. **Jakob の法則**: 既存慣習を踏襲（独自 UI を避ける）
5. **Aesthetic-Usability 効果**: 見た目を軽視しない
6. **Peak-End ルール**: 完了画面 / 成功フィードバックを丁寧に
7. **Doherty 閾値**: 操作フィードバック 400ms 以内
8. **コントラスト**: WCAG AA 必須
9. **キーボード**: フォーカス可視・論理的
10. **Reduced motion**: 尊重

## アイコン規約（Lucide のみ）

```tsx
import { Check, AlertCircle, Loader2 } from 'lucide-react';

<Check className="h-4 w-4 text-success" />
<Button><Plus className="h-4 w-4 mr-2" />追加する</Button>
<Button variant="ghost" size="icon" aria-label="設定"><Settings className="h-5 w-5" /></Button>
<Loader2 className="h-4 w-4 animate-spin" />
```

サイズ:
- インライン: `h-4 w-4`
- ボタン内: `h-4 w-4` or `h-5 w-5`
- ナビ: `h-5 w-5` or `h-6 w-6`

## アプリアイコン

- favicon.ico / favicon.svg / apple-touch-icon.png（180×180）
- android-chrome-{192,512}.png
- og-image.png（1200×630）
- グラデーション禁止、シンプルで識別可能な形

## チェックリスト

- [ ] 絵文字を UI に使っていない
- [ ] グラデーション / ネオンカラー無し
- [ ] Lucide 以外のアイコンライブラリを使っていない
- [ ] WCAG AA コントラスト確認
- [ ] `prefers-reduced-motion` 対応
- [ ] アイコンボタンに `aria-label`
- [ ] フォーカスリング非削除
