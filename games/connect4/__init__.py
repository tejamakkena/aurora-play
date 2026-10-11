"""Four in a Row game module"""
from .routes import connect4_bp
from .socket_events import register_connect4_events

__all__ = ['connect4_bp', 'register_connect4_events']
