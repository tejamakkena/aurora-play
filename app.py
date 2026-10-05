from flask import Flask, render_template, redirect, url_for, session, request, jsonify
from flask_socketio import SocketIO
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from config import config
from functools import wraps
from google.oauth2 import id_token
from google.auth.transport import requests



def make_origin_checker(raw_origins):
    """Build engine.io's origin check: same host as the request, or allowlisted.

    An empty list must never reach engine.io: it treats ``[]`` as "allow no
    origin at all" and rejects every request carrying an Origin header --
    the browser games' WebSocket upgrades and POSTs, and the iOS socket
    library's WebSocket upgrade. Same-host is compared on hostname only, so
    a proxy that rewrites the scheme (Render terminates TLS) or a client
    that spells out the default port still matches.
    """
    from urllib.parse import urlsplit

    allowlist = {o.strip().rstrip("/") for o in raw_origins.split(",") if o.strip()}

    def _host(value):
        value = (value or "").split(",")[0].strip()
        if "//" not in value:
            value = "//" + value
        return (urlsplit(value).hostname or "").lower()

    def check(origin, environ=None):
        if not origin:
            return True
        if origin.rstrip("/") in allowlist:
            return True
        environ = environ or {}
        origin_host = _host(origin)
        request_hosts = {_host(environ.get("HTTP_HOST")),
                         _host(environ.get("HTTP_X_FORWARDED_HOST"))}
        return bool(origin_host) and origin_host in request_hosts

    return check


def create_app(config_name='default'):
    app = Flask(__name__)
    app.config.from_object(config[config_name])

    # Initialize Socket.IO. Same-host origins are always accepted; extra
    # origins come from SOCKETIO_CORS_ORIGINS (comma-separated). "*" restores
    # the previous wide-open behavior.
    raw_origins = app.config.get("SOCKETIO_CORS_ORIGINS", "")
    if raw_origins == "*":
        app.logger.warning(
            "Socket.IO CORS is wide open (*); set SOCKETIO_CORS_ORIGINS "
            "to a comma-separated allowlist to restrict browser origins.")
        cors_origins = "*"
    else:
        cors_origins = make_origin_checker(raw_origins)
    socketio = SocketIO(app, cors_allowed_origins=cors_origins,
                        async_mode='threading')

    # Initialize Rate Limiter
    # Default limits: 200 requests/day, 50 requests/hour per IP
    # Critical endpoints (login) have stricter limits (5/minute)
    # Game endpoints limited to 100 requests/hour to prevent abuse
    # Configurable via RATE_LIMIT environment variable
    limiter = Limiter(
        app=app,
        key_func=get_remote_address,
        default_limits=["200 per day", "50 per hour"],
        storage_uri=app.config.get('RATELIMIT_STORAGE_URL', 'memory://'),
        headers_enabled=app.config.get('RATELIMIT_HEADERS_ENABLED', True)
    )

    # Debug: Print Google Client ID (first 20 chars only for security)
    # client_id = app.config.get('GOOGLE_CLIENT_ID', 'NOT SET')
    # print(f"Google Client ID configured: {client_id[:20] if client_id else 'NOT SET'}...")

    # Register blueprints
    from games.tictactoe.routes import tictactoe_bp
    from games.trivia.routes import trivia_bp
    from games.snake_ladder.routes import snake_ladder_bp
    from games.roulette.routes import roulette_bp
    from games.poker.routes import poker_bp
    from games.canvas_battle.routes import canvas_battle_bp
    from games.connect4.routes import connect4_bp
    from games.digit_guess.routes import digit_guess_bp
    from games.raja_mantri.routes import raja_mantri_bp
    from games.memory.routes import memory_bp
    from games.pictionary.routes import pictionary_bp
    from games.mafia.routes import mafia_bp
    from games.tambola.routes import tambola_bp
    from games.hangman.routes import hangman_bp
    from games.pong.routes import pong_bp
    from games.stickfight.routes import stickfight_bp
    from games.roadfighter.routes import roadfighter_bp

    app.register_blueprint(tictactoe_bp, url_prefix='/tictactoe')
    app.register_blueprint(trivia_bp, url_prefix='/trivia')
    app.register_blueprint(snake_ladder_bp, url_prefix='/snake')
    app.register_blueprint(roulette_bp, url_prefix='/roulette')
    app.register_blueprint(poker_bp, url_prefix='/poker')
    app.register_blueprint(canvas_battle_bp, url_prefix='/canvas-battle')
    app.register_blueprint(connect4_bp, url_prefix='/connect4')
    app.register_blueprint(digit_guess_bp, url_prefix='/digit-guess')
    app.register_blueprint(raja_mantri_bp, url_prefix='/raja-mantri')
    app.register_blueprint(memory_bp, url_prefix='/memory')
    app.register_blueprint(pictionary_bp, url_prefix='/pictionary')
    app.register_blueprint(mafia_bp, url_prefix='/mafia')
    app.register_blueprint(tambola_bp, url_prefix='/tambola')
    app.register_blueprint(hangman_bp, url_prefix='/hangman')
    app.register_blueprint(pong_bp, url_prefix='/pong')
    app.register_blueprint(stickfight_bp, url_prefix='/stickfight')
    app.register_blueprint(roadfighter_bp, url_prefix='/roadfighter')

    # Travel Mode: live topic-based question generation for the iOS client.
    from games.topic_gen import topic_bp
    app.register_blueprint(topic_bp, url_prefix='/api/travel')

    # Voice quizmaster: cloud TTS proxy + answer grading. API keys stay
    # server-side; the apps never see them. See games/voice.py and the
    # PR description for the OPENAI_API_KEY setup.
    from games.voice import voice_bp
    app.register_blueprint(voice_bp, url_prefix='/api/voice')

    # Apply rate limiting to all game blueprints (configurable via RATE_LIMIT env var, default: 100/hour)
    game_rate_limit = app.config.get('RATELIMIT_DEFAULT', '100 per hour')
    limiter.limit(game_rate_limit)(tictactoe_bp)
    limiter.limit(game_rate_limit)(trivia_bp)
    limiter.limit(game_rate_limit)(snake_ladder_bp)
    limiter.limit(game_rate_limit)(roulette_bp)
    limiter.limit(game_rate_limit)(poker_bp)
    limiter.limit(game_rate_limit)(canvas_battle_bp)
    limiter.limit(game_rate_limit)(connect4_bp)
    limiter.limit(game_rate_limit)(digit_guess_bp)
    limiter.limit(game_rate_limit)(raja_mantri_bp)
    limiter.limit(game_rate_limit)(memory_bp)
    limiter.limit(game_rate_limit)(pictionary_bp)
    limiter.limit(game_rate_limit)(mafia_bp)
    limiter.limit(game_rate_limit)(tambola_bp)
    limiter.limit(game_rate_limit)(hangman_bp)
    limiter.limit(game_rate_limit)(pong_bp)
    limiter.limit(game_rate_limit)(stickfight_bp)
    limiter.limit(game_rate_limit)(roadfighter_bp)

    # Import Socket.IO event handlers
    from games.trivia.socket_events import register_trivia_events
    from games.snake_ladder.socket_events import register_snake_events
    from games.roulette.socket_events import register_roulette_events
    from games.poker.socket_events import register_poker_events
    from games.canvas_battle.socket_events import register_canvas_battle_events
    from games.connect4.socket_events import register_connect4_events
    from games.digit_guess.socket_events import register_digit_guess_events
    from games.pictionary.socket_events import register_pictionary_events
    from games.mafia.routes import register_mafia_handlers
    from games.tambola.socket_events import register_tambola_events
    from games.raja_mantri.socket_events import register_raja_mantri_events
    from games.hangman.socket_events import register_hangman_events
    from games.pong.socket_events import register_pong_events
    from games.stickfight.socket_events import register_stickfight_events
    from games.roadfighter.socket_events import register_roadfighter_events

    # Native iOS/tvOS hub -- isolated on the '/native' namespace so it cannot
    # collide with the browser games' default-namespace room events.
    from games.native_hub.socket_events import register_native_events
    from games.native_hub.qr import qr_bp

    # After creating socketio
    register_poker_events(socketio)
    register_trivia_events(socketio)
    register_snake_events(socketio)
    register_roulette_events(socketio)
    register_canvas_battle_events(socketio)
    register_connect4_events(socketio)
    register_digit_guess_events(socketio)
    register_pictionary_events(socketio)
    register_mafia_handlers(socketio)
    register_tambola_events(socketio)
    register_raja_mantri_events(socketio)
    register_hangman_events(socketio)
    register_pong_events(socketio)
    register_stickfight_events(socketio)
    register_roadfighter_events(socketio)
    register_native_events(socketio)
    app.register_blueprint(qr_bp)


    # Login required decorator
    def login_required(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if 'user' not in session:
                return redirect(url_for('login'))
            return f(*args, **kwargs)
        return decorated_function

    # Main routes
    @app.route("/")
    @limiter.limit(lambda: app.config.get('RATELIMIT_DEFAULT', '100 per hour'))
    def home():
        games_list = [
            # ── ACTION ──────────────────────────────────────────
            {
                'name': 'Pong',
                'url': '/pong',
                'icon': '🏓',
                'players': '2',
                'description': 'Classic paddle battle! First to 7 points wins!',
                'category': 'action',
                'category_label': '⚔️ Action',
                'preview': 'pong'
            },
            {
                'name': 'Stick Fight',
                'url': '/stickfight',
                'icon': '🥊',
                'players': '2-4',
                'description': 'Arena brawler! Punch and kick your way to victory!',
                'category': 'action',
                'category_label': '⚔️ Action',
                'preview': 'stickfight'
            },
            {
                'name': 'Road Fighter',
                'url': '/roadfighter',
                'icon': '🚗',
                'players': '1-4',
                'description': 'Race through traffic! Dodge cars and survive the longest!',
                'category': 'action',
                'category_label': '⚔️ Action',
                'preview': 'roadfighter'
            },
            {
                'name': 'Canvas Battle',
                'url': '/canvas-battle',
                'icon': '🎨🖼️',
                'players': '2-6',
                'description': 'Draw on a theme and vote for the best art!',
                'category': 'action',
                'category_label': '⚔️ Action',
                'preview': 'canvas_battle'
            },
            {
                'name': 'Snake & Ladder',
                'url': '/snake',
                'icon': '🐍🪜',
                'players': '2-4',
                'description': 'Roll the dice and climb to victory!',
                'category': 'action',
                'category_label': '⚔️ Action',
                'preview': 'snake'
            },
            # ── STRATEGY ────────────────────────────────────────
            {
                'name': 'Tic Tac Toe',
                'url': '/tictactoe',
                'icon': '❌⭕',
                'players': '2',
                'description': 'Classic 2-player strategy game. Test your tactical skills!',
                'category': 'strategy',
                'category_label': '🧠 Strategy',
                'preview': 'tictactoe'
            },
            {
                'name': 'Connect 4',
                'url': '/connect4',
                'icon': '🔴🟡',
                'players': '2',
                'description': 'Strategic dropping game. Connect four to win!',
                'category': 'strategy',
                'category_label': '🧠 Strategy',
                'preview': 'connect4'
            },
            {
                'name': 'Digit Guess',
                'url': '/digit-guess',
                'icon': '🔢🎯',
                'players': '2',
                'description': 'Crack your opponent\'s 4-digit code! Like Mastermind!',
                'category': 'strategy',
                'category_label': '🧠 Strategy',
                'preview': 'digit_guess'
            },
            {
                'name': 'Memory Game',
                'url': '/memory',
                'icon': '🧠💭',
                'players': '1-4',
                'description': 'Test your memory with matching cards!',
                'category': 'strategy',
                'category_label': '🧠 Strategy',
                'preview': 'memory'
            },
            {
                'name': 'Hangman',
                'url': '/hangman',
                'icon': '🪢🔤',
                'players': '2+',
                'description': 'Host sets a secret word — guessers reveal it letter by letter!',
                'category': 'strategy',
                'category_label': '🧠 Strategy',
                'preview': 'hangman'
            },
            # ── CASINO ──────────────────────────────────────────
            {
                'name': 'Roulette Casino',
                'url': '/roulette',
                'icon': '🎰',
                'players': '1+',
                'description': 'Place your bets and spin the wheel!',
                'category': 'casino',
                'category_label': '🎰 Casino',
                'preview': 'roulette'
            },
            {
                'name': 'Texas Hold\'em Poker',
                'url': '/poker',
                'icon': '🃏♠️',
                'players': '2-6',
                'description': 'High stakes poker showdown!',
                'category': 'casino',
                'category_label': '🎰 Casino',
                'preview': 'poker'
            },
            # ── PARTY ───────────────────────────────────────────
            {
                'name': 'Pictionary',
                'url': '/pictionary',
                'icon': '🎨✏️',
                'players': '2+',
                'description': 'Draw and guess! Creative multiplayer fun!',
                'category': 'party',
                'category_label': '🎉 Party',
                'preview': 'pictionary'
            },
            {
                'name': 'Trivia',
                'url': '/trivia',
                'icon': '❓🏆',
                'players': '1+',
                'description': 'Challenge your knowledge across categories!',
                'category': 'party',
                'category_label': '🎉 Party',
                'preview': 'trivia'
            },
            {
                'name': 'Mafia',
                'url': '/mafia',
                'icon': '🕵️🔪',
                'players': '4+',
                'description': 'Social deduction game. Find the mafia members!',
                'category': 'party',
                'category_label': '🎉 Party',
                'preview': 'mafia'
            },
            {
                'name': 'Tambola',
                'url': '/tambola',
                'icon': '🎲🎟️',
                'players': '2+',
                'description': 'Indian bingo game. Mark your numbers and win!',
                'category': 'party',
                'category_label': '🎉 Party',
                'preview': 'tambola'
            },
            {
                'name': 'Raja Mantri',
                'url': '/raja-mantri',
                'icon': '👑🗡️',
                'players': '4',
                'description': 'Classic 4-player guessing game!',
                'category': 'party',
                'category_label': '🎉 Party',
                'preview': 'raja_mantri'
            },
            {
                'name': 'Hangman',
                'url': '/hangman',
                'icon': '🪢🔤',
                'players': '2+',
                'description': 'Host sets a secret word — guessers reveal it letter by letter!'
            },
            {
                'name': 'Pong',
                'url': '/pong',
                'icon': '🏓',
                'players': '2',
                'description': 'Classic paddle battle! First to 7 points wins!'
            },
            {
                'name': 'Stick Fight',
                'url': '/stickfight',
                'icon': '🥊',
                'players': '2-4',
                'description': 'Arena brawler! Punch and kick your way to victory!'
            },
            {
                'name': 'Road Fighter',
                'url': '/roadfighter',
                'icon': '🚗',
                'players': '1-4',
                'description': 'Race through traffic! Dodge cars and survive the longest!'
            }
        ]

        user = session.get('user')
        return render_template(
            "home.html",
            games=games_list,
            user=user,
            google_client_id=app.config.get('GOOGLE_CLIENT_ID'))

    @app.route("/login", methods=['POST'])
    @limiter.limit("5 per minute")
    def login():
        """Google OAuth login"""
        token = request.json.get('credential')

        try:
            idinfo = id_token.verify_oauth2_token(
                token,
                requests.Request(),
                app.config['GOOGLE_CLIENT_ID']
            )

            session['user'] = {
                'email': idinfo['email'],
                'first_name': idinfo.get('given_name', ''),
                'last_name': idinfo.get('family_name', ''),
                'picture': idinfo.get('picture', ''),
                'name': idinfo.get('name', ''),
                'login_type': 'google'
            }

            print(f"✅ Google login successful: {session['user']['email']}")
            return jsonify({'success': True, 'user': session['user']})
        except ValueError as e:
            print(f"❌ Google login error: {e}")
            return jsonify({'success': False, 'error': 'Invalid login credentials'}), 400

    @app.route("/login/manual", methods=['POST'])
    @limiter.limit("5 per minute")
    def manual_login():
        """Manual name-based login"""
        data = request.json
        player_name = data.get('player_name', '').strip()

        if not player_name or len(player_name) < 2:
            return jsonify(
                {'success': False, 'error': 'Name must be at least 2 characters'}), 400

        session['user'] = {
            'name': player_name,
            'first_name': player_name.split()[0] if ' ' in player_name else player_name,
            'last_name': player_name.split()[-1] if ' ' in player_name else '',
            'email': None,
            'picture': None,
            'login_type': 'manual'
        }

        return jsonify({'success': True, 'user': session['user']})

    @app.route("/logout")
    def logout():
        user = session.get('user', {})
        print(f"👋 Logout: {user.get('name', 'Unknown user')}")
        session.pop('user', None)
        return redirect(url_for('home'))

    @app.route("/about")
    def about():
        return render_template("about.html")

    # Error handlers
    @app.errorhandler(404)
    def not_found(error):
        try:
            return render_template('404.html'), 404
        except Exception:
            return '<h1>404 - Page Not Found</h1><a href="/">Go Home</a>', 404

    @app.errorhandler(500)
    def internal_error(error):
        try:
            return render_template('500.html'), 500
        except Exception as e:
            print(f"500 error handler exception: {e}")
            return '<h1>500 - Internal Server Error</h1><p>An unexpected error occurred.</p><a href="/">Go Home</a>', 500

    return app, socketio


if __name__ == "__main__":
    app, socketio = create_app('development')
    print("\n🚀 Starting Futuristic Games Hub...")
    print("📍 Server running at: http://localhost:5000")
    print("🎮 Games loaded:")
    print("   ✅ Tic-Tac-Toe")
    print("   ✅ Snake & Ladder")
    print("   ✅ Roulette Casino")
    print("   ✅ Texas Hold'em Poker")
    print("   ✅ Trivia")
    print("   ✅ Canvas Battle")
    print("   ✅ Connect 4")
    print()
    socketio.run(app, debug=True, host='0.0.0.0', port=5000, allow_unsafe_werkzeug=True)
