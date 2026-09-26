import sqlite3
import os
import json
from datetime import datetime

# Resolve DB path: same folder as this script, with fallback to cwd
_script_dir = os.path.dirname(os.path.abspath(__file__)) if __file__ else os.getcwd()
DB_PATH = os.path.join(_script_dir, "architect_memory.db")


def _connect():
    """Returns a connection with row_factory enabled for dict-like access."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    """Initializes the SQLite database for long-term cognitive memory."""
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()

        # Core Memory — overarching rules, context, project state
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS cognitive_cache (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                topic TEXT UNIQUE NOT NULL,
                content TEXT NOT NULL,
                tags TEXT DEFAULT '',
                last_updated DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Decision Log — chronological record of explicit choices
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS decision_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                decision TEXT NOT NULL,
                rationale TEXT NOT NULL,
                tags TEXT DEFAULT '',
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        conn.commit()
    print(f"✅ Cognitive Memory initialized at: {DB_PATH}")


# ---------------------------------------------------------------------------
#  CORE MEMORY (cognitive_cache)
# ---------------------------------------------------------------------------

def update_memory(topic, content, tags=""):
    """
    Upserts a core memory block.

    Args:
        topic:   Unique identifier for this memory (e.g. 'core_directives').
        content: The full text payload to store.
        tags:    Optional comma-separated tags for filtering (e.g. 'frontend,css').
    """
    with _connect() as conn:
        conn.execute('''
            INSERT INTO cognitive_cache (topic, content, tags, last_updated)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(topic) DO UPDATE SET
                content = excluded.content,
                tags = excluded.tags,
                last_updated = excluded.last_updated
        ''', (topic, content, tags, datetime.now().isoformat()))
        conn.commit()
    print(f"💾 Saved memory for topic: '{topic}'")


def read_memory(topic=None, tag=None):
    """
    Reads core memory entries.

    Args:
        topic: Return a single topic's content (exact match).
        tag:   Filter entries that contain this tag.

    Returns:
        A single content string (if topic is given),
        or a list of (topic, content, tags, last_updated) tuples.
    """
    with _connect() as conn:
        if topic:
            row = conn.execute(
                "SELECT content FROM cognitive_cache WHERE topic = ?", (topic,)
            ).fetchone()
            return row["content"] if row else "No memory found for this topic."
        elif tag:
            rows = conn.execute(
                "SELECT topic, content, tags, last_updated FROM cognitive_cache WHERE tags LIKE ?",
                (f"%{tag}%",)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT topic, content, tags, last_updated FROM cognitive_cache ORDER BY last_updated DESC"
            ).fetchall()
        return [tuple(r) for r in rows]


def search_memory(keyword):
    """
    Full-text search across topics and content.

    Args:
        keyword: Term to search for (case-insensitive LIKE match).

    Returns:
        List of (topic, content, tags, last_updated) tuples.
    """
    with _connect() as conn:
        rows = conn.execute(
            """SELECT topic, content, tags, last_updated FROM cognitive_cache
               WHERE topic LIKE ? OR content LIKE ?
               ORDER BY last_updated DESC""",
            (f"%{keyword}%", f"%{keyword}%")
        ).fetchall()
    return [tuple(r) for r in rows]


def delete_memory(topic):
    """Deletes a single memory entry by topic name."""
    with _connect() as conn:
        cursor = conn.execute("DELETE FROM cognitive_cache WHERE topic = ?", (topic,))
        conn.commit()
    if cursor.rowcount:
        print(f"🗑️  Deleted memory for topic: '{topic}'")
    else:
        print(f"⚠️  No memory found for topic: '{topic}'")


# ---------------------------------------------------------------------------
#  DECISION LOG
# ---------------------------------------------------------------------------

def log_decision(decision, rationale, tags=""):
    """
    Logs a specific architectural choice.

    Args:
        decision:  Short description of what was decided.
        rationale: Why this choice was made.
        tags:      Optional comma-separated tags (e.g. 'backend,api').
    """
    with _connect() as conn:
        conn.execute('''
            INSERT INTO decision_log (decision, rationale, tags, timestamp)
            VALUES (?, ?, ?, ?)
        ''', (decision, rationale, tags, datetime.now().isoformat()))
        conn.commit()
    print(f"📝 Logged decision: {decision}")


def read_decisions(limit=50, tag=None, keyword=None):
    """
    Reads decision log entries.

    Args:
        limit:   Max number of entries to return (newest first).
        tag:     Filter by tag substring.
        keyword: Search in decision or rationale text.

    Returns:
        List of (id, decision, rationale, tags, timestamp) tuples.
    """
    with _connect() as conn:
        query = "SELECT id, decision, rationale, tags, timestamp FROM decision_log"
        params = []
        conditions = []

        if tag:
            conditions.append("tags LIKE ?")
            params.append(f"%{tag}%")
        if keyword:
            conditions.append("(decision LIKE ? OR rationale LIKE ?)")
            params.extend([f"%{keyword}%", f"%{keyword}%"])

        if conditions:
            query += " WHERE " + " AND ".join(conditions)
        query += " ORDER BY timestamp DESC LIMIT ?"
        params.append(limit)

        rows = conn.execute(query, params).fetchall()
    return [tuple(r) for r in rows]


def delete_decision(decision_id):
    """Deletes a single decision by its numeric ID."""
    with _connect() as conn:
        cursor = conn.execute("DELETE FROM decision_log WHERE id = ?", (decision_id,))
        conn.commit()
    if cursor.rowcount:
        print(f"🗑️  Deleted decision #{decision_id}")
    else:
        print(f"⚠️  No decision found with id: {decision_id}")


# ---------------------------------------------------------------------------
#  UTILITIES
# ---------------------------------------------------------------------------

def export_all(filepath=None):
    """
    Exports the entire memory database to a JSON file.

    Args:
        filepath: Output path. Defaults to 'architect_memory_export.json'
                  in the same directory as the database.

    Returns:
        The filepath of the exported JSON.
    """
    if filepath is None:
        filepath = os.path.join(_script_dir, "architect_memory_export.json")

    with _connect() as conn:
        memories = conn.execute(
            "SELECT topic, content, tags, last_updated FROM cognitive_cache ORDER BY last_updated DESC"
        ).fetchall()
        decisions = conn.execute(
            "SELECT id, decision, rationale, tags, timestamp FROM decision_log ORDER BY timestamp DESC"
        ).fetchall()

    export = {
        "exported_at": datetime.now().isoformat(),
        "cognitive_cache": [
            {"topic": r["topic"], "content": r["content"], "tags": r["tags"], "last_updated": r["last_updated"]}
            for r in memories
        ],
        "decision_log": [
            {"id": r["id"], "decision": r["decision"], "rationale": r["rationale"],
             "tags": r["tags"], "timestamp": r["timestamp"]}
            for r in decisions
        ],
    }

    with open(filepath, "w", encoding="utf-8") as f:
        json.dump(export, f, indent=2, ensure_ascii=False)

    print(f"📦 Exported full memory to: {filepath}")
    return filepath


def import_from_json(filepath):
    """
    Imports memory from a previously exported JSON file.
    Existing entries with the same topic are overwritten.

    Args:
        filepath: Path to the JSON export file.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        data = json.load(f)

    for entry in data.get("cognitive_cache", []):
        update_memory(entry["topic"], entry["content"], entry.get("tags", ""))

    for entry in data.get("decision_log", []):
        log_decision(entry["decision"], entry["rationale"], entry.get("tags", ""))

    print(f"📥 Imported memory from: {filepath}")


def stats():
    """Prints a quick summary of the database contents."""
    with _connect() as conn:
        mem_count = conn.execute("SELECT COUNT(*) FROM cognitive_cache").fetchone()[0]
        dec_count = conn.execute("SELECT COUNT(*) FROM decision_log").fetchone()[0]
        oldest = conn.execute("SELECT MIN(last_updated) FROM cognitive_cache").fetchone()[0]
        newest = conn.execute("SELECT MAX(last_updated) FROM cognitive_cache").fetchone()[0]

    print(f"📊 Memory: {mem_count} topics | Decisions: {dec_count} logged")
    if oldest:
        print(f"   Oldest entry: {oldest}")
        print(f"   Newest entry: {newest}")


# ---------------------------------------------------------------------------
#  ENTRYPOINT
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    init_db()
    update_memory("system_status", "Memory lattice online and awaiting directives.", tags="system")
    stats()
