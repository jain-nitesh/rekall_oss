FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies including Playwright browser dependencies
# Playwright requires additional system libraries for Chromium
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    netcat-traditional \
    # Video processing and OCR
    ffmpeg \
    tesseract-ocr \
    # Playwright browser dependencies for Chromium
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libatspi2.0-0 \
    # Cleanup apt cache to reduce image size
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Install Playwright and Chromium browser
# This is needed for dynamic content fetching from JavaScript-heavy sites
RUN playwright install chromium && \
    playwright install-deps chromium

# Copy application code
COPY . .

# Make startup script executable
RUN chmod +x start.sh

# Expose port (Render default)
EXPOSE 10000

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:10000/health')"

# Run the startup script
# This handles database setup, migrations, and server startup
CMD ["bash", "start.sh"]

