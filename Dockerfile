
FROM python:3.10-slim-bookworm

# Set working directory
WORKDIR /app

# Install system dependencies. build-essential is the only one anything in
# requirements.txt could conceivably need (a transitive dependency compiling
# from source); curl, software-properties-common and git were never actually
# used anywhere in this app, so they're dropped -- smaller image, less apt
# surface to fail on. --no-install-recommends keeps the ripple-effect
# packages down too.
RUN apt-get update && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy project files
COPY . /app

# Install Python dependencies. Only the runtime ones -- pylint/pytest/bandit
# etc. (dev-requirements.txt) are for local development, not for running
# the server, so they don't belong in a deploy image.
RUN pip install --no-cache-dir -r requirements.txt

# Set environment variables
ENV FLASK_APP=app.py
# Production mode unless FLASK_DEBUG=1 (see app.py's __main__).
ENV FLASK_DEBUG=0

# Expose application port
EXPOSE 5000

# Run the application
# "flask run" serves the WSGI app only and never calls socketio.run(), so
# Socket.IO would not be served at all -- every realtime game would break.
CMD ["python", "app.py"]
