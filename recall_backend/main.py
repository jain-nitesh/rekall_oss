from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, HTMLResponse, FileResponse
from contextlib import asynccontextmanager
import asyncio
import logging
import sys
import html
import platform
import os
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from app.core.limiter import limiter
from app.core.config import settings
from app.middleware import SecurityHeadersMiddleware, RequestSizeLimitMiddleware

# Fix for Windows: Set event loop policy for subprocess support (required by Playwright)
if platform.system() == 'Windows':
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())
from app.api.routes import auth, content, notifications, categories, spaces, search, users, connections, import_bookmarks, collections, chrome_sync, trending, insights, knowledge_graph, entities, wiki, chat, health_checks
from app.services.background_processor import background_processor
from app.services.fcm_service import FCMService
from app.services.notification_scheduler import NotificationScheduler
from app.core.provider_manager import initialize_openai_provider, cleanup_openai_provider
from app.core.task_manager import TaskManager
from app.core.playwright_pool import PlaywrightPool

logger = logging.getLogger(__name__)

# Initialize task managers for bounded concurrency (prevents memory leaks)
ingestion_task_manager = TaskManager(
    max_concurrent=settings.max_concurrent_ingestion_tasks,
    name="IngestionTaskManager"
)
ai_task_manager = TaskManager(
    max_concurrent=settings.max_concurrent_ai_tasks,
    name="AITaskManager"
)

# Initialize Playwright browser pool (performance optimization)
playwright_pool = PlaywrightPool(pool_size=settings.playwright_pool_size) if settings.playwright_enabled else None

# Initialize FCM service
fcm_service = FCMService(settings.firebase_service_account_path)
notification_scheduler = NotificationScheduler(fcm_service)

# Log FCM initialization status
if fcm_service.initialized:
    logger.info(f"✅ FCM initialized successfully (project: {fcm_service.project_id})")
else:
    logger.warning("⚠️ FCM not initialized - push notifications will not work")
    logger.warning(f"Service account path: {settings.firebase_service_account_path}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan events for the FastAPI app.

    Runs on startup and shutdown to manage background tasks.
    """
    # Startup: Validate configuration and start services
    print("=" * 55)
    print("  STARTUP: Initializing ReKall Backend")
    print("=" * 55)
    
    # Validate required environment variables
    required_vars = {
        "JWT_SECRET_KEY": settings.jwt_secret_key,
        "DATABASE_URL": settings.database_url,
    }
    
    missing_vars = []
    for var_name, var_value in required_vars.items():
        if not var_value or var_value in ["your-secret-key-change-in-production", ""]:
            missing_vars.append(var_name)
    
    if missing_vars:
        logger.error(f"Missing or invalid required environment variables: {', '.join(missing_vars)}")
        print(f"ERROR: Missing required environment variables: {', '.join(missing_vars)}. Exiting.")
        sys.exit(1)

    # Validate JWT secret key strength
    if len(settings.jwt_secret_key) < 32:
        logger.error("JWT_SECRET_KEY must be at least 32 characters")
        print("ERROR: JWT_SECRET_KEY too short. Exiting.")
        sys.exit(1)

    # Recover items stuck in 'processing' status
    await background_processor.recover_stuck_items()

    # Initialize OpenAI provider singleton
    await initialize_openai_provider()
    logger.info("OpenAI provider initialized")

    # Register task managers in app state for access in routes/processors
    app.state.ingestion_task_manager = ingestion_task_manager
    app.state.ai_task_manager = ai_task_manager

    # Set task managers in background processor
    background_processor.set_task_managers(ingestion_task_manager, ai_task_manager)
    logger.info(f"Task managers initialized (ingestion: {settings.max_concurrent_ingestion_tasks}, ai: {settings.max_concurrent_ai_tasks})")

    # Initialize Playwright browser pool
    if playwright_pool:
        await playwright_pool.initialize()
        app.state.playwright_pool = playwright_pool
        logger.info(f"Playwright browser pool initialized ({settings.playwright_pool_size} browsers)")
    else:
        app.state.playwright_pool = None
        logger.info("Playwright browser pool disabled")

    # Start embedding + connection backfill as a background task
    from app.services.embedding_backfill import run_startup_backfill
    backfill_task = asyncio.create_task(run_startup_backfill())
    logger.info("Startup backfill task launched (embeddings + connections)")

    # Start periodic retry task for content processing
    retry_task = asyncio.create_task(
        background_processor.start_periodic_retry(interval_seconds=settings.retry_interval_seconds)
    )
    logger.info(f"Content processor started ({settings.retry_interval_seconds}s interval)")

    # Start notification scheduler task (every 1 minute)
    async def notification_scheduler_loop():
        """Run notification scheduler every minute"""
        while True:
            try:
                await notification_scheduler.run_scheduled_notifications()
            except Exception as e:
                logger.error(f"Error in notification scheduler: {e}")
                import traceback
                traceback.print_exc()
            await asyncio.sleep(60)  # Run every 60 seconds

    scheduler_task = asyncio.create_task(notification_scheduler_loop())
    logger.info("Notification scheduler started (1-minute interval)")

    print("  Background tasks started")
    print("=" * 55)

    yield  # App runs here

    # Shutdown: Stop background tasks
    print("=" * 55)
    print("  SHUTDOWN: Stopping background tasks...")

    # Stop backfill task
    backfill_task.cancel()
    try:
        await backfill_task
    except asyncio.CancelledError:
        pass

    # Stop content processor
    background_processor.stop_periodic_retry()
    retry_task.cancel()
    try:
        await retry_task
    except asyncio.CancelledError:
        pass

    # Stop notification scheduler
    scheduler_task.cancel()
    try:
        await scheduler_task
    except asyncio.CancelledError:
        pass

    # Cleanup OpenAI provider singleton
    await cleanup_openai_provider()
    logger.info("OpenAI provider cleaned up")

    # Shutdown task managers
    await ingestion_task_manager.shutdown()
    await ai_task_manager.shutdown()
    logger.info("Task managers shut down")

    # Cleanup Playwright browser pool
    if playwright_pool:
        await playwright_pool.cleanup()
        logger.info("Playwright browser pool cleaned up")

    print("  Background tasks stopped")
    print("=" * 55)


# Initialize FastAPI app with lifespan events
app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    debug=settings.debug,
    lifespan=lifespan,
    # Hide API docs in production
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json"
)

# Add rate limiter to app
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Security Headers Middleware - adds security headers to all responses
app.add_middleware(SecurityHeadersMiddleware)

# Request Size Limit Middleware - prevents large payload DoS attacks
app.add_middleware(RequestSizeLimitMiddleware, max_upload_size=10 * 1024 * 1024)  # 10 MB limit

# CORS Middleware - use environment-based configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# Global exception handler for unhandled exceptions
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Handle unhandled exceptions globally."""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "detail": "An internal server error occurred. Please try again later."
        }
    )

# Register API routes
# All authentication routes will be available under /api/auth
# Examples: /api/auth/signup, /api/auth/login, /api/auth/me
app.include_router(auth.router, prefix="/api")

# Content management routes will be available under /api/content
# Examples: /api/content/ingest, /api/content, /api/content/{id}
app.include_router(content.router, prefix="/api")

# Notification routes will be available under /api/notifications
# Examples: /api/notifications/settings, /api/notifications/devices
app.include_router(notifications.router, prefix="/api")

# Category routes will be available under /api/categories
# Examples: /api/categories, /api/categories/{id}
app.include_router(categories.router, prefix="/api")

# Spaces routes will be available under /api/spaces
# Examples: /api/spaces, /api/spaces/{id}, /api/spaces/{id}/members
app.include_router(spaces.router, prefix="/api")

# Search routes will be available under /api/search
# Examples: /api/search/history
app.include_router(search.router, prefix="/api")

# User routes will be available under /api/user
# Examples: /api/user/usage-stats, /api/user/preferences
app.include_router(users.router, prefix="/api")

# Connections routes will be available under /api/connections
# Examples: /api/connections, /api/connections/{id}, /api/connections/daily
app.include_router(connections.router, prefix="/api")

# Clusters routes
from app.api.routes import clusters
app.include_router(clusters.router, prefix="/api")

# Import routes will be available under /api/import
# Examples: /api/import/chrome, /api/import/pocket, /api/import/status/{id}
app.include_router(import_bookmarks.router, prefix="/api")

# Collections routes will be available under /api/collections
# Examples: /api/collections, /api/collections/explore, /api/collections/{slug}
app.include_router(collections.router, prefix="/api")

# Chrome extension sync routes will be available under /api/chrome-sync
# Examples: /api/chrome-sync/check-urls, /api/chrome-sync/bulk-ingest, /api/chrome-sync/map-to-spaces
app.include_router(chrome_sync.router, prefix="/api")

# Trending news routes will be available under /api/trending
# Examples: /api/trending/news
app.include_router(trending.router, prefix="/api")

# Insights routes: /api/insights
app.include_router(insights.router, prefix="/api")

# Knowledge graph routes: /api/knowledge-graph
app.include_router(knowledge_graph.router, prefix="/api")

# Entity routes: /api/entities
app.include_router(entities.router, prefix="/api")

# Wiki routes: /api/wiki
app.include_router(wiki.router, prefix="/api")

# Chat routes: /api/chat
app.include_router(chat.router, prefix="/api")

# Health check routes: /api/health-checks
app.include_router(health_checks.router, prefix="/api")


@app.get("/")
async def root():
    """Root endpoint with API info."""
    if settings.is_production:
        return {
            "app": settings.app_name,
            "version": settings.app_version
        }

    # Development/Staging: Include internal details
    return {
        "app": settings.app_name,
        "version": settings.app_version,
        "environment": settings.environment,
        "ai_provider": settings.ai_provider,
        "extraction_model": settings.extraction_model,
        "embedding_model": settings.embedding_model
    }


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    if settings.is_production:
        return {"status": "healthy"}

    # Development/Staging: Include internal details
    return {
        "status": "healthy",
        "environment": settings.environment,
        "ai_provider": settings.ai_provider
    }


@app.get("/.well-known/apple-app-site-association")
async def apple_app_site_association():
    """
    Serve Apple App Site Association file for iOS Universal Links.

    This file allows iOS to automatically open the app when users click
    links to <YOUR_DEEP_LINK_URL>/invite/* instead of opening Safari.

    Must be served:
    - Over HTTPS (in production)
    - With application/json content-type
    - Without .json extension

    To verify: https://search.developer.apple.com/appsearch-validation-tool/
    """
    file_path = os.path.join(os.path.dirname(__file__), ".well-known", "apple-app-site-association")

    if not os.path.exists(file_path):
        return JSONResponse(
            status_code=status.HTTP_404_NOT_FOUND,
            content={"detail": "Apple App Site Association file not found"}
        )

    return FileResponse(
        path=file_path,
        media_type="application/json",
        headers={
            "Content-Type": "application/json",
            "Cache-Control": "public, max-age=3600"  # Cache for 1 hour
        }
    )


@app.get("/.well-known/assetlinks.json")
async def android_asset_links():
    """
    Serve Android Asset Links file for Android App Links.

    This file allows Android to automatically open the app when users click
    links to <YOUR_DEEP_LINK_URL>/invite/* instead of showing an app chooser.

    Must be served:
    - Over HTTPS (in production)
    - With application/json content-type
    - At exactly /.well-known/assetlinks.json

    To verify: https://developers.google.com/digital-asset-links/tools/generator
    """
    file_path = os.path.join(os.path.dirname(__file__), ".well-known", "assetlinks.json")

    if not os.path.exists(file_path):
        return JSONResponse(
            status_code=status.HTTP_404_NOT_FOUND,
            content={"detail": "Asset Links file not found"}
        )

    return FileResponse(
        path=file_path,
        media_type="application/json",
        headers={
            "Content-Type": "application/json",
            "Cache-Control": "public, max-age=3600"  # Cache for 1 hour
        }
    )


@app.get("/c/{slug}", response_class=HTMLResponse)
async def public_collection_page(slug: str):
    """
    Public web page for a collection. Renders HTML with OG meta tags for social sharing.
    Shows collection items and 'Open in ReCall' deep link.
    """
    from app.db.session import get_db_context

    async with get_db_context() as db:
        from sqlalchemy import text as sql_text
        result = await db.execute(
            sql_text("""
                SELECT pc.*, u.name as creator_name
                FROM public_collections pc
                JOIN users u ON u.id = pc.user_id
                WHERE pc.slug = :slug AND pc.is_published = true
            """),
            {'slug': slug}
        )
        collection = result.fetchone()

    if not collection:
        return HTMLResponse(content="<h1>Collection not found</h1>", status_code=404)

    _title = html.escape(collection.title or "")
    _creator = html.escape(collection.creator_name or "")
    raw_desc = collection.description or f"A curated collection by {collection.creator_name or ''}"
    _desc = html.escape(raw_desc)
    html_content = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>{_title} - ReCall Collection</title>
        <meta name="description" content="{_desc}">
        <meta property="og:title" content="{_title}">
        <meta property="og:description" content="{_desc}">
        <meta property="og:type" content="website">
        <meta property="og:site_name" content="ReCall">
        <meta name="twitter:card" content="summary">
        <meta name="twitter:title" content="{_title}">
        <meta name="twitter:description" content="{_desc}">
        <style>
            * {{ margin: 0; padding: 0; box-sizing: border-box; }}
            body {{
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: linear-gradient(135deg, #0ea5e9 0%, #6366f1 100%);
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                padding: 20px;
            }}
            .container {{
                background: white;
                border-radius: 20px;
                box-shadow: 0 20px 60px rgba(0,0,0,0.3);
                max-width: 600px;
                width: 100%;
                padding: 40px 30px;
                text-align: center;
            }}
            .logo {{ font-size: 32px; font-weight: bold; color: #0ea5e9; margin-bottom: 8px; }}
            h1 {{ font-size: 24px; color: #1a202c; margin-bottom: 8px; }}
            .creator {{ color: #718096; font-size: 14px; margin-bottom: 16px; }}
            .description {{ color: #4a5568; font-size: 15px; line-height: 1.6; margin-bottom: 24px; }}
            .stats {{ display: flex; justify-content: center; gap: 24px; margin-bottom: 24px; color: #718096; font-size: 13px; }}
            .btn {{
                display: inline-block;
                padding: 14px 32px;
                border-radius: 12px;
                font-size: 16px;
                font-weight: 600;
                text-decoration: none;
                background: linear-gradient(135deg, #0ea5e9, #6366f1);
                color: white;
                margin-bottom: 12px;
            }}
            .store-links {{ margin-top: 16px; color: #718096; font-size: 13px; }}
            .store-links a {{ color: #0ea5e9; text-decoration: none; }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="logo">ReCall</div>
            <h1>{_title}</h1>
            <p class="creator">by {_creator}</p>
            <p class="description">{_desc}</p>
            <div class="stats">
                <span>{collection.view_count} views</span>
                <span>{collection.fork_count} forks</span>
            </div>
            <a href="rekall://collection/{slug}" class="btn">Open in ReCall</a>
            <div class="store-links">
                Don't have ReCall? <a href="{settings.app_store_url}">App Store</a> |
                <a href="{settings.play_store_url}">Play Store</a>
            </div>
        </div>
        <script>
            const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
            if (isMobile) {{ window.location.href = "rekall://collection/{slug}"; }}
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)


@app.get("/invite/{token}", response_class=HTMLResponse)
async def invite_fallback(token: str):
    """
    Web fallback page for space invitations.

    This page is shown when:
    1. User clicks invite link and app is not installed
    2. User clicks invite link in a desktop browser

    The page attempts to open the app via deep link, and if that fails,
    shows download buttons for App Store and Play Store.
    """
    html_content = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Join Space - ReKall</title>
        <meta name="description" content="You've been invited to join a shared space on ReKall">

        <!-- Open Graph / Social sharing -->
        <meta property="og:title" content="Join Space - ReKall">
        <meta property="og:description" content="You've been invited to collaborate on ReKall">
        <meta property="og:type" content="website">

        <style>
            * {{
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }}

            body {{
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                padding: 20px;
            }}

            .container {{
                background: white;
                border-radius: 20px;
                box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
                max-width: 500px;
                width: 100%;
                padding: 40px 30px;
                text-align: center;
            }}

            .logo {{
                width: 80px;
                height: 80px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                border-radius: 20px;
                margin: 0 auto 20px;
                display: flex;
                align-items: center;
                justify-content: center;
                font-size: 40px;
                color: white;
                font-weight: bold;
            }}

            h1 {{
                font-size: 28px;
                color: #1a202c;
                margin-bottom: 10px;
            }}

            p {{
                color: #718096;
                font-size: 16px;
                line-height: 1.6;
                margin-bottom: 30px;
            }}

            .status {{
                padding: 15px 20px;
                border-radius: 12px;
                margin-bottom: 25px;
                font-size: 14px;
                font-weight: 500;
            }}

            .status.checking {{
                background: #edf2f7;
                color: #4a5568;
            }}

            .status.app-detected {{
                background: #c6f6d5;
                color: #22543d;
            }}

            .status.no-app {{
                background: #fed7d7;
                color: #742a2a;
            }}

            .buttons {{
                display: flex;
                flex-direction: column;
                gap: 12px;
            }}

            .btn {{
                display: inline-flex;
                align-items: center;
                justify-content: center;
                padding: 16px 24px;
                border-radius: 12px;
                font-size: 16px;
                font-weight: 600;
                text-decoration: none;
                transition: all 0.2s;
                cursor: pointer;
                border: none;
            }}

            .btn-primary {{
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
            }}

            .btn-primary:hover {{
                transform: translateY(-2px);
                box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
            }}

            .btn-secondary {{
                background: #f7fafc;
                color: #2d3748;
                border: 2px solid #e2e8f0;
            }}

            .btn-secondary:hover {{
                background: #edf2f7;
            }}

            .store-badges {{
                display: flex;
                gap: 12px;
                justify-content: center;
                margin-top: 15px;
            }}

            .store-badge {{
                height: 50px;
                transition: transform 0.2s;
            }}

            .store-badge:hover {{
                transform: scale(1.05);
            }}

            .divider {{
                margin: 25px 0;
                color: #cbd5e0;
                font-size: 14px;
            }}

            #spinner {{
                border: 3px solid #f3f4f6;
                border-top: 3px solid #667eea;
                border-radius: 50%;
                width: 40px;
                height: 40px;
                animation: spin 1s linear infinite;
                margin: 0 auto 20px;
            }}

            @keyframes spin {{
                0% {{ transform: rotate(0deg); }}
                100% {{ transform: rotate(360deg); }}
            }}

            .hidden {{
                display: none;
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="logo">R</div>
            <h1>You're Invited!</h1>
            <p>You've been invited to join a shared space on ReKall - Your Memory, Organized.</p>

            <div id="checking" class="status checking">
                <div id="spinner"></div>
                Checking for ReKall app...
            </div>

            <div id="app-detected" class="status app-detected hidden">
                ✓ App detected! Opening ReKall...
            </div>

            <div id="no-app" class="status no-app hidden">
                ReKall app not found
            </div>

            <div id="install-instructions" class="status hidden" style="background: #fff7ed; color: #9a3412; border-left: 4px solid #f97316;">
                <strong>📱 After installing:</strong><br>
                Click this invite link again to join the space!
            </div>

            <div id="buttons" class="buttons hidden">
                <button onclick="openApp()" class="btn btn-primary">
                    Open in ReKall App
                </button>

                <div class="divider">or download the app</div>

                <div class="store-badges">
                    <a href="{settings.app_store_url}" target="_blank" rel="noopener" onclick="showInstallInstructions()">
                        <img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='135' height='40'%3E%3Crect width='135' height='40' rx='5' fill='black'/%3E%3Ctext x='50%25' y='50%25' fill='white' font-family='Arial' font-size='12' text-anchor='middle' dominant-baseline='middle'%3EApp Store%3C/text%3E%3C/svg%3E"
                             alt="Download on App Store"
                             class="store-badge">
                    </a>
                    <a href="{settings.play_store_url}" target="_blank" rel="noopener" onclick="showInstallInstructions()">
                        <img src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='135' height='40'%3E%3Crect width='135' height='40' rx='5' fill='black'/%3E%3Ctext x='50%25' y='50%25' fill='white' font-family='Arial' font-size='12' text-anchor='middle' dominant-baseline='middle'%3EPlay Store%3C/text%3E%3C/svg%3E"
                             alt="Get it on Google Play"
                             class="store-badge">
                    </a>
                </div>
            </div>
        </div>

        <script>
            const token = "{token}";
            const customSchemeUrl = "rekall://invite/" + token;

            // Detect platform
            const isAndroid = /Android/i.test(navigator.userAgent);
            const isIOS = /iPhone|iPad|iPod/i.test(navigator.userAgent);
            const isMobile = isAndroid || isIOS;

            let appOpened = false;
            let attemptCount = 0;

            function openApp() {{
                attemptCount++;

                // Show checking status
                document.getElementById('no-app').classList.add('hidden');
                document.getElementById('install-instructions').classList.add('hidden');
                document.getElementById('checking').classList.remove('hidden');

                // Try to open the app using custom URL scheme
                // This works on both Android and iOS if app is installed
                window.location.href = customSchemeUrl;

                // Monitor if app opened
                setTimeout(() => {{
                    if (!appOpened && !document.hidden) {{
                        // App didn't open, show download options
                        document.getElementById('checking').classList.add('hidden');
                        document.getElementById('no-app').classList.remove('hidden');
                        document.getElementById('install-instructions').classList.remove('hidden');
                    }}
                }}, 2000);
            }}

            // On page load
            window.addEventListener('load', () => {{
                if (isMobile) {{
                    // On mobile, auto-try to open app
                    document.getElementById('checking').classList.remove('hidden');
                    setTimeout(() => {{
                        openApp();
                    }}, 500);
                }} else {{
                    // On desktop, show buttons immediately
                    document.getElementById('checking').classList.add('hidden');
                    document.getElementById('buttons').classList.remove('hidden');
                }}
            }});

            // Track visibility change (indicates app opened)
            document.addEventListener('visibilitychange', () => {{
                if (document.hidden) {{
                    appOpened = true;
                    document.getElementById('checking').classList.add('hidden');
                    document.getElementById('no-app').classList.add('hidden');
                    document.getElementById('install-instructions').classList.add('hidden');
                    document.getElementById('app-detected').classList.remove('hidden');
                }}
            }});

            // Track page blur (app might have opened)
            window.addEventListener('blur', () => {{
                appOpened = true;
            }});

            // Show install instructions when user clicks store badge
            function showInstallInstructions() {{
                setTimeout(() => {{
                    document.getElementById('install-instructions').classList.remove('hidden');
                }}, 500);
            }}
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)


if __name__ == "__main__":
    import uvicorn

    # Windows fix: Ensure event loop policy is set before uvicorn starts
    if platform.system() == 'Windows':
        asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())
        # On Windows with reload, the subprocess won't inherit the policy
        # So we disable reload when Playwright is enabled on Windows
        if settings.playwright_enabled and settings.debug:
            logger.warning("⚠️ Reload mode disabled on Windows when Playwright is enabled")
            logger.warning("⚠️ Restart the server manually to see code changes")

    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug if platform.system() != 'Windows' or not settings.playwright_enabled else False
    )
