import os
import secrets

from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()


_DEV_SECRET = 'dev-secret-key-change-in-production-12345'


class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or _DEV_SECRET

    # Google OAuth Configuration
    GOOGLE_CLIENT_ID = os.environ.get('GOOGLE_CLIENT_ID')
    GOOGLE_CLIENT_SECRET = os.environ.get('GOOGLE_CLIENT_SECRET')
    GOOGLE_DISCOVERY_URL = "https://accounts.google.com/.well-known/openid-configuration"
    
    # Rate Limiting Configuration
    RATELIMIT_DEFAULT = os.environ.get('RATE_LIMIT', '100 per hour')
    RATELIMIT_STORAGE_URL = os.environ.get('RATELIMIT_STORAGE_URL', 'memory://')
    RATELIMIT_HEADERS_ENABLED = True

    # Voice quizmaster (cloud TTS + answer grading). The OpenAI key funds
    # the TTS proxy at /api/voice/tts; grading reuses GEMINI_API_KEY via
    # games.topic_gen. See games/voice.py for the cost math (~$0.07/game).
    OPENAI_API_KEY = os.environ.get('OPENAI_API_KEY')
    TTS_MODEL = os.environ.get('TTS_MODEL', 'gpt-4o-mini-tts')
    TTS_VOICE = os.environ.get('TTS_VOICE', 'marin')
    try:
        TTS_DAILY_CHAR_CAP = max(0, int(os.environ.get('TTS_DAILY_CHAR_CAP',
                                                       '500000')))
    except ValueError:
        TTS_DAILY_CHAR_CAP = 500000

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
    # A known constant must never sign sessions in production: anyone who has
    # read this file could forge one. Without SECRET_KEY the server mints a
    # random key per process instead (web sessions end on a restart, which is
    # harmless: the apps do not use them). Set SECRET_KEY to keep them.
    if not os.environ.get('SECRET_KEY'):
        SECRET_KEY = secrets.token_hex(32)


config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'default': DevelopmentConfig
}
