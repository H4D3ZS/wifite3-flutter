# Architect Memory — Local Cognitive Memory for AI Agents

**Lightweight, zero-dependency persistence for agentic AI environments.**

---

## The Problem

Long-running AI chat sessions accumulate tokens until they lag or hit context limits. When you clear the thread, the AI loses everything — your project rules, decisions, preferences, all gone. Cloud-based vector databases solve this, but they add latency, cost, and dependencies that are overkill for local work.

## The Solution

Architect Memory is a single Python script that creates a local SQLite database on your machine. Your AI agent writes its context, decisions, and project knowledge directly to disk. When you start a fresh session, the agent reads it back and picks up exactly where it left off.

No servers. No API keys. No network round-trips. Just a file on your hard drive.

---

## Features

- **Core Memory** — Store overarching project rules, persona settings, tech stacks, and user preferences by topic. Updating a topic always keeps the latest version.
- **Decision Log** — A chronological ledger of explicit choices. When you switch from Tailwind to vanilla CSS, the agent logs *what* it decided and *why*, so future sessions have full rationale.
- **Tags & Search** — Tag entries for fast filtering and search across everything by keyword.
- **Export / Import** — One-command JSON export for backups, version control, or migrating between machines.
- **Delete & Prune** — Remove stale topics or outdated decisions so the agent isn't polluted by old context.

---

## Requirements

- Python 3.7+
- No external packages (uses only the standard library)
- An agentic AI environment with native Python execution (e.g. Antigravity, Claude with code execution, etc.)

---

## Setup

1. Drop `architect_memory_clean.py` into your project folder.
2. Tell your AI agent:

> *"Read `architect_memory_clean.py` and run it to initialize the memory database."*

This creates `architect_memory.db` in the same directory. That's it. The agent now understands the full memory system and can operate it on your behalf.

---

## Usage

You don't need to know the function names or syntax. Your agent reads the script and translates your natural language into the right calls. Just talk to it.

### Saving Memory

> *"Save our current project rules to memory under the topic 'core_directives'. Tag it as frontend and stack."*

> *"Update the 'api_design' memory with everything we decided about the REST endpoints today."*

> *"Remember that we're using Next.js 14 with the App Router. Save that to memory."*

### Recalling Memory

> *"Read everything from memory and get up to speed."*

> *"What do we have stored under the topic 'core_directives'?"*

> *"Show me all memory entries tagged 'frontend'."*

> *"Search memory for anything related to authentication."*

### Logging Decisions

> *"Log a decision: we dropped Tailwind in favor of CSS Modules because the bundle size was 40% larger."*

> *"Show me the last 10 decisions we've made."*

> *"Show me all decisions tagged 'backend'."*

### Cleaning Up

> *"Delete the memory topic 'old_prototype_notes' — it's outdated."*

> *"Remove decision #3 from the log, we reversed that choice."*

### Backups

> *"Export the entire memory database to a JSON file."*

> *"Import memory from the backup file I used on my other machine."*

### Quick Check

> *"Give me a summary of what's in the memory database."*

---

## The Workflow (Step by Step)

### 1. Initialize

Start a new project. Tell your agent:

> *"Read `architect_memory_clean.py` and run it to initialize the memory database."*

### 2. Work Normally

Build, iterate, make decisions. The agent accumulates context naturally in the chat window.

### 3. Commit Before Clearing

When the session gets heavy, ask the agent to persist everything before you wipe the thread:

> *"Commit our current context to memory. Save the project rules under 'core_directives', the API design under 'api_design', and log any decisions we made this session. Tag everything appropriately."*

### 4. Recall in a Fresh Session

Open a new zero-token chat. Your first prompt:

> *"Read `architect_memory_clean.py`, initialize it, then read all memory topics and the last 20 decisions. Get fully up to speed."*

The agent reloads its own brain instantly.

---

## What's Under the Hood

You don't need to know this to use it, but if you're curious — the script manages two SQLite tables.

**`cognitive_cache`** holds named memory blocks. Each topic is unique, so saving to the same topic overwrites the previous version. Every entry can be tagged and is timestamped automatically.

**`decision_log`** is an append-only chronological record. Each entry captures what was decided, why, and when. Entries can also be tagged and searched.

The full function list (for reference or if you want to extend the script):

| Function | What it does |
|----------|-------------|
| `init_db()` | Creates the database and tables |
| `update_memory(topic, content, tags)` | Saves or updates a memory topic |
| `read_memory(topic, tag)` | Reads one topic, filters by tag, or returns everything |
| `search_memory(keyword)` | Searches across topics and content |
| `delete_memory(topic)` | Removes a topic |
| `log_decision(decision, rationale, tags)` | Records a decision |
| `read_decisions(limit, tag, keyword)` | Queries the decision log |
| `delete_decision(decision_id)` | Removes a decision |
| `export_all(filepath)` | Exports the full DB to JSON |
| `import_from_json(filepath)` | Imports from a JSON export |
| `stats()` | Prints a quick DB summary |

---

## Why Local?

A SQLite file on your disk reads in microseconds. There's no network hop, no auth token to manage, no monthly bill, and no risk of a third-party service going down mid-session. The database file is a single portable artifact you can back up, version-control, or copy to another machine. For local agentic workflows, this is the fastest and simplest path to persistent memory.

---

## License

MIT — use it however you want.
