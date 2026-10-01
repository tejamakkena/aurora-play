import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()


class Config:
    SECRET_KEY = os.environ.get(
        'SECRET_KEY') or 'dev-secret-key-change-in-production-12345'

    # Google OAuth Configuration
    GOOGLE_CLIENT_ID = os.environ.get('GOOGLE_CLIENT_ID')
    GOOGLE_CLIENT_SECRET = os.environ.get('GOOGLE_CLIENT_SECRET')
    GOOGLE_DISCOVERY_URL = "https://accounts.google.com/.well-known/openid-configuration"
    
    # Rate Limiting Configuration
    RATELIMIT_DEFAULT = os.environ.get('RATE_LIMIT', '100 per hour')
    RATELIMIT_STORAGE_URL = os.environ.get('RATELIMIT_STORAGE_URL', 'memory://')
    RATELIMIT_HEADERS_ENABLED = True

    # Socket.IO CORS origins: comma-separated list, or "*" to allow all.
    # Default is same-origin only. The web UI is served by this app (same
    # origin needs no CORS entry) and the native iOS/tvOS apps do not send
    # an Origin header, so they are unaffected. Set SOCKETIO_CORS_ORIGINS
    # explicitly if a third-party web client needs cross-origin access.
    SOCKETIO_CORS_ORIGINS = os.environ.get('SOCKETIO_CORS_ORIGINS', '')


class DevelopmentConfig(Config):
    DEBUG = True


class ProductionConfig(Config):
    DEBUG = False


config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'default': DevelopmentConfig
}
