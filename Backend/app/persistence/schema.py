from __future__ import annotations

import sqlite3


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS jobs (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    parent_job_id TEXT,
    chain_step_id TEXT,
    status TEXT NOT NULL,
    progress REAL NOT NULL,
    status_text TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    result_image_id TEXT,
    result_json TEXT,
    error TEXT,
    cancel_requested INTEGER NOT NULL DEFAULT 0,
    cancel_requested_at TEXT,
    cancelled_at TEXT,
    started_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS images (
    id TEXT PRIMARY KEY,
    status TEXT NOT NULL,
    media_type TEXT NOT NULL DEFAULT 'image',
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    poster_path TEXT,
    poster_mime_type TEXT,
    thumbnail_path TEXT,
    thumbnail_mime_type TEXT,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    prompt TEXT NOT NULL,
    default_positive_prompt TEXT NOT NULL,
    default_negative_prompt TEXT NOT NULL,
    final_positive_prompt TEXT NOT NULL,
    model_id TEXT NOT NULL,
    loras_json TEXT NOT NULL,
    tags_json TEXT NOT NULL DEFAULT '[]',
    caption TEXT NOT NULL DEFAULT '',
    num_inference_steps INTEGER NOT NULL DEFAULT 40,
    guidance_scale REAL NOT NULL DEFAULT 5.0,
    image_orientation TEXT NOT NULL DEFAULT 'landscape',
    source_image_id TEXT,
    scale_factor REAL,
    is_upscaled INTEGER NOT NULL DEFAULT 0,
    duration_seconds REAL,
    generation_duration_seconds REAL,
    fps INTEGER,
    num_frames INTEGER,
    loop_video INTEGER NOT NULL DEFAULT 0,
    rating INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    stored_at TEXT,
    deleted_at TEXT
);

CREATE TABLE IF NOT EXISTS asset_ratings (
    asset_type TEXT NOT NULL,
    asset_id TEXT NOT NULL,
    rating INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (asset_type, asset_id)
);

CREATE TABLE IF NOT EXISTS deleted_assets (
    asset_type TEXT NOT NULL,
    asset_id TEXT NOT NULL,
    PRIMARY KEY (asset_type, asset_id)
);

CREATE TABLE IF NOT EXISTS chat_sessions (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    model_name TEXT NOT NULL,
    system_message TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chat_messages (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    thinking TEXT,
    tool_traces_json TEXT,
    context_image_id TEXT,
    context_image_path TEXT,
    context_image_mime_type TEXT,
    model_name TEXT,
    total_duration_ns INTEGER,
    load_duration_ns INTEGER,
    prompt_eval_count INTEGER,
    prompt_eval_duration_ns INTEGER,
    eval_count INTEGER,
    eval_duration_ns INTEGER,
    summarized_into_memory INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chat_message_attachments (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    attachment_index INTEGER NOT NULL,
    context_image_id TEXT,
    context_image_path TEXT,
    context_image_mime_type TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chat_session_summaries (
    session_id TEXT PRIMARY KEY,
    summary_text TEXT NOT NULL,
    covered_through_message_id TEXT,
    updated_at TEXT NOT NULL
);
"""


REQUIRED_COLUMNS: tuple[tuple[str, str], ...] = (
    ("jobs", "parent_job_id TEXT"),
    ("jobs", "chain_step_id TEXT"),
    ("jobs", "result_json TEXT"),
    ("jobs", "cancel_requested INTEGER NOT NULL DEFAULT 0"),
    ("jobs", "cancel_requested_at TEXT"),
    ("jobs", "cancelled_at TEXT"),
    ("jobs", "started_at TEXT"),
    ("images", "rating INTEGER NOT NULL DEFAULT 0"),
    ("images", "deleted_at TEXT"),
    ("images", "media_type TEXT NOT NULL DEFAULT 'image'"),
    ("images", "poster_path TEXT"),
    ("images", "poster_mime_type TEXT"),
    ("images", "thumbnail_path TEXT"),
    ("images", "thumbnail_mime_type TEXT"),
    ("images", "tags_json TEXT NOT NULL DEFAULT '[]'"),
    ("images", "caption TEXT NOT NULL DEFAULT ''"),
    ("chat_sessions", "system_message TEXT NOT NULL DEFAULT ''"),
    ("chat_messages", "context_image_path TEXT"),
    ("chat_messages", "context_image_mime_type TEXT"),
    ("images", "num_inference_steps INTEGER NOT NULL DEFAULT 40"),
    ("images", "guidance_scale REAL NOT NULL DEFAULT 5.0"),
    ("images", "image_orientation TEXT NOT NULL DEFAULT 'landscape'"),
    ("images", "duration_seconds REAL"),
    ("images", "generation_duration_seconds REAL"),
    ("images", "fps INTEGER"),
    ("images", "num_frames INTEGER"),
    ("images", "loop_video INTEGER NOT NULL DEFAULT 0"),
    ("asset_ratings", "rating INTEGER NOT NULL DEFAULT 0"),
    ("chat_messages", "thinking TEXT"),
    ("chat_messages", "tool_traces_json TEXT"),
    ("chat_messages", "context_image_id TEXT"),
    ("chat_messages", "model_name TEXT"),
    ("chat_messages", "total_duration_ns INTEGER"),
    ("chat_messages", "load_duration_ns INTEGER"),
    ("chat_messages", "prompt_eval_count INTEGER"),
    ("chat_messages", "prompt_eval_duration_ns INTEGER"),
    ("chat_messages", "eval_count INTEGER"),
    ("chat_messages", "eval_duration_ns INTEGER"),
    ("chat_messages", "summarized_into_memory INTEGER NOT NULL DEFAULT 0"),
)


INDEX_SQL: tuple[str, ...] = (
    """
    CREATE INDEX IF NOT EXISTS idx_images_status_created_at
    ON images(status, created_at DESC, id DESC)
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_images_status_media_type
    ON images(status, media_type)
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_images_status_model_id
    ON images(status, model_id)
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_images_status_rating
    ON images(status, rating)
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_images_status_deleted_at
    ON images(status, deleted_at)
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_chat_sessions_updated_at
    ON chat_sessions(updated_at DESC, created_at DESC, id DESC)
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_chat_messages_session_created_at
    ON chat_messages(session_id, created_at ASC, id ASC)
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_chat_messages_session_summary
    ON chat_messages(session_id, summarized_into_memory, created_at ASC, id ASC)
    """,
    """
    CREATE INDEX IF NOT EXISTS idx_chat_message_attachments_message
    ON chat_message_attachments(message_id, attachment_index ASC, id ASC)
    """,
)


def initialize_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA_SQL)
    for table, column_definition in REQUIRED_COLUMNS:
        ensure_column(conn, table, column_definition)
    migrate_gif_media_type(conn)
    for statement in INDEX_SQL:
        conn.execute(statement)


def ensure_column(
    conn: sqlite3.Connection,
    table: str,
    column_definition: str,
) -> None:
    column_name = column_definition.split()[0]
    existing_columns = {
        row["name"] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()
    }
    if column_name not in existing_columns:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column_definition}")


def migrate_gif_media_type(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        UPDATE images
        SET media_type = 'gif'
        WHERE media_type = 'image' AND lower(mime_type) = 'image/gif'
        """
    )
