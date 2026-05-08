# Shared Handoff

Cross-gateway coordination between bots that otherwise have **isolated brains**
(`isolated` or `shared-skills` strategy — see [§"Sharing Strategies"](../../../README.md#sharing-strategies-reference)).

## Why this folder exists

When gateways have isolated `memories/` (the `isolated` or `shared-skills`
strategy), the bots can't read each other's transient context — and that's
the point (no leakage). But you sometimes *do* want them to coordinate.
This folder is the explicit, deliberate, file-based bridge.

The pattern:

- The **work bot** writes durable handoff notes here at the end of its window.
- The **personal bot** reads them at the start of its window, and writes its
  own notes back when something the work bot should know about came up.
- Each file is plain markdown. Both bots `Read` and `Write` to it via their
  normal tool calls. No special protocol, no cross-process IPC.

## Convention used in this repo

```
_shared/
└── handoff/
    ├── weekend-handoff.md     # work bot writes Friday 6pm; personal bot reads
    └── weekend-notes.md       # personal bot writes Sunday 6pm; work bot reads
```

> _Why the underscore?_ Anything in `<parent>/_shared/` is reserved for
> cross-gateway state that's NOT a gateway itself. The launcher `run.sh`
> auto-discovers gateways by looking for sibling directories with both
> `.env` and `config.yaml`, and skips any name starting with `_` so the
> shared store never gets started as a runaway gateway.

The split is calendrical, not topical:

- **Work bot owns weekdays** (Mon–Fri) — sprint state, ops, automations.
- **Personal bot owns weekends** (Sat–Sun) — anything that came up off-hours.

That's the whole protocol. Adapt freely — three bots? Add a third file.
Different cadence? Change the schedule. Different domains? Rename the files.

## Wiring it into the bots

Add a skill to the **shared `skills/` folder** (skills are shared in the
`shared-skills` and `shared-both` strategies) telling each bot what to do
with this directory. For example, `_shared/skills/handoff-protocol.md`:

```markdown
---
name: handoff-protocol
description: Read/write the _shared/handoff/ files to coordinate with the other gateway.
---

# Handoff Protocol

Path: `~/gateways/_shared/handoff/`

## When you start a session
1. List files in handoff/.
2. Read the file(s) addressed to YOUR gateway (see filename convention).
3. Acknowledge briefly to the user: "Read handoff: <file> — <one-line summary>".

## When you end a session
- If anything happened the OTHER gateway should know about, append to the
  file addressed to it. Use ISO timestamps. Keep entries terse.

## Never
- Force-push or rewrite history.
- Delete a handoff file without explicit user confirmation.
- Echo handoff content into your `memories/MEMORY.md` (it lives here, not there).
```

That's enough for the bots to pick up the convention without each gateway
needing custom code.
