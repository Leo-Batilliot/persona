# Persona — Agrégateur de newsletters IA

Agrégateur d'actualités tech personnalisable piloté par chatbot. Aucune interface graphique — tout passe par le chat n8n. 100 % local, 100 % gratuit, RGPD-friendly.

## Stack

| Composant | Rôle |
|-----------|------|
| n8n | Moteur de workflows (chatbot + automatisations) |
| PostgreSQL | Base de données applicative (`persona`) |
| Ollama + llama3.2:3b | LLM local — classification d'intention + résumés d'articles |
| Gmail SMTP | Envoi des newsletters (mot de passe d'application) |

---

## Démarrage rapide

### 1. Prérequis

- Docker + Docker Compose
- Un compte Gmail avec un [mot de passe d'application](https://myaccount.google.com/apppasswords) activé

### 2. Configuration

```bash
cp .env.example .env
# Éditer .env : remplir POSTGRES_PASSWORD, N8N_BASIC_AUTH_PASSWORD, GMAIL_APP_PASSWORD
```

### 3. Lancer l'infra

```bash
docker compose up -d
# Vérifier : docker compose ps  → 3 conteneurs Up (n8n, postgres, ollama)
```

### 4. Télécharger le modèle Ollama

```bash
docker exec persona-ollama ollama pull llama3.2:3b
# ~2 Go, à faire une seule fois
```

### 5. Accéder à n8n

Ouvrir [http://localhost:5678](http://localhost:5678) — créer un compte owner au premier lancement.

---

## Création des credentials (une seule fois, dans n8n)

> Les credentials ne sont jamais dans les fichiers JSON — à créer manuellement.

| Nom dans n8n | Type | Paramètres |
|---|---|---|
| `persona-db` | Postgres | Host: `postgres`, Port: `5432`, DB: `persona`, User/Pass: voir `.env` |
| `persona-smtp` | SMTP | Host: `smtp.gmail.com`, Port: `587`, User: votre Gmail, Pass: mot de passe d'application |

---

## Import des workflows

Importer dans cet ordre via **⋮ → Import from File** :

| Ordre | Fichier | Description |
|---|---|---|
| 1 | `workflows/01-auth-router.json` | Chatbot : auth, routing Ollama, commandes |
| 2 | `workflows/02-user-management.json` | Inscription 6 étapes + modification préférences |
| 3 | `workflows/03-news-pipeline.json` | RSS → résumés Ollama → emails HTML |
| 4 | `workflows/04-unsubscribe.json` | Webhook désinscription |
| 5 | `workflows/05-maintenance.json` | Cron nettoyage registrations expirées |

---

## ⚠️ Configuration post-import (obligatoire)

Après import, les nodes **Execute Workflow** de WF1 ont `workflowId = 0` (placeholder). Mettre à jour avec les vrais IDs n8n :

| Node dans WF1 | Pointe vers |
|---|---|
| Continue Registration | ID de WF2 |
| WF2: Register | ID de WF2 |
| WF2: Update Prefs | ID de WF2 |
| WF3: Newsletter | ID de WF3 |
| WF4: Unsubscribe | ID de WF4 |

Les IDs sont visibles dans l'URL n8n quand le workflow est ouvert : `/workflow/<ID>`.

---

## Vérification de la base de données

Si le volume Postgres existait avant (ou après une mise à jour) :

```bash
# Appliquer les migrations manquantes
docker exec -i persona-postgres psql -U persona_admin -d persona \
  -f /docker-entrypoint-initdb.d/02-sessions.sql
docker exec -i persona-postgres psql -U persona_admin -d persona \
  -f /docker-entrypoint-initdb.d/03-pending-registrations.sql

# Vérifier les 5 tables
docker exec persona-postgres psql -U persona_admin -d persona -c "\dt"
# → users, news_cache, audit_log, feedback, sessions, pending_registrations
```

---

## Scénario de démo (keynote)

### 1. Inscription

Dans le chat n8n (WF1 actif) :

```
> register
← Bienvenue ! Quel pseudo souhaitez-vous ?
> AliceDemo
← Super ! Votre adresse email ?
> alice@example.com
← Choisissez un mot de passe
> MonPass123
← Vos centres d'intérêt ? (ex: AI, startup, cloud)
> AI, startup
← À quelle heure recevoir la newsletter ? (0-23)
> 9
← Acceptez-vous les CGU et la politique de confidentialité ? (oui/non)
> oui
← Compte créé !
```

### 2. Connexion

```
> login AliceDemo MonPass123
← Bienvenue AliceDemo !
```

### 3. Consulter son profil

```
> mes préférences
← Votre profil Persona :
   • Pseudo : AliceDemo
   • Email : alice@example.com
   • Intérêts : AI, startup
   • Newsletter à : 9h00
   ...
```

### 4. Newsletter immédiate

```
> newsletter
← (WF3 se déclenche, email envoyé)
```

### 5. Désinscription

Cliquer sur le lien en bas de l'email → page HTML de confirmation.

---

## Architecture des workflows

```
WF1 Auth & Router (29 nodes)
 ├─ Chat Trigger → Parse Input → pending_reg? → Continue Registration (WF2)
 └─ Get Session → Session Valid?
     ├─ TRUE → Prepare Prompt → Ollama → Parse Intent → Route Intent (Switch)
     │           ├─ register     → WF2
     │           ├─ update_prefs → WF2
     │           ├─ newsletter   → WF3
     │           ├─ unsubscribe  → WF4
     │           ├─ status       → Get User Profile → Profile Response
     │           ├─ help         → Help message
     │           └─ unknown      → Unknown message
     └─ FALSE → Login Command? → Authenticate (pgcrypto bcrypt) → Session → Welcome

WF2 User Management (27 nodes)   — inscription state machine + update préférences
WF3 News Pipeline (16 nodes)     — RSS HN+TC → Ollama résumés → emails HTML SMTP
WF4 Unsubscribe (9 nodes)        — webhook GET → désactiver compte → page HTML
WF5 Maintenance (3 nodes)        — cron daily 3h → purge pending_registrations
```

---

## Sécurité & RGPD

- Mots de passe hashés bcrypt via `pgcrypto` (jamais en clair, côté PostgreSQL)
- Sessions expirantes 24h, inscriptions partielles expirantes 1h
- Désinscription par token UUID (1 clic, sans login)
- `audit_log` : login_success, login_fail, newsletter_sent, unsubscribe
- XSS : `esc()` + `escAttr()` + validation schéma URL (`http:`/`https:` uniquement) dans emails HTML
- Aucune donnée ne quitte la machine (Ollama 100 % local)
