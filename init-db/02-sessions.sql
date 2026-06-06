-- =====================================================================
--  PERSONA — Migration : table sessions
--  Joué automatiquement si le volume est recréé après le 01-schema.sql.
--  Pour appliquer sur un volume existant (sans tout écraser) :
--    docker exec -i persona-postgres psql -U persona_admin -d persona \
--      -f /docker-entrypoint-initdb.d/02-sessions.sql
-- =====================================================================

\connect persona;

CREATE TABLE IF NOT EXISTS sessions (
    session_id   TEXT PRIMARY KEY,                          -- identifiant de session n8n (chatTrigger.sessionId)
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pseudo       TEXT NOT NULL,
    role         TEXT NOT NULL DEFAULT 'user',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at   TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '24 hours'
);

CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at);
