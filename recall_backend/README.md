# ReKall Backend

FastAPI backend for ReKall - *Your Memory, Organized*.

## Features

- **Provider-Agnostic AI**: Switch between Ollama (local) and OpenAI (production) via environment variables
- **PostgreSQL + pgvector**: Semantic search with vector embeddings
- **JWT Authentication**: Secure user authentication
- **Alembic Migrations**: Database schema versioning

## Quick Start

### Option 1: Docker Compose (Recommended)

The easiest way to run the backend is using Docker Compose, which sets up PostgreSQL with pgvector and optionally Ollama:

1. **Set Environment Variables** (optional, defaults are provided):
   ```bash
   # Create .env file or set environment variables
   export JWT_SECRET_KEY=your-secret-key-min-32-characters
   export AI_PROVIDER=ollama  # or "openai"
   export OPENAI_API_KEY=your-key-if-using-openai
   ```

2. **Start Services**:
   ```bash
   docker-compose up -d
   ```

   This will:
   - Start PostgreSQL with pgvector extension
   - Start the backend API (runs database setup and migrations automatically)
   - Optionally start Ollama (if using Ollama as AI provider)

3. **View Logs**:
   ```bash
   docker-compose logs -f backend
   ```

4. **Stop Services**:
   ```bash
   docker-compose down
   ```

The API will be available at `http://localhost:8000`

**Note**: If using Ollama, you may need to pull models manually:
```bash
docker exec -it ReKall_ollama ollama pull llama3
docker exec -it ReKall_ollama ollama pull nomic-embed-text
```

### Option 2: Manual Setup

### 1. Environment Setup

Copy the example environment file and configure:

```bash
cp .env.example .env
```

Edit `.env` to set your configuration:
- Set `AI_PROVIDER=ollama` for local development
- Set `AI_PROVIDER=openai` for production (requires `OPENAI_API_KEY`)

### 2. Install Dependencies

```bash
pip install -r requirements.txt
```

### 3. Database Setup

Ensure PostgreSQL is running with pgvector extension:

```sql
CREATE DATABASE ReKall;
\c ReKall
CREATE EXTENSION vector;
```

### 4. Run Migrations

```bash
alembic upgrade head
```

### 5. Start Server

```bash
python main.py
```

Or with uvicorn:

```bash
uvicorn main:app --reload
```

The API will be available at `http://localhost:8000`

## AI Provider Configuration

### Ollama (Local/Testing)
- Ensure Ollama is running: `ollama serve`
- Models required: `llama3`, `nomic-embed-text`
- Set `AI_PROVIDER=ollama` in `.env`

### OpenAI (Production)
- Get API key from OpenAI
- Set `OPENAI_API_KEY` in `.env`
- Set `AI_PROVIDER=openai` in `.env`

## AI Service Methods

The `AIProvider` abstract base class defines four methods, each implemented in both `OllamaProvider` and `OpenAIProvider`:

### `extract_content(url, title, content, provided_source_app?)`
Extracts structured metadata from web content: title, bullet-point summary, category, tags, reading time, and source app. Used during content ingestion.

### `generate_embedding(text)`
Produces a vector embedding for semantic similarity search. Ollama uses `nomic-embed-text` (768 dims), OpenAI uses `text-embedding-3-small` (1536 dims).

### `generate_connection_explanation(source_title, source_summary, target_title, target_summary)`
Evaluates whether two content items share an insightful, non-obvious connection. Returns a verdict (`INSIGHTFUL` or `OBVIOUS`) and a 1-2 sentence explanation. Used as a quality gate during connection discovery — only `INSIGHTFUL` connections are persisted.

- Temperature: 0.5 | Max tokens: 150
- Fallback: returns `OBVIOUS` with no explanation (connection is skipped)

### `generate_cluster_description(item_titles, item_summaries, item_categories?)`
Generates a thematic label (max 80 chars), 1-2 sentence description, and dominant category for a cluster of related items. Receives both titles and summaries (truncated to 100 chars each, max 20 items) for richer context.

- Temperature: 0.4 | Max tokens: 200
- Fallback: deterministic label from most common category (e.g., "technology Collection"), description listing first two titles

## Project Structure

```
Recall_backend/
├── app/
│   ├── core/          # Configuration, security
│   ├── api/           # API endpoints
│   ├── models/        # SQLAlchemy models
│   ├── services/      # Business logic
│   └── db/            # Database utilities
├── alembic/           # Database migrations
├── main.py            # Application entry point
└── requirements.txt   # Python dependencies
```

## API Documentation

Once running, visit:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`
