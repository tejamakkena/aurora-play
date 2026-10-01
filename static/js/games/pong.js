// ============================================================
//  PONG — Multiplayer
//  Host runs physics + sends ball state; both relay paddle pos
// ============================================================

const socket = io('/pong');
const cleanup = new CleanupManager();

// ── Constants ─────────────────────────────────────────────────
const W = 800, H = 500;
const PADDLE_W = 14, PADDLE_H = 110;
const BALL_R = 10;
const PADDLE_MARGIN = 30;
const WIN_SCORE = 7;
const BASE_SPEED = 5;
const MAX_SPEED = 14;
const PADDLE_SPEED = 7;

// ── Game state ────────────────────────────────────────────────
let gs = {
    roomCode: null, isHost: false, mySide: null,
    players: [], gameStarted: false, gameOver: false,
    score: { left: 0, right: 0 },
    ball: { x: W / 2, y: H / 2, vx: BASE_SPEED, vy: 2 },
    paddles: { left: { y: H / 2 - PADDLE_H / 2 }, right: { y: H / 2 - PADDLE_H / 2 } },
    keys: {},
    lastBallSend: 0
};

// ── DOM ────────────────────────────────────────────────────────
const $ = id => document.getElementById(id);
const sections = {
    mode: $('mode-section'),
    join: $('join-section'),
    waiting: $('waiting-section'),
    game: $('game-section'),
    over: $('gameover-section')
};

const canvas = $('pong-canvas');
const ctx = canvas.getContext('2d');
canvas.width = W; canvas.height = H;

// ── Section helpers ────────────────────────────────────────────
function showSection(name) {
    Object.entries(sections).forEach(([k, el]) => {
        if (el) el.classList.toggle('hidden', k !== name);
    });
}

// ── Socket setup ──────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    bindUI();
    setupSocket();
    showSection('mode');
});

function bindUI() {
    cleanup.addEventListener($('create-btn'), 'click', createRoom);
    cleanup.addEventListener($('join-btn-show'), 'click', () => showSection('join'));
    cleanup.addEventListener($('back-to-mode'), 'click', () => showSection('mode'));
    cleanup.addEventListener($('join-submit'), 'click', joinRoom);
    cleanup.addEventListener($('room-code-input'), 'keypress', e => { if (e.key === 'Enter') joinRoom(); });
    cleanup.addEventListener($('copy-code-btn'), 'click', copyCode);
    cleanup.addEventListener($('start-btn'), 'click', startGame);
    cleanup.addEventListener($('leave-waiting-btn'), 'click', leaveRoom);
    cleanup.addEventListener($('play-again-btn'), 'click', resetAndReturn);
    cleanup.addEventListener($('exit-btn'), 'click', () => window.location.href = '/');
}

function setupSocket() {
    cleanup.addSocketListener(socket, 'room_created', data => {
        gs.roomCode = data.room_code;
        gs.isHost = true;
        gs.mySide = data.your_side || 'left';
        gs.players = data.players;
        updateWaitingRoom();
        showSection('waiting');
    });

    cleanup.addSocketListener(socket, 'room_joined', data => {
        gs.roomCode = data.room_code;
        gs.isHost = false;
        gs.mySide = data.your_side || 'right';
        gs.players = data.players;
        updateWaitingRoom();
        showSection('waiting');
    });

    cleanup.addSocketListener(socket, 'player_joined', data => {
        gs.players = data.players;
        updateWaitingRoom();
    });

    cleanup.addSocketListener(socket, 'player_left', data => {
        gs.players = data.players;
        updateWaitingRoom();
        if (gs.gameStarted && !gs.gameOver) {
            showMessage('Opponent disconnected!', 'warning');
            cleanup.addTimeout(setTimeout(resetAndReturn, 2000));
        }
    });

    cleanup.addSocketListener(socket, 'game_started', () => {
        gs.gameStarted = true;
        gs.gameOver = false;
        resetBall();
        showSection('game');
        if (gs.isHost) startHostLoop();
        else startGuestLoop();
    });

    // Guest receives authoritative ball+score from host
    cleanup.addSocketListener(socket, 'pong_ball_update', data => {
        if (gs.isHost) return;
        gs.ball = data.ball;
        gs.score = data.score;
        // Update opponent paddle (left paddle for guest = opponent)
        if (data.paddles) gs.paddles.left = data.paddles.left;
    });

    // Receive opponent paddle position
    cleanup.addSocketListener(socket, 'pong_paddle_update', data => {
        if (data.side && gs.paddles[data.side]) {
            gs.paddles[data.side].y = data.y;
        }
    });

    cleanup.addSocketListener(socket, 'pong_game_over', data => {
        gs.gameOver = true;
        cancelAnimationFrame(gs.rafId);
        const w = data.winner === gs.mySide ? 'You Win!' : 'You Lose';
        $('result-text').textContent = w;
        $('final-score').textContent = `${data.score.left} – ${data.score.right}`;
        showSection('over');
    });

    cleanup.addSocketListener(socket, 'error', data => {
        showMessage(data.message || 'Error', 'error');
    });
}

// ── Room actions ───────────────────────────────────────────────
function createRoom() {
    const name = getUserName();
    socket.emit('create_room', { game_type: 'pong', player_name: name });
}

function joinRoom() {
    const code = $('room-code-input').value.trim().toUpperCase();
    if (!code) { showMessage('Enter a room code', 'error'); return; }
    socket.emit('join_room', { game_type: 'pong', room_code: code, player_name: getUserName() });
}

function startGame() {
    socket.emit('start_game', { game_type: 'pong', room_code: gs.roomCode });
}

function leaveRoom() {
    socket.emit('leave_room', { game_type: 'pong', room_code: gs.roomCode });
    gs.roomCode = null;
    showSection('mode');
}

function resetAndReturn() {
    gs.gameStarted = false; gs.gameOver = false;
    cancelAnimationFrame(gs.rafId);
    gs.score = { left: 0, right: 0 };
    resetBall();
    showSection('mode');
}

function copyCode() {
    copyToClipboard(gs.roomCode, () => showMessage('Copied!', 'success'));
}

function updateWaitingRoom() {
    $('display-room-code').textContent = gs.roomCode;
    $('waiting-players').innerHTML = gs.players.map(p =>
        `<div class="player-item${p.is_host ? ' host' : ''}">
          <div class="player-number" style="background:${p.side === 'left' ? '#00f5ff' : '#bf5fff'}">${p.side === 'left' ? 'L' : 'R'}</div>
          <span>${p.name}</span>${p.is_host ? '<span class="host-badge">HOST</span>' : ''}
         </div>`
    ).join('');
    const startBtn = $('start-btn');
    if (startBtn) startBtn.classList.toggle('hidden', !gs.isHost || gs.players.length < 2);
}

// ── Physics (host) ─────────────────────────────────────────────
function resetBall(dir = null) {
    const d = dir ?? (Math.random() > 0.5 ? 1 : -1);
    gs.ball = {
        x: W / 2, y: H / 2,
        vx: BASE_SPEED * d,
        vy: (Math.random() - 0.5) * 6
    };
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

function updatePhysics() {
    const { ball, paddles, score } = gs;

    // Move my paddle
    const myPaddle = paddles[gs.mySide];
    if (gs.keys['ArrowUp'] || gs.keys['w'] || gs.keys['W']) myPaddle.y -= PADDLE_SPEED;
    if (gs.keys['ArrowDown'] || gs.keys['s'] || gs.keys['S']) myPaddle.y += PADDLE_SPEED;
    myPaddle.y = clamp(myPaddle.y, 0, H - PADDLE_H);

    // Ball movement
    ball.x += ball.vx;
    ball.y += ball.vy;

    // Top/bottom bounce
    if (ball.y - BALL_R <= 0) { ball.y = BALL_R; ball.vy = Math.abs(ball.vy); }
    if (ball.y + BALL_R >= H) { ball.y = H - BALL_R; ball.vy = -Math.abs(ball.vy); }

    // Left paddle collision
    const lp = paddles.left;
    if (ball.x - BALL_R <= PADDLE_MARGIN + PADDLE_W &&
        ball.y >= lp.y - BALL_R && ball.y <= lp.y + PADDLE_H + BALL_R &&
        ball.vx < 0) {
        ball.vx = Math.abs(ball.vx) * 1.05;
        const rel = (ball.y - (lp.y + PADDLE_H / 2)) / (PADDLE_H / 2);
        ball.vy = rel * 7;
        ball.x = PADDLE_MARGIN + PADDLE_W + BALL_R;
    }

    // Right paddle collision
    const rp = paddles.right;
    if (ball.x + BALL_R >= W - PADDLE_MARGIN - PADDLE_W &&
        ball.y >= rp.y - BALL_R && ball.y <= rp.y + PADDLE_H + BALL_R &&
        ball.vx > 0) {
        ball.vx = -Math.abs(ball.vx) * 1.05;
        const rel = (ball.y - (rp.y + PADDLE_H / 2)) / (PADDLE_H / 2);
        ball.vy = rel * 7;
        ball.x = W - PADDLE_MARGIN - PADDLE_W - BALL_R;
    }

    // Speed cap
    const spd = Math.sqrt(ball.vx ** 2 + ball.vy ** 2);
    if (spd > MAX_SPEED) { ball.vx = ball.vx / spd * MAX_SPEED; ball.vy = ball.vy / spd * MAX_SPEED; }

    // Scoring
    if (ball.x - BALL_R <= 0) {
        score.right++;
        if (score.right >= WIN_SCORE) { endGame(); return; }
        setTimeout(() => resetBall(1), 800);
        ball.x = W / 2; ball.y = H / 2; ball.vx = 0; ball.vy = 0;
    } else if (ball.x + BALL_R >= W) {
        score.left++;
        if (score.left >= WIN_SCORE) { endGame(); return; }
        setTimeout(() => resetBall(-1), 800);
        ball.x = W / 2; ball.y = H / 2; ball.vx = 0; ball.vy = 0;
    }
}

function endGame() {
    const winner = gs.score.left >= WIN_SCORE ? 'left' : 'right';
    socket.emit('pong_game_over', { room_code: gs.roomCode, winner, score: gs.score });
    gs.gameOver = true;
    cancelAnimationFrame(gs.rafId);
    $('result-text').textContent = winner === gs.mySide ? 'You Win!' : 'You Lose';
    $('final-score').textContent = `${gs.score.left} – ${gs.score.right}`;
    showSection('over');
}

// ── Game loop (host) ────────────────────────────────────────────
function startHostLoop() {
    bindKeys();
    function loop() {
        if (gs.gameOver) return;
        updatePhysics();

        // Send paddle to opponent every frame
        socket.emit('pong_paddle_update', {
            room_code: gs.roomCode,
            side: gs.mySide,
            y: gs.paddles[gs.mySide].y
        });

        // Send authoritative ball state ~30fps
        const now = performance.now();
        if (now - gs.lastBallSend > 33) {
            socket.emit('pong_ball_update', {
                room_code: gs.roomCode,
                ball: gs.ball,
                score: gs.score,
                paddles: gs.paddles
            });
            gs.lastBallSend = now;
        }

        render();
        gs.rafId = requestAnimationFrame(loop);
    }
    gs.rafId = requestAnimationFrame(loop);
}

// ── Game loop (guest) ───────────────────────────────────────────
function startGuestLoop() {
    bindKeys();
    function loop() {
        if (gs.gameOver) return;

        // Guest only controls their own paddle
        const myPaddle = gs.paddles[gs.mySide];
        if (gs.keys['ArrowUp'] || gs.keys['w'] || gs.keys['W']) myPaddle.y -= PADDLE_SPEED;
        if (gs.keys['ArrowDown'] || gs.keys['s'] || gs.keys['S']) myPaddle.y += PADDLE_SPEED;
        myPaddle.y = clamp(myPaddle.y, 0, H - PADDLE_H);

        // Send paddle to host/room
        socket.emit('pong_paddle_update', {
            room_code: gs.roomCode,
            side: gs.mySide,
            y: myPaddle.y
        });

        render();
        gs.rafId = requestAnimationFrame(loop);
    }
    gs.rafId = requestAnimationFrame(loop);
}

function bindKeys() {
    cleanup.addEventListener(window, 'keydown', e => { gs.keys[e.key] = true; });
    cleanup.addEventListener(window, 'keyup', e => { gs.keys[e.key] = false; });
}

// ── Rendering ──────────────────────────────────────────────────
function render() {
    const { ball, paddles, score } = gs;

    // Background
    ctx.fillStyle = '#04000f';
    ctx.fillRect(0, 0, W, H);

    // Center line
    ctx.setLineDash([12, 8]);
    ctx.strokeStyle = 'rgba(255,255,255,0.12)';
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(W / 2, 0); ctx.lineTo(W / 2, H); ctx.stroke();
    ctx.setLineDash([]);

    // Scores
    ctx.fillStyle = 'rgba(255,255,255,0.4)';
    ctx.font = 'bold 64px Orbitron, monospace';
    ctx.textAlign = 'center';
    ctx.fillText(score.left, W / 4, 80);
    ctx.fillText(score.right, W * 3 / 4, 80);

    // Player labels
    ctx.font = '13px Space Grotesk, sans-serif';
    ctx.fillStyle = 'rgba(255,255,255,0.3)';
    const lName = gs.players.find(p => p.side === 'left')?.name || 'LEFT';
    const rName = gs.players.find(p => p.side === 'right')?.name || 'RIGHT';
    ctx.fillText(lName, W / 4, 105);
    ctx.fillText(rName, W * 3 / 4, 105);

    // Left paddle
    drawPaddle(PADDLE_MARGIN, paddles.left.y, '#00f5ff');

    // Right paddle
    drawPaddle(W - PADDLE_MARGIN - PADDLE_W, paddles.right.y, '#bf5fff');

    // Ball
    drawBall(ball.x, ball.y);

    // "My side" indicator
    if (!gs.gameOver) {
        ctx.font = '11px Space Grotesk, sans-serif';
        ctx.fillStyle = 'rgba(255,255,255,0.4)';
        ctx.textAlign = gs.mySide === 'left' ? 'left' : 'right';
        const tx = gs.mySide === 'left' ? PADDLE_MARGIN : W - PADDLE_MARGIN;
        ctx.fillText('YOU', tx, H - 12);
    }
}

function drawPaddle(x, y, color) {
    const grd = ctx.createLinearGradient(x, y, x + PADDLE_W, y + PADDLE_H);
    grd.addColorStop(0, color);
    grd.addColorStop(1, color + '88');
    ctx.shadowColor = color;
    ctx.shadowBlur = 18;
    ctx.fillStyle = grd;
    ctx.beginPath();
    ctx.roundRect(x, y, PADDLE_W, PADDLE_H, 6);
    ctx.fill();
    ctx.shadowBlur = 0;
}

function drawBall(x, y) {
    ctx.shadowColor = '#ffffff';
    ctx.shadowBlur = 20;
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.arc(x, y, BALL_R, 0, Math.PI * 2);
    ctx.fill();
    // inner glow
    const grd = ctx.createRadialGradient(x - 3, y - 3, 1, x, y, BALL_R);
    grd.addColorStop(0, 'rgba(200,240,255,0.8)');
    grd.addColorStop(1, 'rgba(100,180,255,0.2)');
    ctx.fillStyle = grd;
    ctx.beginPath();
    ctx.arc(x, y, BALL_R, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 0;
}
