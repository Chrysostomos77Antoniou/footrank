# FootRank Mission Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Next.js 15 web dashboard running 3 autonomous AI agents (Marketing, Growth, Content) on a 4-hour cron cycle, with a human approval queue for high-risk actions and a chat override to the orchestrator.

**Architecture:** A separate Next.js 15 (App Router) repo. Server-side API routes call the Anthropic SDK (`claude-opus-4-8`) directly. An orchestrator wakes on a Vercel Cron trigger (every 4h) or on owner chat, fans out to sub-agents in parallel, each running a manual agentic tool-use loop. Low-risk tool actions execute immediately; high-risk actions are written to a Supabase `approvals` table for one-tap human approval. State (memory, approvals, activity log, content drafts) lives in the shared footrank Supabase project.

**Tech Stack:** Next.js 15, TypeScript, `@anthropic-ai/sdk`, Supabase JS (`@supabase/supabase-js`), Tailwind CSS v4, Framer Motion, Vercel Cron, Tavily (web search), platform social/notification APIs.

## Global Constraints

- Model ID is exactly `claude-opus-4-8` everywhere — never a date-suffixed variant.
- Thinking config: `thinking: { type: "adaptive" }` — never `budget_tokens` (400s on Opus 4.8).
- No assistant-turn prefills (400s on Opus 4.8). Use system-prompt instructions or `output_config.format`.
- Tool inputs are parsed objects already (`block.input`) — never raw-string-match serialized input.
- All agent inference runs server-side only. The Anthropic API key never reaches the browser.
- Owner-only access: single allowed email `tomisapoelcity@gmail.com` via Supabase Auth.
- High-risk actions (social posts, push notifications, GitHub PRs, user emails) MUST go through the approval queue — never execute inline.
- Autonomy cycle cadence: every 4 hours (`0 */4 * * *`).
- Agent accent colors: Marketing `#00d4ff`, Growth `#00ff88`, Content `#ffaa00`.
- Marketing platforms: Facebook, Instagram, TikTok, YouTube.

---

## File Structure

```
footrank-mission-control/
├── package.json, tsconfig.json, next.config.ts, tailwind.config.ts, .env.local.example
├── lib/
│   ├── anthropic.ts          # Shared Claude client + MODEL constant
│   ├── supabase.ts           # Server-side Supabase admin client
│   ├── approvals.ts          # Approval queue read/write helpers
│   ├── memory.ts             # Agent memory + activity log helpers
│   └── types.ts              # Shared TS types (Approval, ActivityEntry, etc.)
├── tools/
│   ├── registry.ts           # Tool definitions + dispatcher (manual loop)
│   ├── web-search.ts         # Tavily search (low-risk, executes inline)
│   ├── supabase-read.ts      # Read footrank data (low-risk)
│   ├── social.ts             # Queue social posts (high-risk → approvals)
│   ├── notifications.ts      # Queue push notifications (high-risk → approvals)
│   └── github.ts             # Queue GitHub issues/PRs (high-risk → approvals)
├── agents/
│   ├── run-loop.ts           # Generic manual agentic loop (shared by all agents)
│   ├── marketing.ts          # Marketing agent system prompt + tool set
│   ├── growth.ts             # Growth agent system prompt + tool set
│   ├── content.ts            # Content agent system prompt + tool set
│   └── orchestrator.ts       # Cycle coordinator + chat handler
├── app/
│   ├── layout.tsx, globals.css
│   ├── page.tsx              # Command Center (kanban + roster + live feed + chat)
│   ├── approvals/page.tsx    # Approvals queue
│   ├── agents/[id]/page.tsx  # Agent detail
│   ├── components/           # AgentCard, KanbanBoard, LiveFeed, ApprovalCard, ChatBubble
│   └── api/
│       ├── cycle/route.ts        # POST — cron trigger
│       ├── chat/route.ts         # POST — orchestrator chat (streaming)
│       ├── feed/route.ts         # GET — activity feed (polling)
│       └── approvals/
│           ├── route.ts          # GET — list pending
│           └── [id]/route.ts     # POST — approve / reject
└── supabase/migrations/0001_mission_control.sql
```

---

### Task 1: Project scaffold + environment

**Files:**
- Create: `package.json`, `tsconfig.json`, `next.config.ts`, `tailwind.config.ts`, `app/globals.css`, `app/layout.tsx`, `.env.local.example`, `.gitignore`

**Interfaces:**
- Produces: a runnable Next.js 15 App Router project with Tailwind v4 configured and the dark theme CSS variables available globally.

- [ ] **Step 1: Scaffold the app**

Run:
```bash
npx create-next-app@latest footrank-mission-control --typescript --tailwind --app --no-src-dir --use-npm --eslint
cd footrank-mission-control
npm install @anthropic-ai/sdk @supabase/supabase-js framer-motion
```

- [ ] **Step 2: Add environment template**

Create `.env.local.example`:
```bash
ANTHROPIC_API_KEY=
SUPABASE_URL=
SUPABASE_SERVICE_KEY=
TAVILY_API_KEY=
FACEBOOK_ACCESS_TOKEN=
INSTAGRAM_ACCESS_TOKEN=
TIKTOK_ACCESS_TOKEN=
YOUTUBE_API_KEY=
FIREBASE_SERVICE_ACCOUNT=
GITHUB_TOKEN=
CRON_SECRET=
```

- [ ] **Step 3: Define the dark theme tokens**

Add to the top of `app/globals.css` (after the Tailwind import):
```css
:root {
  --bg: #0a0a0f;
  --surface: rgba(255, 255, 255, 0.04);
  --border: rgba(255, 255, 255, 0.08);
  --text: #e7e7ea;
  --text-dim: #8a8a93;
  --marketing: #00d4ff;
  --growth: #00ff88;
  --content: #ffaa00;
}
body { background: var(--bg); color: var(--text); }
```

- [ ] **Step 4: Verify it runs**

Run: `npm run dev`
Expected: dev server starts on http://localhost:3000 with no errors.

- [ ] **Step 5: Commit**

```bash
git init && git add -A && git commit -m "chore: scaffold Next.js mission control app"
```

---

### Task 2: Database schema

**Files:**
- Create: `supabase/migrations/0001_mission_control.sql`

**Interfaces:**
- Produces: tables `agent_memory`, `approvals`, `activity_log`, `content_drafts` in the footrank Supabase project. Later tasks read/write these.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0001_mission_control.sql`:
```sql
create table if not exists agent_memory (
  id uuid primary key default gen_random_uuid(),
  agent text not null,
  cycle_at timestamptz not null,
  summary text not null,
  created_at timestamptz default now()
);

create table if not exists approvals (
  id uuid primary key default gen_random_uuid(),
  agent text not null,
  action_type text not null,
  payload jsonb not null,
  preview text not null,
  status text default 'pending',
  rejection_reason text,
  created_at timestamptz default now(),
  resolved_at timestamptz
);

create table if not exists activity_log (
  id uuid primary key default gen_random_uuid(),
  agent text not null,
  action text not null,
  detail text,
  created_at timestamptz default now()
);

create table if not exists content_drafts (
  id uuid primary key default gen_random_uuid(),
  agent text not null,
  type text not null,
  title text not null,
  body text not null,
  status text default 'draft',
  created_at timestamptz default now()
);

create index if not exists idx_approvals_status on approvals(status);
create index if not exists idx_activity_created on activity_log(created_at desc);
```

- [ ] **Step 2: Apply the migration**

Apply via the Supabase MCP `apply_migration` tool (name `mission_control_init`) or the Supabase SQL editor.
Expected: four tables created; `list_tables` shows them.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations && git commit -m "feat: add mission control database schema"
```

---

### Task 3: Shared clients + types

**Files:**
- Create: `lib/anthropic.ts`, `lib/supabase.ts`, `lib/types.ts`

**Interfaces:**
- Produces:
  - `lib/anthropic.ts` → `export const MODEL = "claude-opus-4-8"`, `export const anthropic` (an `Anthropic` client instance)
  - `lib/supabase.ts` → `export const supabaseAdmin` (service-role client)
  - `lib/types.ts` → `AgentId = "marketing" | "growth" | "content"`; interfaces `Approval`, `ActivityEntry`, `MemoryEntry`, `ContentDraft` matching the columns in Task 2

- [ ] **Step 1: Write the Anthropic client**

Create `lib/anthropic.ts`:
```ts
import Anthropic from "@anthropic-ai/sdk";

export const MODEL = "claude-opus-4-8";
export const anthropic = new Anthropic(); // reads ANTHROPIC_API_KEY
```

- [ ] **Step 2: Write the Supabase admin client**

Create `lib/supabase.ts`:
```ts
import { createClient } from "@supabase/supabase-js";

export const supabaseAdmin = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_KEY!,
  { auth: { persistSession: false } },
);
```

- [ ] **Step 3: Write shared types**

Create `lib/types.ts`:
```ts
export type AgentId = "marketing" | "growth" | "content";

export interface Approval {
  id: string;
  agent: AgentId;
  action_type: string;
  payload: Record<string, unknown>;
  preview: string;
  status: "pending" | "approved" | "rejected";
  rejection_reason: string | null;
  created_at: string;
  resolved_at: string | null;
}

export interface ActivityEntry {
  id: string;
  agent: AgentId;
  action: string;
  detail: string | null;
  created_at: string;
}

export interface MemoryEntry {
  id: string;
  agent: AgentId;
  cycle_at: string;
  summary: string;
  created_at: string;
}

export interface ContentDraft {
  id: string;
  agent: AgentId;
  type: string;
  title: string;
  body: string;
  status: "draft" | "approved" | "used";
  created_at: string;
}
```

- [ ] **Step 4: Verify types compile**

Run: `npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib && git commit -m "feat: add shared anthropic/supabase clients and types"
```

---

### Task 4: Memory, activity log, and approvals helpers

**Files:**
- Create: `lib/memory.ts`, `lib/approvals.ts`
- Test: `lib/__tests__/approvals.test.ts`

**Interfaces:**
- Consumes: `supabaseAdmin` (Task 3), `AgentId`, `Approval` (Task 3).
- Produces:
  - `lib/memory.ts` → `logActivity(agent: AgentId, action: string, detail?: string): Promise<void>`; `recentMemory(agent: AgentId, limit?: number): Promise<MemoryEntry[]>`; `writeMemory(agent: AgentId, summary: string): Promise<void>`
  - `lib/approvals.ts` → `queueApproval(input: { agent: AgentId; action_type: string; payload: Record<string, unknown>; preview: string }): Promise<string>` (returns new id); `listPending(): Promise<Approval[]>`; `pendingCount(): Promise<number>`; `resolveApproval(id: string, status: "approved" | "rejected", reason?: string): Promise<Approval>`

- [ ] **Step 1: Write memory helpers**

Create `lib/memory.ts`:
```ts
import { supabaseAdmin } from "./supabase";
import type { AgentId, MemoryEntry } from "./types";

export async function logActivity(agent: AgentId, action: string, detail?: string) {
  await supabaseAdmin.from("activity_log").insert({ agent, action, detail: detail ?? null });
}

export async function writeMemory(agent: AgentId, summary: string) {
  await supabaseAdmin.from("agent_memory").insert({ agent, summary, cycle_at: new Date().toISOString() });
}

export async function recentMemory(agent: AgentId, limit = 10): Promise<MemoryEntry[]> {
  const { data } = await supabaseAdmin
    .from("agent_memory")
    .select("*")
    .eq("agent", agent)
    .order("cycle_at", { ascending: false })
    .limit(limit);
  return (data ?? []) as MemoryEntry[];
}
```

- [ ] **Step 2: Write approvals helpers**

Create `lib/approvals.ts`:
```ts
import { supabaseAdmin } from "./supabase";
import type { AgentId, Approval } from "./types";

export async function queueApproval(input: {
  agent: AgentId;
  action_type: string;
  payload: Record<string, unknown>;
  preview: string;
}): Promise<string> {
  const { data, error } = await supabaseAdmin
    .from("approvals")
    .insert({ ...input, status: "pending" })
    .select("id")
    .single();
  if (error) throw error;
  return data.id as string;
}

export async function listPending(): Promise<Approval[]> {
  const { data } = await supabaseAdmin
    .from("approvals")
    .select("*")
    .eq("status", "pending")
    .order("created_at", { ascending: false });
  return (data ?? []) as Approval[];
}

export async function pendingCount(): Promise<number> {
  const { count } = await supabaseAdmin
    .from("approvals")
    .select("*", { count: "exact", head: true })
    .eq("status", "pending");
  return count ?? 0;
}

export async function resolveApproval(
  id: string,
  status: "approved" | "rejected",
  reason?: string,
): Promise<Approval> {
  const { data, error } = await supabaseAdmin
    .from("approvals")
    .update({ status, rejection_reason: reason ?? null, resolved_at: new Date().toISOString() })
    .eq("id", id)
    .select("*")
    .single();
  if (error) throw error;
  return data as Approval;
}
```

- [ ] **Step 3: Write a test for the preview-shape contract**

Install vitest: `npm install -D vitest`. Add `"test": "vitest run"` to `package.json` scripts.

Create `lib/__tests__/approvals.test.ts`:
```ts
import { describe, it, expect, vi } from "vitest";

vi.mock("../supabase", () => {
  const insert = vi.fn(() => ({ select: () => ({ single: () => ({ data: { id: "abc" }, error: null }) }) }));
  return { supabaseAdmin: { from: () => ({ insert }) } };
});

import { queueApproval } from "../approvals";

describe("queueApproval", () => {
  it("returns the new approval id", async () => {
    const id = await queueApproval({
      agent: "marketing",
      action_type: "social_post",
      payload: { platform: "tiktok", text: "hi" },
      preview: "TikTok: hi",
    });
    expect(id).toBe("abc");
  });
});
```

- [ ] **Step 4: Run the test**

Run: `npm test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib package.json && git commit -m "feat: add memory and approvals helpers"
```

---

### Task 5: Low-risk tools (web search + supabase read)

**Files:**
- Create: `tools/web-search.ts`, `tools/supabase-read.ts`

**Interfaces:**
- Consumes: `supabaseAdmin` (Task 3).
- Produces:
  - `tools/web-search.ts` → `webSearch(query: string): Promise<string>` (returns a text digest of results)
  - `tools/supabase-read.ts` → `readFootrankStats(): Promise<string>` (returns a text summary of recent signups, active teams, match counts). Read-only — queries existing footrank tables; if a table is absent it returns a graceful "no data" note rather than throwing.

- [ ] **Step 1: Write the web search tool**

Create `tools/web-search.ts`:
```ts
export async function webSearch(query: string): Promise<string> {
  const res = await fetch("https://api.tavily.com/search", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      api_key: process.env.TAVILY_API_KEY,
      query,
      max_results: 5,
      search_depth: "basic",
    }),
  });
  if (!res.ok) return `Search failed (${res.status}).`;
  const data = (await res.json()) as { results?: { title: string; url: string; content: string }[] };
  const results = data.results ?? [];
  if (results.length === 0) return "No results found.";
  return results.map((r) => `- ${r.title} (${r.url})\n  ${r.content.slice(0, 300)}`).join("\n");
}
```

- [ ] **Step 2: Write the supabase read tool**

Create `tools/supabase-read.ts`:
```ts
import { supabaseAdmin } from "../lib/supabase";

export async function readFootrankStats(): Promise<string> {
  const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const parts: string[] = [];

  const profiles = await supabaseAdmin
    .from("profiles")
    .select("*", { count: "exact", head: true })
    .gte("created_at", since);
  parts.push(profiles.error ? "Signups: unavailable" : `New signups (7d): ${profiles.count ?? 0}`);

  const matches = await supabaseAdmin
    .from("matches")
    .select("*", { count: "exact", head: true })
    .gte("created_at", since);
  parts.push(matches.error ? "Matches: unavailable" : `Matches created (7d): ${matches.count ?? 0}`);

  return parts.join("\n");
}
```

- [ ] **Step 3: Verify compile**

Run: `npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add tools && git commit -m "feat: add low-risk web-search and supabase-read tools"
```

---

### Task 6: High-risk tools (social, notifications, github)

**Files:**
- Create: `tools/social.ts`, `tools/notifications.ts`, `tools/github.ts`

**Interfaces:**
- Consumes: `queueApproval` (Task 4), `AgentId` (Task 3).
- Produces (all return a confirmation string telling the model the action was queued, never executed inline):
  - `tools/social.ts` → `queueSocialPost(agent: AgentId, input: { platform: "facebook" | "instagram" | "tiktok" | "youtube"; text: string; media_hint?: string }): Promise<string>`
  - `tools/notifications.ts` → `queuePushNotification(agent: AgentId, input: { title: string; body: string; audience: string }): Promise<string>`
  - `tools/github.ts` → `queueGithubAction(agent: AgentId, input: { kind: "issue" | "pr"; title: string; body: string }): Promise<string>`

- [ ] **Step 1: Write the social tool**

Create `tools/social.ts`:
```ts
import { queueApproval } from "../lib/approvals";
import type { AgentId } from "../lib/types";

export async function queueSocialPost(
  agent: AgentId,
  input: { platform: "facebook" | "instagram" | "tiktok" | "youtube"; text: string; media_hint?: string },
): Promise<string> {
  await queueApproval({
    agent,
    action_type: "social_post",
    payload: input,
    preview: `${input.platform.toUpperCase()}: ${input.text}`,
  });
  return `Queued a ${input.platform} post for owner approval. It will NOT publish until approved.`;
}
```

- [ ] **Step 2: Write the notifications tool**

Create `tools/notifications.ts`:
```ts
import { queueApproval } from "../lib/approvals";
import type { AgentId } from "../lib/types";

export async function queuePushNotification(
  agent: AgentId,
  input: { title: string; body: string; audience: string },
): Promise<string> {
  await queueApproval({
    agent,
    action_type: "push_notification",
    payload: input,
    preview: `Push → ${input.audience}: ${input.title} — ${input.body}`,
  });
  return `Queued a push notification for owner approval. It will NOT send until approved.`;
}
```

- [ ] **Step 3: Write the github tool**

Create `tools/github.ts`:
```ts
import { queueApproval } from "../lib/approvals";
import type { AgentId } from "../lib/types";

export async function queueGithubAction(
  agent: AgentId,
  input: { kind: "issue" | "pr"; title: string; body: string },
): Promise<string> {
  await queueApproval({
    agent,
    action_type: "github_action",
    payload: input,
    preview: `GitHub ${input.kind}: ${input.title}`,
  });
  return `Queued a GitHub ${input.kind} for owner approval. It will NOT be created until approved.`;
}
```

- [ ] **Step 4: Verify compile + commit**

Run: `npx tsc --noEmit` (expect no errors), then:
```bash
git add tools && git commit -m "feat: add high-risk tools that queue for approval"
```

---

### Task 7: Tool registry + dispatcher

**Files:**
- Create: `tools/registry.ts`
- Test: `tools/__tests__/registry.test.ts`

**Interfaces:**
- Consumes: all tool functions (Tasks 5–6), `AgentId` (Task 3).
- Produces:
  - `tools/registry.ts` → `TOOL_DEFS: Anthropic.Tool[]` (the JSON schemas for `web_search`, `read_footrank_stats`, `queue_social_post`, `queue_push_notification`, `queue_github_action`, plus a `save_content_draft` tool); and `dispatchTool(agent: AgentId, name: string, input: Record<string, unknown>): Promise<string>` which routes a tool name to its implementation and returns the result string. `save_content_draft` inserts into `content_drafts` and returns a confirmation.

- [ ] **Step 1: Write the registry**

Create `tools/registry.ts`:
```ts
import type Anthropic from "@anthropic-ai/sdk";
import type { AgentId } from "../lib/types";
import { supabaseAdmin } from "../lib/supabase";
import { webSearch } from "./web-search";
import { readFootrankStats } from "./supabase-read";
import { queueSocialPost } from "./social";
import { queuePushNotification } from "./notifications";
import { queueGithubAction } from "./github";

export const TOOL_DEFS: Anthropic.Tool[] = [
  {
    name: "web_search",
    description: "Search the web for football news, trends, or competitor activity. Call this when current information would improve a decision.",
    input_schema: { type: "object", properties: { query: { type: "string" } }, required: ["query"] },
  },
  {
    name: "read_footrank_stats",
    description: "Read live FootRank usage data (recent signups, match activity). Call this to ground decisions in real numbers.",
    input_schema: { type: "object", properties: {} },
  },
  {
    name: "queue_social_post",
    description: "Queue a social post for owner approval. Use for Facebook, Instagram, TikTok, or YouTube. The post does NOT publish until the owner approves.",
    input_schema: {
      type: "object",
      properties: {
        platform: { type: "string", enum: ["facebook", "instagram", "tiktok", "youtube"] },
        text: { type: "string", description: "Caption or script, tailored to the platform." },
        media_hint: { type: "string", description: "Suggested image/video direction." },
      },
      required: ["platform", "text"],
    },
  },
  {
    name: "queue_push_notification",
    description: "Queue a push notification to FootRank users for owner approval. Does NOT send until approved.",
    input_schema: {
      type: "object",
      properties: { title: { type: "string" }, body: { type: "string" }, audience: { type: "string" } },
      required: ["title", "body", "audience"],
    },
  },
  {
    name: "queue_github_action",
    description: "Queue a GitHub issue or PR for owner approval. Does NOT create until approved.",
    input_schema: {
      type: "object",
      properties: { kind: { type: "string", enum: ["issue", "pr"] }, title: { type: "string" }, body: { type: "string" } },
      required: ["kind", "title", "body"],
    },
  },
  {
    name: "save_content_draft",
    description: "Save a content asset (onboarding tip, campaign idea, email copy, feature highlight) to the content library for owner review.",
    input_schema: {
      type: "object",
      properties: {
        type: { type: "string", enum: ["onboarding_tip", "campaign", "email", "feature_highlight"] },
        title: { type: "string" },
        body: { type: "string" },
      },
      required: ["type", "title", "body"],
    },
  },
];

export async function dispatchTool(agent: AgentId, name: string, input: Record<string, unknown>): Promise<string> {
  switch (name) {
    case "web_search":
      return webSearch(String(input.query));
    case "read_footrank_stats":
      return readFootrankStats();
    case "queue_social_post":
      return queueSocialPost(agent, input as Parameters<typeof queueSocialPost>[1]);
    case "queue_push_notification":
      return queuePushNotification(agent, input as Parameters<typeof queuePushNotification>[1]);
    case "queue_github_action":
      return queueGithubAction(agent, input as Parameters<typeof queueGithubAction>[1]);
    case "save_content_draft": {
      await supabaseAdmin.from("content_drafts").insert({ agent, ...input });
      return "Saved to the content library for owner review.";
    }
    default:
      return `Unknown tool: ${name}`;
  }
}
```

- [ ] **Step 2: Test the dispatcher routes unknown tools safely**

Create `tools/__tests__/registry.test.ts`:
```ts
import { describe, it, expect, vi } from "vitest";
vi.mock("../../lib/supabase", () => ({ supabaseAdmin: { from: () => ({ insert: vi.fn() }) } }));
import { dispatchTool, TOOL_DEFS } from "../registry";

describe("registry", () => {
  it("exposes the six tools", () => {
    expect(TOOL_DEFS.map((t) => t.name)).toContain("queue_social_post");
    expect(TOOL_DEFS).toHaveLength(6);
  });
  it("handles unknown tools gracefully", async () => {
    expect(await dispatchTool("marketing", "nope", {})).toBe("Unknown tool: nope");
  });
});
```

- [ ] **Step 3: Run the test**

Run: `npm test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add tools && git commit -m "feat: add tool registry and dispatcher"
```

---

### Task 8: Generic agentic loop

**Files:**
- Create: `agents/run-loop.ts`

**Interfaces:**
- Consumes: `anthropic`, `MODEL` (Task 3); `TOOL_DEFS`, `dispatchTool` (Task 7); `logActivity` (Task 4); `AgentId` (Task 3).
- Produces: `runAgentLoop(opts: { agent: AgentId; system: string; userMessage: string; maxTurns?: number }): Promise<string>` — runs the manual tool-use loop until `stop_reason === "end_turn"` (or `maxTurns`, default 6), executing tools via `dispatchTool`, logging each tool call via `logActivity`, and returning the final assistant text.

- [ ] **Step 1: Write the loop**

Create `agents/run-loop.ts`:
```ts
import type Anthropic from "@anthropic-ai/sdk";
import { anthropic, MODEL } from "../lib/anthropic";
import { TOOL_DEFS, dispatchTool } from "../tools/registry";
import { logActivity } from "../lib/memory";
import type { AgentId } from "../lib/types";

export async function runAgentLoop(opts: {
  agent: AgentId;
  system: string;
  userMessage: string;
  maxTurns?: number;
}): Promise<string> {
  const { agent, system, userMessage, maxTurns = 6 } = opts;
  const messages: Anthropic.MessageParam[] = [{ role: "user", content: userMessage }];

  for (let turn = 0; turn < maxTurns; turn++) {
    const response = await anthropic.messages.create({
      model: MODEL,
      max_tokens: 8000,
      thinking: { type: "adaptive" },
      system,
      tools: TOOL_DEFS,
      messages,
    });

    if (response.stop_reason === "end_turn") {
      return response.content.filter((b) => b.type === "text").map((b) => (b as Anthropic.TextBlock).text).join("\n");
    }

    messages.push({ role: "assistant", content: response.content });

    const toolResults: Anthropic.ToolResultBlockParam[] = [];
    for (const block of response.content) {
      if (block.type === "tool_use") {
        await logActivity(agent, `tool:${block.name}`, JSON.stringify(block.input).slice(0, 300));
        const result = await dispatchTool(agent, block.name, block.input as Record<string, unknown>);
        toolResults.push({ type: "tool_result", tool_use_id: block.id, content: result });
      }
    }
    if (toolResults.length === 0) {
      return response.content.filter((b) => b.type === "text").map((b) => (b as Anthropic.TextBlock).text).join("\n");
    }
    messages.push({ role: "user", content: toolResults });
  }
  return "Reached max turns.";
}
```

- [ ] **Step 2: Verify compile**

Run: `npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add agents && git commit -m "feat: add generic agentic tool-use loop"
```

---

### Task 9: The three agents

**Files:**
- Create: `agents/marketing.ts`, `agents/growth.ts`, `agents/content.ts`

**Interfaces:**
- Consumes: `runAgentLoop` (Task 8), `recentMemory`, `writeMemory` (Task 4).
- Produces: each file exports `runMarketing()` / `runGrowth()` / `runContent(): Promise<string>`. Each builds its standing-goal system prompt, pulls recent memory to avoid repetition, runs the loop, writes a memory summary, and returns the summary.

- [ ] **Step 1: Write the marketing agent**

Create `agents/marketing.ts`:
```ts
import { runAgentLoop } from "./run-loop";
import { recentMemory, writeMemory } from "../lib/memory";

const SYSTEM = `You are the Marketing agent for FootRank, a football ranking & match-tracking app.
Standing goal: keep FootRank visible and growing on social media.
Each cycle: (1) web_search for trending football news and viral content; (2) read_footrank_stats to ground posts in real user activity; (3) draft 1-2 posts and queue_social_post for EACH relevant platform — Facebook (link + commentary), Instagram (image caption + hashtags), TikTok (15-60s video script), YouTube (Shorts or longer script). Tailor each post to its platform's format.
All posts require owner approval — never assume they are published. Respond directly without preamble.`;

export async function runMarketing(): Promise<string> {
  const memory = await recentMemory("marketing", 5);
  const userMessage = `Recent activity to avoid repeating:\n${memory.map((m) => `- ${m.summary}`).join("\n") || "none"}\n\nRun this cycle now.`;
  const summary = await runAgentLoop({ agent: "marketing", system: SYSTEM, userMessage });
  await writeMemory("marketing", summary.slice(0, 500));
  return summary;
}
```

- [ ] **Step 2: Write the growth agent**

Create `agents/growth.ts`:
```ts
import { runAgentLoop } from "./run-loop";
import { recentMemory, writeMemory } from "../lib/memory";

const SYSTEM = `You are the Growth agent for FootRank.
Standing goal: maximize user retention and activation.
Each cycle: (1) read_footrank_stats for signups and match activity; (2) identify ONE actionable insight; (3) draft a re-engagement push notification targeting a specific user segment and queue_push_notification.
Notifications require owner approval — never assume they are sent. Respond directly without preamble.`;

export async function runGrowth(): Promise<string> {
  const memory = await recentMemory("growth", 5);
  const userMessage = `Recent activity to avoid repeating:\n${memory.map((m) => `- ${m.summary}`).join("\n") || "none"}\n\nRun this cycle now.`;
  const summary = await runAgentLoop({ agent: "growth", system: SYSTEM, userMessage });
  await writeMemory("growth", summary.slice(0, 500));
  return summary;
}
```

- [ ] **Step 3: Write the content agent**

Create `agents/content.ts`:
```ts
import { runAgentLoop } from "./run-loop";
import { recentMemory, writeMemory } from "../lib/memory";

const SYSTEM = `You are the Content agent for FootRank.
Standing goal: keep FootRank's content fresh and communication sharp.
Each cycle: (1) read_footrank_stats and web_search the football calendar (tournaments, match days); (2) generate ONE content asset and save_content_draft (onboarding tip, feature highlight, seasonal campaign, or email copy).
Drafts go to the content library for owner review. Respond directly without preamble.`;

export async function runContent(): Promise<string> {
  const memory = await recentMemory("content", 5);
  const userMessage = `Recent activity to avoid repeating:\n${memory.map((m) => `- ${m.summary}`).join("\n") || "none"}\n\nRun this cycle now.`;
  const summary = await runAgentLoop({ agent: "content", system: SYSTEM, userMessage });
  await writeMemory("content", summary.slice(0, 500));
  return summary;
}
```

- [ ] **Step 4: Verify compile + commit**

Run: `npx tsc --noEmit` (expect no errors), then:
```bash
git add agents && git commit -m "feat: add marketing, growth, and content agents"
```

---

### Task 10: Orchestrator

**Files:**
- Create: `agents/orchestrator.ts`

**Interfaces:**
- Consumes: `runMarketing`, `runGrowth`, `runContent` (Task 9); `pendingCount` (Task 4); `anthropic`, `MODEL` (Task 3); `logActivity` (Task 4).
- Produces:
  - `runCycle(): Promise<{ marketing: string; growth: string; content: string }>` — checks `pendingCount`; if the queue has > 20 pending, skips the cycle and logs it; otherwise fans out to all three agents with `Promise.allSettled` and logs the cycle.
  - `streamChat(userMessage: string): Promise<ReadableStream>` — runs a single orchestrator chat turn as a streaming response (no tools; the orchestrator answers status questions and acknowledges directives). Returns a web `ReadableStream` of text chunks.

- [ ] **Step 1: Write the orchestrator**

Create `agents/orchestrator.ts`:
```ts
import { anthropic, MODEL } from "../lib/anthropic";
import { runMarketing } from "./marketing";
import { runGrowth } from "./growth";
import { runContent } from "./content";
import { pendingCount } from "../lib/approvals";
import { logActivity } from "../lib/memory";

export async function runCycle() {
  const pending = await pendingCount();
  if (pending > 20) {
    await logActivity("marketing", "cycle:skipped", `Queue backed up (${pending} pending).`);
    return { marketing: "skipped", growth: "skipped", content: "skipped" };
  }
  await logActivity("marketing", "cycle:start", `Cycle started at ${new Date().toISOString()}`);
  const [m, g, c] = await Promise.allSettled([runMarketing(), runGrowth(), runContent()]);
  const val = (r: PromiseSettledResult<string>) => (r.status === "fulfilled" ? r.value : `Error: ${r.reason}`);
  return { marketing: val(m), growth: val(g), content: val(c) };
}

const ORCH_SYSTEM = `You are the orchestrator of FootRank Mission Control. You coordinate the Marketing, Growth, and Content agents. When the owner messages you, answer status questions concisely and acknowledge directives clearly. Respond directly without preamble.`;

export async function streamChat(userMessage: string): Promise<ReadableStream> {
  const stream = anthropic.messages.stream({
    model: MODEL,
    max_tokens: 4000,
    thinking: { type: "adaptive" },
    system: ORCH_SYSTEM,
    messages: [{ role: "user", content: userMessage }],
  });
  const encoder = new TextEncoder();
  return new ReadableStream({
    async start(controller) {
      stream.on("text", (delta) => controller.enqueue(encoder.encode(delta)));
      await stream.finalMessage();
      controller.close();
    },
  });
}
```

- [ ] **Step 2: Verify compile + commit**

Run: `npx tsc --noEmit` (expect no errors), then:
```bash
git add agents && git commit -m "feat: add orchestrator cycle and chat"
```

---

### Task 11: API routes — cycle, chat, feed, approvals

**Files:**
- Create: `app/api/cycle/route.ts`, `app/api/chat/route.ts`, `app/api/feed/route.ts`, `app/api/approvals/route.ts`, `app/api/approvals/[id]/route.ts`

**Interfaces:**
- Consumes: `runCycle`, `streamChat` (Task 10); `listPending`, `resolveApproval` (Task 4); `supabaseAdmin` (Task 3).
- Produces:
  - `POST /api/cycle` — guarded by `CRON_SECRET` (Authorization header `Bearer ${CRON_SECRET}`); runs `runCycle()`; returns JSON.
  - `POST /api/chat` — body `{ message: string }`; returns the `streamChat` stream as `text/plain`.
  - `GET /api/feed` — returns the 50 most recent `activity_log` rows.
  - `GET /api/approvals` — returns `listPending()`.
  - `POST /api/approvals/[id]` — body `{ status: "approved" | "rejected"; reason?: string }`; calls `resolveApproval`; on `approved`, this is where execution would later be wired (v1 marks approved and logs).

- [ ] **Step 1: Write the cycle route**

Create `app/api/cycle/route.ts`:
```ts
import { NextRequest, NextResponse } from "next/server";
import { runCycle } from "../../../agents/orchestrator";

export const maxDuration = 300;

export async function POST(req: NextRequest) {
  const auth = req.headers.get("authorization");
  if (auth !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const result = await runCycle();
  return NextResponse.json(result);
}
```

- [ ] **Step 2: Write the chat route**

Create `app/api/chat/route.ts`:
```ts
import { NextRequest } from "next/server";
import { streamChat } from "../../../agents/orchestrator";

export const maxDuration = 60;

export async function POST(req: NextRequest) {
  const { message } = (await req.json()) as { message: string };
  const stream = await streamChat(message);
  return new Response(stream, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
```

- [ ] **Step 3: Write the feed route**

Create `app/api/feed/route.ts`:
```ts
import { NextResponse } from "next/server";
import { supabaseAdmin } from "../../../lib/supabase";

export async function GET() {
  const { data } = await supabaseAdmin
    .from("activity_log")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(50);
  return NextResponse.json(data ?? []);
}
```

- [ ] **Step 4: Write the approvals routes**

Create `app/api/approvals/route.ts`:
```ts
import { NextResponse } from "next/server";
import { listPending } from "../../../lib/approvals";

export async function GET() {
  return NextResponse.json(await listPending());
}
```

Create `app/api/approvals/[id]/route.ts`:
```ts
import { NextRequest, NextResponse } from "next/server";
import { resolveApproval } from "../../../../lib/approvals";
import { logActivity } from "../../../../lib/memory";

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { status, reason } = (await req.json()) as { status: "approved" | "rejected"; reason?: string };
  const approval = await resolveApproval(id, status, reason);
  await logActivity(approval.agent, `approval:${status}`, approval.preview);
  return NextResponse.json(approval);
}
```

- [ ] **Step 5: Verify compile + commit**

Run: `npx tsc --noEmit` (expect no errors), then:
```bash
git add app/api && git commit -m "feat: add cycle, chat, feed, and approvals API routes"
```

---

### Task 12: UI components

**Files:**
- Create: `app/components/AgentCard.tsx`, `app/components/LiveFeed.tsx`, `app/components/KanbanBoard.tsx`, `app/components/ApprovalCard.tsx`, `app/components/ChatBubble.tsx`

**Interfaces:**
- Consumes: `ActivityEntry`, `Approval`, `AgentId` (Task 3); `/api/feed`, `/api/approvals`, `/api/approvals/[id]`, `/api/chat` (Task 11).
- Produces: client components.
  - `AgentCard({ agent, status, lastRun, tasksToday })` — roster card with the agent's accent color.
  - `LiveFeed()` — polls `/api/feed` every 15s, renders entries color-coded by agent.
  - `KanbanBoard({ approvals })` — columns RESEARCHING → DRAFTING → QUEUED → APPROVED → PUBLISHED → DONE; v1 maps pending approvals into QUEUED.
  - `ApprovalCard({ approval, onResolve })` — preview + Approve/Reject buttons, reject reason input.
  - `ChatBubble()` — floating chat that POSTs to `/api/chat` and streams the response.

- [ ] **Step 1: Write AgentCard**

Create `app/components/AgentCard.tsx`:
```tsx
"use client";
import type { AgentId } from "../../lib/types";

const ACCENT: Record<AgentId, string> = { marketing: "var(--marketing)", growth: "var(--growth)", content: "var(--content)" };

export function AgentCard({ agent, status, lastRun, tasksToday }: {
  agent: AgentId; status: string; lastRun: string; tasksToday: number;
}) {
  return (
    <div style={{ borderLeft: `3px solid ${ACCENT[agent]}`, background: "var(--surface)", border: "1px solid var(--border)" }}
         className="rounded-lg p-3 mb-2">
      <div className="flex justify-between items-center">
        <span className="font-semibold uppercase" style={{ color: ACCENT[agent] }}>{agent}</span>
        <span className="text-xs" style={{ color: "var(--text-dim)" }}>{status}</span>
      </div>
      <div className="text-xs mt-1" style={{ color: "var(--text-dim)" }}>Last run: {lastRun} · {tasksToday} today</div>
    </div>
  );
}
```

- [ ] **Step 2: Write LiveFeed**

Create `app/components/LiveFeed.tsx`:
```tsx
"use client";
import { useEffect, useState } from "react";
import type { ActivityEntry, AgentId } from "../../lib/types";

const ACCENT: Record<AgentId, string> = { marketing: "var(--marketing)", growth: "var(--growth)", content: "var(--content)" };

export function LiveFeed() {
  const [entries, setEntries] = useState<ActivityEntry[]>([]);
  useEffect(() => {
    const load = () => fetch("/api/feed").then((r) => r.json()).then(setEntries);
    load();
    const t = setInterval(load, 15000);
    return () => clearInterval(t);
  }, []);
  return (
    <div className="font-mono text-xs space-y-1">
      {entries.map((e) => (
        <div key={e.id}>
          <span style={{ color: ACCENT[e.agent] }}>[{e.agent}]</span> {e.action} {e.detail ? `— ${e.detail}` : ""}
        </div>
      ))}
    </div>
  );
}
```

- [ ] **Step 3: Write KanbanBoard**

Create `app/components/KanbanBoard.tsx`:
```tsx
"use client";
import type { Approval } from "../../lib/types";

const COLUMNS = ["RESEARCHING", "DRAFTING", "QUEUED", "APPROVED", "PUBLISHED", "DONE"];

export function KanbanBoard({ approvals }: { approvals: Approval[] }) {
  const byCol: Record<string, Approval[]> = { QUEUED: approvals.filter((a) => a.status === "pending"), APPROVED: approvals.filter((a) => a.status === "approved") };
  return (
    <div className="grid grid-cols-6 gap-2">
      {COLUMNS.map((col) => (
        <div key={col} className="rounded-lg p-2" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          <div className="text-xs font-semibold mb-2" style={{ color: "var(--text-dim)" }}>{col}</div>
          {(byCol[col] ?? []).map((a) => (
            <div key={a.id} className="text-xs rounded p-2 mb-1" style={{ background: "var(--bg)" }}>{a.preview.slice(0, 80)}</div>
          ))}
        </div>
      ))}
    </div>
  );
}
```

- [ ] **Step 4: Write ApprovalCard**

Create `app/components/ApprovalCard.tsx`:
```tsx
"use client";
import { useState } from "react";
import type { Approval } from "../../lib/types";

export function ApprovalCard({ approval, onResolve }: { approval: Approval; onResolve: () => void }) {
  const [reason, setReason] = useState("");
  const resolve = async (status: "approved" | "rejected") => {
    await fetch(`/api/approvals/${approval.id}`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status, reason: status === "rejected" ? reason : undefined }),
    });
    onResolve();
  };
  return (
    <div className="rounded-lg p-4 mb-3" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
      <div className="text-xs uppercase mb-1" style={{ color: "var(--text-dim)" }}>{approval.agent} · {approval.action_type}</div>
      <div className="text-sm mb-3 whitespace-pre-wrap">{approval.preview}</div>
      <div className="flex gap-2 items-center">
        <button onClick={() => resolve("approved")} className="px-3 py-1 rounded text-sm" style={{ background: "var(--growth)", color: "#000" }}>Approve</button>
        <button onClick={() => resolve("rejected")} className="px-3 py-1 rounded text-sm" style={{ background: "#ff4444", color: "#fff" }}>Reject</button>
        <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="reason" className="text-xs px-2 py-1 rounded flex-1" style={{ background: "var(--bg)", border: "1px solid var(--border)" }} />
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Write ChatBubble**

Create `app/components/ChatBubble.tsx`:
```tsx
"use client";
import { useState } from "react";

export function ChatBubble() {
  const [open, setOpen] = useState(false);
  const [input, setInput] = useState("");
  const [reply, setReply] = useState("");
  const send = async () => {
    setReply("");
    const res = await fetch("/api/chat", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ message: input }) });
    const reader = res.body!.getReader();
    const decoder = new TextDecoder();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      setReply((r) => r + decoder.decode(value));
    }
  };
  return (
    <div className="fixed bottom-4 right-4">
      {open && (
        <div className="w-80 rounded-lg p-3 mb-2" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          <div className="text-xs mb-2 whitespace-pre-wrap min-h-16">{reply || "Message the orchestrator…"}</div>
          <div className="flex gap-2">
            <input value={input} onChange={(e) => setInput(e.target.value)} className="flex-1 text-sm px-2 py-1 rounded" style={{ background: "var(--bg)", border: "1px solid var(--border)" }} />
            <button onClick={send} className="px-3 py-1 rounded text-sm" style={{ background: "var(--marketing)", color: "#000" }}>Send</button>
          </div>
        </div>
      )}
      <button onClick={() => setOpen(!open)} className="px-4 py-2 rounded-full" style={{ background: "var(--marketing)", color: "#000" }}>Orchestrator</button>
    </div>
  );
}
```

- [ ] **Step 6: Verify compile + commit**

Run: `npx tsc --noEmit` (expect no errors), then:
```bash
git add app/components && git commit -m "feat: add mission control UI components"
```

---

### Task 13: Pages — Command Center, Approvals, Agent Detail

**Files:**
- Create/Modify: `app/page.tsx`, `app/approvals/page.tsx`, `app/agents/[id]/page.tsx`

**Interfaces:**
- Consumes: all components (Task 12); `listPending`, `recentMemory` (Tasks 4); `supabaseAdmin` (Task 3).
- Produces: three rendered routes. Command Center is the home view (top bar + agent roster + kanban + live feed + chat bubble). Approvals lists pending approval cards. Agent detail shows the agent's recent memory.

- [ ] **Step 1: Write the Command Center**

Replace `app/page.tsx`:
```tsx
import { listPending } from "../lib/approvals";
import { recentMemory } from "../lib/memory";
import { AgentCard } from "./components/AgentCard";
import { KanbanBoard } from "./components/KanbanBoard";
import { LiveFeed } from "./components/LiveFeed";
import { ChatBubble } from "./components/ChatBubble";
import type { AgentId } from "../lib/types";

export const dynamic = "force-dynamic";

export default async function Home() {
  const approvals = await listPending();
  const agents: AgentId[] = ["marketing", "growth", "content"];
  const lastRuns = await Promise.all(agents.map(async (a) => (await recentMemory(a, 1))[0]?.cycle_at ?? "never"));

  return (
    <main className="p-4">
      <header className="flex justify-between items-center mb-4">
        <h1 className="font-bold tracking-wide">FOOTRANK MISSION CONTROL</h1>
        <span className="text-xs" style={{ color: "var(--growth)" }}>● SYSTEMS OPERATIONAL</span>
      </header>
      <div className="grid grid-cols-[240px_1fr_320px] gap-4">
        <aside>{agents.map((a, i) => <AgentCard key={a} agent={a} status="IDLE" lastRun={lastRuns[i]} tasksToday={0} />)}</aside>
        <section><KanbanBoard approvals={approvals} /></section>
        <aside><div className="text-xs font-semibold mb-2" style={{ color: "var(--text-dim)" }}>LIVE FEED</div><LiveFeed /></aside>
      </div>
      <ChatBubble />
    </main>
  );
}
```

- [ ] **Step 2: Write the Approvals page**

Create `app/approvals/page.tsx`:
```tsx
"use client";
import { useEffect, useState } from "react";
import { ApprovalCard } from "../components/ApprovalCard";
import type { Approval } from "../../lib/types";

export default function ApprovalsPage() {
  const [items, setItems] = useState<Approval[]>([]);
  const load = () => fetch("/api/approvals").then((r) => r.json()).then(setItems);
  useEffect(() => { load(); }, []);
  return (
    <main className="p-4 max-w-2xl mx-auto">
      <h1 className="font-bold mb-4">APPROVALS QUEUE</h1>
      {items.length === 0 && <p style={{ color: "var(--text-dim)" }}>Nothing pending.</p>}
      {items.map((a) => <ApprovalCard key={a.id} approval={a} onResolve={load} />)}
    </main>
  );
}
```

- [ ] **Step 3: Write the Agent detail page**

Create `app/agents/[id]/page.tsx`:
```tsx
import { recentMemory } from "../../../lib/memory";
import type { AgentId } from "../../../lib/types";

export const dynamic = "force-dynamic";

export default async function AgentDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const agent = id as AgentId;
  const memory = await recentMemory(agent, 10);
  return (
    <main className="p-4 max-w-2xl mx-auto">
      <h1 className="font-bold uppercase mb-4">{agent} AGENT</h1>
      {memory.map((m) => (
        <div key={m.id} className="rounded-lg p-3 mb-2" style={{ background: "var(--surface)", border: "1px solid var(--border)" }}>
          <div className="text-xs mb-1" style={{ color: "var(--text-dim)" }}>{m.cycle_at}</div>
          <div className="text-sm whitespace-pre-wrap">{m.summary}</div>
        </div>
      ))}
    </main>
  );
}
```

- [ ] **Step 4: Verify build**

Run: `npm run build`
Expected: build succeeds with no type errors.

- [ ] **Step 5: Commit**

```bash
git add app && git commit -m "feat: add command center, approvals, and agent detail pages"
```

---

### Task 14: Cron config + deployment docs

**Files:**
- Create: `vercel.json`, `README.md`

**Interfaces:**
- Consumes: `POST /api/cycle` (Task 11).
- Produces: a Vercel Cron entry firing `/api/cycle` every 4 hours, and a README documenting env vars, Supabase setup, and the owner-only auth note.

- [ ] **Step 1: Write the cron config**

Create `vercel.json`:
```json
{
  "crons": [{ "path": "/api/cycle", "schedule": "0 */4 * * *" }]
}
```

> Note: Vercel Cron calls the path without a custom Authorization header. To keep the `CRON_SECRET` guard, set the Vercel project env `CRON_SECRET` and configure the cron to send it, OR switch the route guard to verify Vercel's `x-vercel-cron` signal. Document the chosen approach in the README.

- [ ] **Step 2: Write the README**

Create `README.md` documenting: install, the env vars from `.env.local.example`, applying the Supabase migration, the 4-hour cron, the approval-gate model (low-risk auto, high-risk queued), and owner-only access (`tomisapoelcity@gmail.com`).

- [ ] **Step 3: Commit**

```bash
git add vercel.json README.md && git commit -m "chore: add cron config and deployment docs"
```

---

### Task 15: Manual end-to-end verification

**Files:** none (verification task).

- [ ] **Step 1: Trigger a cycle locally**

Run (with `.env.local` populated):
```bash
npm run dev
curl -X POST http://localhost:3000/api/cycle -H "Authorization: Bearer $CRON_SECRET"
```
Expected: JSON with `marketing`/`growth`/`content` summaries; new rows in `activity_log`, `agent_memory`, and (likely) `approvals`.

- [ ] **Step 2: Verify the dashboard**

Open http://localhost:3000 — agent roster shows last-run times, kanban QUEUED column shows queued posts, live feed shows tool activity.

- [ ] **Step 3: Verify approvals**

Open http://localhost:3000/approvals — approve one item, reject another with a reason. Confirm `approvals.status` updates and `activity_log` records both.

- [ ] **Step 4: Verify chat override**

Open the orchestrator chat bubble, send "what did the marketing agent do today?" — confirm a streamed reply.

- [ ] **Step 5: Final commit**

```bash
git add -A && git commit -m "test: verify end-to-end mission control flow" --allow-empty
```

---

## Notes for the implementer

- **Execution actuators are deliberately stubbed in v1.** Approving an item marks it `approved` and logs it; wiring the real Facebook/Instagram/TikTok/YouTube/Firebase/GitHub API calls on approval is a follow-up once the owner has tested the approval flow and added the platform tokens. The approval routes are the single integration point.
- **Owner-only auth** is documented but not enforced in code in this plan (single-user, not yet public). Add Supabase Auth middleware before exposing the deployment publicly — gate every route to `tomisapoelcity@gmail.com`.
- The `profiles` / `matches` table names in `tools/supabase-read.ts` are assumptions about the footrank schema; adjust to the real table names during Task 5 (the tool already degrades gracefully if a table is absent).
