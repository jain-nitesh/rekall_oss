# ReKall — Mobile-First Memory Engine

Save anything from your phone. AI organizes it. Search finds it years later.

**ReKall Cloud** (hosted, no setup) · **Self-hosted** (your server, your data)

---

## What is ReKall?

ReKall is a personal memory engine. Share a link from any app, snap a photo, or paste text — ReKall stores it, understands it with AI, and surfaces connections you'd never find manually.

### Features

| Feature | Description |
|---------|-------------|
| **Save anything** | URLs, photos, videos, and text via the mobile share sheet or Chrome extension |
| **AI extraction** | Auto-generates title, summary, category, and tags from every saved item |
| **Semantic search** | Find anything by meaning, not just keywords (vector + full-text) |
| **Connections** | AI discovers non-obvious links between items across your entire library |
| **Clusters** | Automatically groups related items into thematic collections |
| **Knowledge graph** | Visual map of entities and relationships across your saved content |
| **Wiki** | Auto-generated wiki pages for recurring topics and entities |
| **Brain / Chat** | Conversational interface — ask questions about your saved memories |
| **Spaces** | Shared spaces to save and explore content with others |
| **Collections** | Manually curate items into named lists |
| **OCR** | Extracts text from photos and screenshots |
| **Insights & Trending** | Surfaces what you've been saving and reading lately |
| **Chrome extension** | Save from the browser desktop and sync bookmarks |
| **Import bookmarks** | Bulk import existing browser bookmarks |

---

## Cloud vs Self-Hosted

| | ReKall Cloud | Self-Hosted |
|-|-------------|-------------|
| **Setup** | None — use the app immediately | Docker Compose on any server |
| **Data location** | Rekall servers | Your server |
| **Sign-in** | Google, Apple, or email + password | Email + password |
| **AI processing** | Managed (no API keys needed) | Ollama (free, local) or OpenAI (your key) |
| **Media storage** | Managed cloud storage | Your own S3, Cloudflare R2, or local MinIO |
| **Cost** | Subscription (coming soon) | Free — pay only for your own infrastructure |
| **Updates** | Automatic | Pull and redeploy |

Both options use the same published mobile app (App Store / Google Play). Choose your backend on first launch.

---

## Self-Hosting

### Prerequisites

- Docker + Docker Compose
- 2 GB RAM minimum (4 GB recommended if using Ollama for local AI)

### Quick Start

**1. Clone the repo**

```bash
git clone https://github.com/your-org/ReKall.git
cd ReKall
```

**2. Configure the environment**

```bash
cp ReKall_backend/.env.example ReKall_backend/.env
```

At minimum, set a secure JWT secret:

```bash
# Generate a random secret
python -c "import secrets; print(secrets.token_hex(32))"
```

Paste the output as `JWT_SECRET_KEY` in `ReKall_backend/.env`.

**3. Start the backend**

```bash
# With Ollama — free local AI, no API keys needed (recommended for self-hosting)
docker compose --profile ollama up -d

# With OpenAI — faster, requires OPENAI_API_KEY in your .env
docker compose up -d
```

**4. Pull AI models (Ollama only)**

Run this once after the containers start:

```bash
docker exec ReKall_ollama ollama pull llama3
docker exec ReKall_ollama ollama pull nomic-embed-text
docker exec ReKall_ollama ollama pull llava   # for image/video OCR
```

**5. Verify**

```bash
curl http://localhost:8000/health
```

**6. Connect the mobile app**

Install the ReKall app, tap **Connect your server**, and enter `http://your-server-ip:8000`.

---

### Configuration

`ReKall_backend/.env.example` documents every available option. Key sections:

#### AI Provider

```env
# Free local AI (default for self-hosting)
AI_PROVIDER=ollama
OLLAMA_BASE_URL=http://localhost:11434

# Or use OpenAI (faster, costs money)
AI_PROVIDER=openai
OPENAI_API_KEY=sk-...
```

#### Media Storage

Photos and videos require object storage. Three options:

```env
# Local development (MinIO, included in Docker Compose)
MEDIA_STORAGE_PROVIDER=minio
S3_ENDPOINT_URL=http://localhost:9000
S3_ACCESS_KEY_ID=minioadmin
S3_SECRET_ACCESS_KEY=minioadmin

# Cloudflare R2 (recommended for production self-hosting — generous free tier)
MEDIA_STORAGE_PROVIDER=r2
S3_ENDPOINT_URL=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
S3_ACCESS_KEY_ID=your-r2-token-id
S3_SECRET_ACCESS_KEY=your-r2-token-secret
S3_BUCKET_NAME=ReKall-media

# AWS S3
MEDIA_STORAGE_PROVIDER=s3
S3_REGION=us-east-1
S3_ACCESS_KEY_ID=your-key
S3_SECRET_ACCESS_KEY=your-secret
S3_BUCKET_NAME=ReKall-media
```

#### Email (Optional)

Required only if you want password-reset emails:

```env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=you@gmail.com
SMTP_PASSWORD=your-app-password
```

---

### VPS Deployment

Any VPS with Docker works (DigitalOcean, Hetzner, Linode). Recommended: 2 vCPU / 4 GB RAM.

- Open port 8000 in your firewall (or 443 if using a reverse proxy)
- Use nginx or Caddy with HTTPS for production
- Replace `http://your-server-ip:8000` with your `https://your-domain.com` in the mobile app

---

## Mobile App

Install **ReKall** from the App Store or Google Play. On first launch:

1. Swipe through the onboarding carousel
2. Choose a backend:
   - **ReKall Cloud** — no setup, start saving immediately
   - **Connect your server** — enter your self-hosted backend URL; the app validates connectivity before proceeding
3. Sign in (Google/Apple for Cloud; email + password for self-hosted)

To switch backends later: go to **Settings → Switch server**. This clears your local session and returns to server selection.

---

## Architecture

```
                 ┌──────────────────┐   ┌──────────────────┐
                 │   Mobile App     │   │ Chrome Extension │
                 │ Flutter · iOS/Android│   │   Vanilla JS     │
                 └────────┬─────────┘   └────────┬─────────┘
                          │                       │
                          └──────────┬────────────┘
                                     │ HTTPS / REST
                                     ▼
                 ┌───────────────────────────────────────────┐
                 │            Backend  (FastAPI)             │
                 │  ┌─────────────┐  ┌─────────────────────┐│
                 │  │  API Layer  │  │    AI Services      ││
                 │  │ auth/routes │  │ extract·embed·chat  ││
                 │  └─────────────┘  └─────────────────────┘│
                 │  ┌──────────────────────────────────────┐ │
                 │  │       Background Processor           │ │
                 │  │  async jobs: OCR · links · entities  │ │
                 │  └──────────────────────────────────────┘ │
                 └──────┬──────────────────┬─────────────────┘
                        │                  │
            ┌───────────▼───────┐   ┌──────▼──────────────────┐
            │  PostgreSQL       │   │     AI Provider          │
            │  + pgvector       │   │  Ollama (local)          │
            │  content, vectors │   │  or OpenAI (cloud)       │
            └───────────────────┘   └──────────────────────────┘
                                    ┌──────────────────────────┐
                                    │     Media Storage        │
                                    │  MinIO · R2 · S3         │
                                    └──────────────────────────┘
```

| Component | Tech | Role |
|-----------|------|------|
| **Mobile App** | Flutter (iOS + Android) | Primary client — share sheet, camera, full UI |
| **Chrome Extension** | Vanilla JS | Save pages and sync bookmarks from desktop |
| **Backend** | FastAPI + Python | REST API, auth, AI orchestration, background jobs |
| **Database** | PostgreSQL + pgvector | Content, metadata, and semantic embeddings |
| **AI Provider** | Ollama or OpenAI | Extraction, embedding, classification, and chat |
| **Media Storage** | MinIO / Cloudflare R2 / S3 | Photo and video object storage |

---

## Development

### Backend

```bash
cd ReKall_backend
pip install -r requirements.txt
cp .env.example .env   # edit as needed
uvicorn main:app --reload
```

API docs available at `http://localhost:8000/docs` (Swagger) and `/redoc`.

### Mobile

```bash
cd ReKall_mobile
flutter pub get
flutter run
```

### Chrome Extension

Load `ReKall_chrome_extension/` as an unpacked extension in Chrome (`chrome://extensions` → Developer mode → Load unpacked).

---

## License

AGPL-3.0. See [LICENSE](LICENSE).

Anyone can use, modify, and self-host freely. Derivative works must also be open-sourced under AGPL — this prevents a third party from running a competing closed-source hosted service without contributing back.
