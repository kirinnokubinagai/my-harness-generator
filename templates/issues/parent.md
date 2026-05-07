---
name: Parent issue (feature)
about: Parent issue for splitting a large feature or change into child issues
title: "[parent] "
labels: parent
---

## Purpose / Goal

<!-- Why is this needed, and what benefit does it deliver? -->

## Scope

- In scope:
- Out of scope:

## Child Issue List (split into units that avoid conflicts)

- [ ] #<child1> Changed files: `src/domain/...`
- [ ] #<child2> Changed files: `src/application/...`
- [ ] #<child3> Changed files: `src/interfaces/...`
- [ ] #<child4> tests
- [ ] #<child5> docs

## Completion Criteria

- [ ] All child issues closed
- [ ] Full test suite green on dev
- [ ] OWASP ZAP / E2E green on stage

## Lane Assignment (filled in by team-lead)

- lane 1: #<child>
- lane 2: #<child>
- lane 3: #<child>
- lane 4: #<child>
