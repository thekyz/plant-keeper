# Plant Keeper Agent Guide

## Project Snapshot
- Name: `Plant Keeper`
- Type: Swift Package app (`PlantKeeperApp`) + core module (`PlantKeeperCore`)
- Main target: iPhone app for tracking plants and surfacing what needs attention first
- Core behavior: urgency-sorted plant list, quick "watered/checked" actions, add/edit flow, settings for AI key + home location

## Product Intent
- Help the user keep plants healthy with minimal friction.
- Prioritize urgent plants first (overdue and near-due states).
- Keep plant data and app settings durable and sync-capable (SwiftData + CloudKit path where available).

## Platform + Run Expectations
- Primary platform: iOS (minimum iOS 17).
- Normal day-to-day validation:
  - `make build`
  - `make test`
  - `make run-sim` for iOS simulator sanity
- Physical iPhone flow:
  - `make run-ios`
  - If setup is missing, use interactive `make ios-setup` (writes `.env`, gitignored).

## Code Quality Expectations
- Keep code SOLID and DRY.
- Favor protocol-based dependencies over concrete coupling in use cases/services.
- Keep view models thin coordinators; business logic belongs in use cases/core.
- Make minimal, pragmatic changes that improve correctness and maintainability.
- Avoid speculative rewrites; fix concrete issues first.

## Delivery Expectations
- Verify changes with relevant make targets and report what was actually run.
- If something cannot be fully verified (for example, missing iPhone/provisioning), state it clearly and give exact next steps.
- Keep documentation aligned when workflow changes (especially `Makefile` behavior).

## Git Workflow Rules
- Never make code changes directly on `main`.
- Always create a new branch and do all work in a git worktree tied to that branch.
- Canonical remote is `origin` at `https://github.com/thekyz/plant-keeper.git`; push all branches and `main` there.
- After completing a task, commit the changes and wait for explicit approval before merging into `main`.
- When merging to `main`, always use squash merge to keep a linear history.
- Do not create merge commits on `main`.
