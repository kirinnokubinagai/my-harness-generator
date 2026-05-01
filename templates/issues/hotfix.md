---
name: hotfix
about: 本番障害の緊急修正
title: "[hotfix] "
labels: hotfix, priority/p0
---

## 障害概要

## 影響範囲

## 一時回避策（あれば）

## 修正方針

## ロールバック計画

## 完了条件（最小）

- [ ] hotfix/* ブランチで修正 + 最小テスト
- [ ] PR を main 宛に作成
- [ ] post-merge で OWASP ZAP / E2E 即時実施
- [ ] main → stage → dev へマージコミットで逆流
- [ ] 24 時間以内に post-mortem 親 issue 起票
