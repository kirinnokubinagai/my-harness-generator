---
name: 親 issue（feature）
about: 大きな機能・変更を子 issue に分割するための親
title: "[parent] "
labels: parent
---

## 目的 / ゴール

<!-- なぜ必要か、達成すれば何が良いか -->

## スコープ

- 含む:
- 含まない:

## 子 issue リスト（コンフリクトを避ける単位で分割）

- [ ] #<子1> 変更ファイル群: `src/domain/...`
- [ ] #<子2> 変更ファイル群: `src/application/...`
- [ ] #<子3> 変更ファイル群: `src/interfaces/...`
- [ ] #<子4> tests
- [ ] #<子5> docs

## 完了条件

- [ ] すべての子 issue クローズ
- [ ] dev でフルテスト緑
- [ ] stage で OWASP ZAP / E2E 緑

## レーン割当（team-lead 記入）

- lane 1: #<子>
- lane 2: #<子>
- lane 3: #<子>
- lane 4: #<子>
