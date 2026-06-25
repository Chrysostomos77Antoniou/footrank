# FootRank Mission Control — Design Spec
**Date:** 2026-06-25  
**Status:** Approved  

---

## Overview

FootRank Mission Control is a standalone Next.js web dashboard that runs 3 autonomous AI agents (Marketing, Growth, Content) 24/7. Agents wake every 4 hours, autonomously research, draft, and act on their standing goals — grounded in live Supabase data. High-risk actions (posting publicly, sending notifications, opening PRs) are queued for one-tap human approval. The owner can also send direct directives to the orchestrator at any time via a chat interface, overriding the autonomous cycle.

---

## Goals

1. Agents run continuously without the owner needing to prompt them
2. Owner retains final approval on all public-facing or irreversible actions
3. Owner can interrupt and direct agents via chat at any time
4. Full visibility into what every agent did, is doing, and has queued

---

## Architecture

### Project Structure

```
footrank-mission-control/          ← separate Next.js repo
├── app/
│   ├── page.tsx                   ← Command Center (home)
│   ├── approvals/page.tsx         ← Approvals queue
│   ├── agents/[id]/page.tsx       ← Per-agent detail
│   └── api/
│       ├── chat/route.ts          ← Orchestrator chat endpoint (streaming)
│       ├── cycle/route.ts         ← Cron trigger endpoint (every 4h)
│       └── approvals/
│           ├── route.ts           ← List pending approvals
│           └── [id]/route.ts      ← Approve / reject action
├── agents/
│   ├── orchestrator.ts            ← Routes tasks, manages cycle
│   ├── marketing.ts               ← Marketing agent
│   ├── growth.ts                  ← Growth agent
│   └── content.ts                 ← Content agent
├── tools/
│   ├── supabase.ts                ← Read footrank user/match data
│   ├── github.ts                  ← Open issues, create PRs
│   ├── social.ts                  ← Post to X and Instagram
│   ├── notifications.ts           ← Send push via Firebase
│   └── web-search.ts              ← Research tool
└── lib/
    ├── anthropic.ts               ← Shared Claude client (claude-opus-4-8)
    ├── approvals.ts               ← Approval queue logic
    └── memory.ts                  ← Agent memory read/write (Supabase)
```

### Data Flow

```
Vercel Cron (every 4h)
  → POST /api/cycle
  → orchestrator.ts wakes up
  → reads agent memory from Supabase (what did each agent do last cycle?)
  → checks approval queue (skip agent if queue already backed up)
  → fans out to Marketing, Growth, Content agents in parallel
  → each agent: web search → analyze Supabase data → produce actions
  → low-risk actions execute immediately (research, save drafts)
  → high-risk actions saved to approvals table in Supabase
  → cycle log entry written to Supabase
  → dashboard live feed updates via polling
```

---

## Agents

### Orchestrator
- Runs on every cycle trigger and on every chat message from owner
- Has access to all tools and all sub-agent functions
- On cycle: reads memory, decides which agents to activate, fans out, collects results
- On chat: treats owner message as priority directive, executes immediately (next cycle still runs on schedule)
- Model: `claude-opus-4-8`

### Marketing Agent
**Standing goal:** Keep FootRank visible and growing on social media.

Each cycle:
1. Web search: trending football news, viral football content, competitor activity
2. Supabase read: which teams/players/leagues are most active in FootRank right now
3. Draft 1–2 social posts per platform: Facebook, Instagram, TikTok, YouTube — each tailored to that platform's format (short-form video script for TikTok/YouTube, image post for Instagram, link post for Facebook)
4. Queue posts for approval

Tools: `web-search`, `supabase`, `social` (write — approval required)

### Growth Agent
**Standing goal:** Maximize user retention and activation.

Each cycle:
1. Supabase read: new signups (last 4h), churn signals (users inactive >7 days), match activity peaks
2. Identify one actionable insight (e.g. "Wednesday 8pm has 3x match activity — good time for push")
3. Draft a re-engagement push notification or in-app prompt targeting a specific user segment
4. Queue notification for approval

Tools: `supabase`, `notifications` (write — approval required), `web-search`

### Content Agent
**Standing goal:** Keep FootRank's content fresh and communication sharp.

Each cycle:
1. Supabase read: recent feature usage, onboarding drop-off points
2. Web search: football calendar (upcoming tournaments, transfer windows, match days)
3. Generate one content asset: onboarding tip, feature highlight, seasonal campaign idea, or email copy
4. Save to content library (Supabase `content_drafts` table) — owner reviews from dashboard

Tools: `supabase`, `web-search`, `notifications` (write — approval required)

---

## Tools

### Approval Gate Pattern
All tools that affect external systems follow this pattern:
```typescript
// Low-risk: executes immediately
await webSearch(query)
await supabaseRead(query)

// High-risk: saves to approval queue instead of executing
await queueForApproval({
  type: 'social_post',
  agent: 'marketing',
  payload: { platform: 'twitter', text: '...', image: '...' },
  preview: '...',
})
```

### Tools Summary

| Tool | Access | Approval Required |
|---|---|---|
| `supabase` | Read footrank DB | No |
| `web-search` | Tavily/Brave API | No |
| `social` | Facebook Graph API + Instagram Graph API + TikTok API + YouTube Data API | Yes |
| `notifications` | Firebase Admin SDK | Yes |
| `github` | GitHub API (issues, PRs) | Yes |

---

## Database Schema (Supabase — new tables)

```sql
-- Agent memory: what each agent did last cycle
create table agent_memory (
  id uuid primary key default gen_random_uuid(),
  agent text not null,           -- 'marketing' | 'growth' | 'content'
  cycle_at timestamptz not null,
  summary text not null,         -- what the agent did
  created_at timestamptz default now()
);

-- Approval queue: high-risk actions pending owner review
create table approvals (
  id uuid primary key default gen_random_uuid(),
  agent text not null,
  action_type text not null,     -- 'social_post' | 'push_notification' | 'github_pr'
  payload jsonb not null,        -- full action data
  preview text not null,         -- human-readable summary
  status text default 'pending', -- 'pending' | 'approved' | 'rejected'
  rejection_reason text,
  created_at timestamptz default now(),
  resolved_at timestamptz
);

-- Activity log: all agent actions (approved + autonomous)
create table activity_log (
  id uuid primary key default gen_random_uuid(),
  agent text not null,
  action text not null,
  detail text,
  created_at timestamptz default now()
);

-- Content library: drafts generated by content agent
create table content_drafts (
  id uuid primary key default gen_random_uuid(),
  agent text not null,
  type text not null,            -- 'onboarding_tip' | 'campaign' | 'email' | 'feature_highlight'
  title text not null,
  body text not null,
  status text default 'draft',   -- 'draft' | 'approved' | 'used'
  created_at timestamptz default now()
);
```

---

## UI Design

### Theme
- Background: `#0a0a0f` (near-black)
- Surface cards: `rgba(255,255,255,0.04)` glassmorphism with `1px` border `rgba(255,255,255,0.08)`
- Agent accent colors: Marketing = `#00d4ff` (cyan), Growth = `#00ff88` (green), Content = `#ffaa00` (amber)
- Fonts: Sora (headings), Geist Mono (live feed, stats)
- Micro-animations: Framer Motion for card transitions, status pulse indicators

### Views

**1. Command Center (`/`)**
- Top bar: logo, `SYSTEMS OPERATIONAL` status chip, live clock, online dot
- Left sidebar (240px): agent roster — each agent shows name, accent color, status badge (RUNNING / IDLE / AWAITING APPROVAL), last run time, tasks done today
- Main area: Kanban board with columns: `RESEARCHING → DRAFTING → QUEUED → APPROVED → PUBLISHED → DONE`
- Right sidebar (320px): Live feed — real-time stream of agent activity, color-coded by agent
- Bottom-right: floating chat bubble → expands to chat with orchestrator

**2. Approvals Queue (`/approvals`)**
- Grid of approval cards, each showing: agent badge, action type, full preview (post copy, notification text, PR description), Approve / Reject / Edit buttons
- Reject flow: inline reason input → stored and fed back to agent memory
- Badge on nav showing pending count

**3. Agent Detail (`/agents/[id]`)**
- Agent header with accent color, status, stats (tasks today, approval rate, last cycle time)
- Current cycle task (if running): live streaming output
- Memory log: last 10 cycle summaries
- Toggle: enable/disable agent

**4. Chat Override (floating, all pages)**
- Messages go to `POST /api/chat`
- Orchestrator responds with streaming text
- Owner messages flagged as `priority: true` — executed on next cycle or immediately if urgent

### Autonomy Levels
- **Autonomous (no approval):** web research, Supabase reads, saving drafts, activity logging
- **Approval required:** social posts, push notifications, GitHub PRs/issues, emails to users

---

## Tech Stack

| Layer | Choice | Reason |
|---|---|---|
| Framework | Next.js 15 (App Router) | Full-stack, Vercel-native, streaming support |
| AI | Anthropic SDK (`claude-opus-4-8`) | Best reasoning for autonomous decisions |
| Styling | Tailwind CSS v4 + Framer Motion | Dark glassmorphism theme |
| Database | Supabase (shared with footrank) | Reuse existing infra, read live app data |
| Cron | Vercel Cron Jobs | Native, no extra infra |
| Social | Facebook Graph API + Instagram Graph API + TikTok API + YouTube Data API | Direct posting across all platforms |
| Search | Tavily API | Best for AI agent web search |
| Notifications | Firebase Admin SDK | Reuse footrank's existing Firebase setup |
| Auth | Supabase Auth (owner-only) | Simple, single user |

---

## Deployment

- Separate Vercel project: `footrank-mission-control`
- Environment variables: `ANTHROPIC_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `TAVILY_API_KEY`, `FACEBOOK_ACCESS_TOKEN`, `INSTAGRAM_ACCESS_TOKEN`, `TIKTOK_ACCESS_TOKEN`, `YOUTUBE_API_KEY`, `FIREBASE_SERVICE_ACCOUNT`, `GITHUB_TOKEN`
- Vercel Cron: `0 */4 * * *` → `POST /api/cycle`
- Owner access only: protected by Supabase Auth, single allowed email (`tomisapoelcity@gmail.com`)

---

## Out of Scope (v1)

- Engineering agent (GitHub PR automation) — add after v1 ships
- Analytics agent — add after v1 ships  
- Multi-user access / team roles
- Agent-to-agent messaging (agents communicate via orchestrator only in v1)
- Fine-tuning or custom model training
