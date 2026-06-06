-- =====================================================================
--  PERSONA - Initialisation de la base applicative
--  Joué automatiquement par Postgres au premier démarrage du volume.
--  Crée une base "persona" séparée de la base "n8n".
-- =====================================================================

CREATE DATABASE persona;

\connect persona;

-- Pour générer des UUID et des tokens aléatoires
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------
--  TABLE users
--  Cœur du système. Contient auth, préférences, et champs RGPD.
-- ---------------------------------------------------------------------
CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pseudo              TEXT UNIQUE NOT NULL,
    email               TEXT UNIQUE NOT NULL,

    -- AUTH : on ne stocke JAMAIS le mot de passe en clair.
    -- Hash bcrypt généré côté workflow (node Code / crypto).
    password_hash       TEXT NOT NULL,

    -- Rôle : 'user' par défaut, 'admin' réservé. Gate les commandes admin.
    role                TEXT NOT NULL DEFAULT 'user'
                        CHECK (role IN ('user', 'admin', 'advertiser')),

    -- Préférences newsletter
    interests           JSONB NOT NULL DEFAULT '[]'::jsonb,   -- ex: ["ai","space","crypto"]
    send_hour           INTEGER NOT NULL DEFAULT 8            -- heure d'envoi (0-23), timezone serveur
                        CHECK (send_hour BETWEEN 0 AND 23),
    custom_prompt       TEXT,                                 -- feature "could" : prompt perso

    -- Champs publics (feature "could" : référencer un autre user)
    public_bio          TEXT,
    profile_is_public   BOOLEAN NOT NULL DEFAULT FALSE,

    -- ============== RGPD ==============
    consent_given       BOOLEAN NOT NULL DEFAULT FALSE,       -- consentement explicite au stockage email
    consent_at          TIMESTAMPTZ,                          -- horodatage du consentement (preuve)
    unsubscribe_token   UUID NOT NULL DEFAULT gen_random_uuid(), -- token unique pour le lien de désinscription
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,        -- FALSE = désinscrit (soft delete)

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_email   ON users(email);
CREATE INDEX idx_users_pseudo  ON users(pseudo);
CREATE INDEX idx_users_active  ON users(is_active);
CREATE INDEX idx_users_unsub   ON users(unsubscribe_token);

-- ---------------------------------------------------------------------
--  TABLE news_cache
--  Stocke les news déjà récupérées pour dédoublonner entre exécutions
--  et permettre le fact-check / multi-format (features "could").
-- ---------------------------------------------------------------------
CREATE TABLE news_cache (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    url             TEXT UNIQUE NOT NULL,        -- clé de dédoublonnage
    source          TEXT NOT NULL,               -- nom de la source (ex: "TechCrunch")
    title           TEXT NOT NULL,
    raw_content     TEXT,                        -- contenu brut récupéré
    summary         TEXT,                        -- résumé généré par Ollama
    topics          JSONB DEFAULT '[]'::jsonb,   -- topics détectés, pour matcher les intérêts
    published_at    TIMESTAMPTZ,
    fetched_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_news_fetched ON news_cache(fetched_at);
CREATE INDEX idx_news_topics  ON news_cache USING GIN(topics);

-- ---------------------------------------------------------------------
--  TABLE audit_log
--  Trace les actions sensibles : tentatives d'auth, accès admin,
--  désinscriptions. Sert à la fois à la sécurité ET à la preuve RGPD.
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    id          BIGSERIAL PRIMARY KEY,
    user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    action      TEXT NOT NULL,        -- ex: 'login_success','login_fail','admin_attempt','unsubscribe'
    detail      JSONB,
    ip_hint     TEXT,                 -- info de session si dispo
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_user   ON audit_log(user_id);
CREATE INDEX idx_audit_action ON audit_log(action);
CREATE INDEX idx_audit_time   ON audit_log(created_at);

-- ---------------------------------------------------------------------
--  TABLE feedback  (feature "could" : commenter une newsletter passée)
-- ---------------------------------------------------------------------
CREATE TABLE feedback (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    comment     TEXT NOT NULL,        -- ex: "n'utilise plus cette source"
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
--  Trigger : maintient updated_at à jour automatiquement
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ---------------------------------------------------------------------
--  Donne tous les droits sur "persona" à l'utilisateur applicatif
-- ---------------------------------------------------------------------
-- (l'utilisateur est déjà superuser via POSTGRES_USER, donc rien à faire,
--  mais on le note ici pour la clarté en cas de durcissement futur)
