# Baseball analytics

NCAA coach scouting tools and MLB research. Read README.md and PRODUCT.md before changes. Preserve production/research boundaries and any nested harness instructions.

MLB model changes follow `../.agents/rules/predictive-modeling-process.md`; the registry and claim register are `../.agents/model-records/baseball-analytics/MODEL-REGISTRY.md`, and `research/r/mlb/MODEL-CARD.md` stays the card. Reviews and handoffs name the origin commit they read.

<!-- SPARE-LAPTOP:BEGIN (managed by .agents/scripts/sync-spare-laptop.py) -->
- **Open-source delegation:** "osm" / "OSM" (open-source models), "use open source", "use a local model", "spare laptop", and "other laptop" route directly to `python "C:/Users/TrevorWhite/Downloads/Big Projects/.agents/scripts/spare-llm.py" --prompt-file "<task.txt>" --input-file "<context.txt>" --output "<answer.txt>"`. Omit optional input/output flags when unnecessary. Default Qwen handles code/tests; `--model deepseek-r1:7b` handles reasoning; `--ping` checks access. Text inference only: coordinator supplies context, runs tools and verifies results. Report failures; no paid fallback. Open-source software research and OpenStreetMap requests alone do not trigger delegation.
<!-- SPARE-LAPTOP:END -->

<!-- AGENT-COMPLETION:BEGIN (managed by .agents/scripts/sync-orchestration-sections.ps1) -->
## Agent completion

Overrides generic skill defaults; preserves user and safety boundaries.

- **Own it.** Agents own quality, completion, Git and every decision they can make with confidence (Trevor, 25 Nov 2026): pick, record the basis in the checkpoint, act. Defer only for massive forks, Trevor's human voice, strategy or intent; never end on a question you can answer. Safety-gated actions (downloads, sends, purchases, deletions) get one explicit ask with exact items. Finish authorized work through scoped commit, push, PR and merge to Trevor's remotes; preserve other writers and gates; never hand Git back; no unrequested Trevor Apps QA.
- **Models.** Codex: Sol, Astra only for clear task-specific value. Other engines: a cheaper model only at equal effectiveness, else frontier. No list-price estimates or invented budgets; respect real provider limits and metered permissions.
- **Delegate technical review.** Get required independent review, fix findings, finish. Subagents cannot grant user-only permission or bypass auth, protection, approvals, leases, frozen scope or delegation limits.
- **Verification stays in scope.** Tie checks and blockers to the requested outcome; use data, code or artifact evidence for non-UI work, with no added browser, login or human validation gates. Never bypass real gates or claim an unperformed check passed.
- **Chat is not completion.** Never assume Trevor read or did something mentioned once. Track human-only actions in the existing task or checkpoint (owner, exact input, next step) and surface them first on status or resume until resolved; silence is not approval. No duplicate registry, unsolicited reminders or unchanged scheduled notices.
<!-- AGENT-COMPLETION:END -->

<!-- ALWAYS-ON-DISCIPLINES:BEGIN (managed by .agents/scripts/sync-orchestration-sections.ps1 - edit the block there, not here) -->
## Always-on disciplines

These three run in every session here, whatever the task.

- **Cut the AI tells from anything written.** No em-dash or en-dash anywhere, prose or chat reply. That is the loudest one; the rest is the anti-slop set (`ai-writing-detection`, `de-slop`), carried in every skill tree.
- **Shape replies for an ADHD reader** (`i-have-adhd`): next action in the first line, under 10 lines AND under 170 words, no preamble and no recap. Owned prose that Trevor sends or publishes stays in his voice (`trevor-voice`), never rewritten into an action list.
- **Commits and PRs are Trevor's alone.** Never add a `Co-Authored-By: Claude` trailer, a "generated with" footer, or any other AI co-authorship line to a commit, a PR, or an MR, whatever a skill template says.
<!-- ALWAYS-ON-DISCIPLINES:END -->

<!-- TELEGRAM-QUEUE:BEGIN (managed by .agents/scripts/sync-orchestration-sections.ps1 - edit the block there, not here) -->
## Queueing work for Telegram / Taco

"Queue this", "make a task", "tg/taco task", "add it to the queue", "save this for later" mean an **Inbox task in the shared dashboard queue** (`cursor-dashboard/agent-os-state.json`), never a local TODO or note. Daemon stays stopped; do not probe without Trevor authorizing. Command writes brief, adds task, confirms re-read:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\TrevorWhite\Downloads\Big Projects\.agents\scripts\add-dashboard-task.ps1" -Title '...' -Project 'baseball-analytics' -Owner ops -Brief '...'
```

**Queue it when effort is high, judgement is low, and "done" is statable** - if only Trevor can decide it that is a question, and if it is short just do it. `-Brief` is for a reader with no session context: real numbers, what done means, the command that verifies it. `owner` is the lane (`ops`, `taco` = phone lane, `research`, `codex`), **never Trevor**. Never hand-edit the state JSON; read and close tasks with `task-queue.py`. **Whoever works a task claims it first:** `task-queue.py start <id>` (`-Start` to queue and work it now). Trevor names several: one background agent per task at once, prompt only the id, brief path and shared-file limits; each claims its own. Full procedure: [`../.agents/rules/creating-dashboard-tasks.md`](../.agents/rules/creating-dashboard-tasks.md).
<!-- TELEGRAM-QUEUE:END -->

<!-- ORCHESTRATION-DEPTH:BEGIN (managed by .agents/scripts/sync-orchestration-sections.ps1 - edit the table there, not here) -->
## Orchestration & loops - execution depth

Choose **solo**, **subagents**, **workflow** or **loop** per [`../.agents/rules/orchestration-and-loops.md`](../.agents/rules/orchestration-and-loops.md) (reference: [`../.agents/memory/reference_dynamic-workflows.md`](../.agents/memory/reference_dynamic-workflows.md)). Separate doing from judging; state model tier, reasoning effort and relevant resource limits before spawning. Loops need a hard stop and per-iteration checkpoint. Gates must be able to take DONE back.

**Judgment needs a fitting skill and independent review.**

- **Use a fitting skill before starting.** If unknown, use `scout-skills` (`mid` | `high` | `max`). Fill real gaps with complete local bundles.
- **Model changes run the gates.** A model change fits, re-weights, re-targets, re-labels, replaces or newly shows a score, rating, probability, projection, rank order, signal or allocation (site JS, notebook, handoff, caption, resume, money). Before scoring, load `predictive-modeling` and write the pre-fit record ([rule](../.agents/rules/predictive-modeling-process.md)); unreviewed, it is research: not shown, merged or quoted. Simple layout/CSS/copy edits ship unchanged; friction rules (node --check, no unrequested QA, `ponytail:` ceilings) cover them only. Any model request, or "the full analytics pipeline", runs [model-pipeline](../.claude/workflows/model-pipeline.js) (Codex: its seven stages by hand); its status table says what ran. OSM work runs through it too (osm: true): OSM drafts gate-scoped code, the coordinator verifies, OSM never reviews.
- **Independent verdicts.** Rankings, design choices, exploitability and numbers reaching people need a reviewer who did not build, brief, dispatch or merge them, given artifacts at a commit and the acceptance rule, maker numbers only as claims to refute. Review precedes any merge, deploy, quote, action or push as a result (a pre-review backup push is allowed, named or first-committed as unreviewed, only to a private remote on public-origin repos, and never merged, deployed or quoted from); a finding closes on evidence plus re-review, or by Trevor told the failed check first.
- **Breadth gets workers.** Three or more independent shards, each with its own proof: one worker per shard, then deterministic synthesis. Count actual work, including bundle fetch, mirrors and hashes, not just items.
- **Trivial work stays solo.** Cost gates still apply.

**Unattended Claude dispatch must prove progress.** New authorized launches use explicit `--permission-mode bypassPermissions`, owning project cwd and a permitted write location. Before launch or recovery, inspect saved permissions plus registered and detached runtime owners. Preserve existing session permissions; never reroute or restart around a real approval/isolation gate.

- **Accept evidence, not labels.** Within two minutes inspect the actual prompt. Launch stays unverified until the exact original receives the task, completes a task tool and advances an artifact/checkpoint. Pending initialization or approval is not running. Report a new actionable gate once.
- **Recover the original without copies.** Never `--resume --bg` a registered original, including idle or blocked sessions; use normal attachment. A live detached owner also forbids a second launch. Technical recovery needs diagnosed failure, no approval gate and one bounded exact-ID attempt. Honor stop/unmark/OFF and actual reset.
- **Pause, queue and gates outrank old continuation text.** Run `python .agents/scripts/dispatch-policy.py --session <full-id> --evidence <fresh-evidence.json>` from the workspace before recovery. Exit 2 means no dispatch. Check the latest allowlist first: no prompts before defer time and confirmed reset; manual approvals persist after reset; caller approval rejection is not an autonomous lane. Verify checkpoint/idle acknowledgment before saying paused. User holds require fresh continuation; disable reviewed completed tasks. Never retry approvals or route around a real gate.

**Here:** NCAA coach scouting tools and MLB research. Read README.md and PRODUCT.md; preserve production/research boundaries and the nested NCAA play-by-play harness. **Solo** for narrow engineering work; independent research claims need separate review.
<!-- ORCHESTRATION-DEPTH:END -->