-- =====================================================================
--  PERSONA — Migration : table pending_registrations
--  Stockage temporaire des inscriptions multi-étapes en cours.
--  Supprimé à la complétion ou annulation. TTL 1h.
--
--  Note RGPD : cette table est équivalente à un "panier" de formulaire.
--  Elle ne persiste pas de données utilisateur au-delà de la session
--  d'inscription. Le password est hashé (bcrypt) dès la saisie.
-- =====================================================================

\connect persona;

CREATE TABLE IF NOT EXISTS pending_registrations (
    session_id    TEXT PRIMARY KEY,
    -- Étapes : ask_pseudo → ask_email → ask_password → ask_interests → ask_hour → ask_consent
    step          TEXT NOT NULL DEFAULT 'ask_pseudo',
    pseudo        TEXT,
    email         TEXT,
    password_hash TEXT,              -- hashé bcrypt via pgcrypto dès la saisie, jamais de clair
    interests     JSONB DEFAULT '[]'::jsonb,
    send_hour     INTEGER,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '1 hour'
);

CREATE INDEX IF NOT EXISTS idx_pending_reg_expires ON pending_registrations(expires_at);

-- Nettoyage manuel des entrées expirées (à lancer périodiquement ou via WF cron futur) :
-- DELETE FROM pending_registrations WHERE expires_at < now();
