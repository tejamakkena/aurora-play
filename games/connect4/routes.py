from flask import Blueprint, render_template, session, redirect, url_for
from functools import wraps

connect4_bp = Blueprint(
    'connect4',
    __name__,
    template_folder='../../templates')


def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user' not in session:
            return redirect(url_for('home'))
        return f(*args, **kwargs)
    return decorated_function


@connect4_bp.route('/')
@login_required
def index():
    """Four in a Row game page"""
    return render_template('games/connect4.html', user=session.get('user'))
