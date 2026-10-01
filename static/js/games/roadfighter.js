// ============================================================
//  ROAD FIGHTER — Multiplayer Survival Racing
//  Host generates obstacles; all players dodge in their lane
// ============================================================

const socket = io('/roadfighter');
const cleanup = new CleanupManager();

const canvas = document.getElementById('rf-canvas');
const ctx = canvas.getContext('2d');
const W = 480, H = 640;
canvas.width = W; canvas.height = H;

// ── Road constants ─────────────────────────────────────────────
const ROAD_LEFT = 60, ROAD_RIGHT = W - 60, ROAD_W = ROAD_RIGHT - ROAD_LEFT;
const LANE_COUNT = 3;
const LANE_W = ROAD_W / LANE_COUNT;
const CAR_W = 46, CAR_H = 80;
const OBS_W = 46, OBS_H = 78;
const SCROLL_BASE = 4;
const SPAWN_INTERVAL = 1400; // ms between obstacle spawns
const MAX_HEALTH = 3;

// Obstacle car templates
const OBS_COLORS = ['#ff4444', '#ff8844', '#ff44aa', '#888888', '#cc4444'];

// ── Game state ─────────────────────────────────────────────────
let gs = {
    roomCode: null, isHost: false, myIndex: -1, myColor: '#00f5ff',
    players: [], started: false, over: false,
    // My car
    lane: 1, // 0=left 1=center 2=right
    x: 0, targetX: 0, health: MAX_HEALTH, score: 0, alive: true,
    // Others' cars (keyed by player_id)
    others: {},
    // Obstacles (host manages, relayed to guests)
    obstacles: [],
    scrollY: 0,
    speedMult: 1,
    lastObstacleTime: 0,
    rafId: null, lastTime: 0,
    keys: {},
    lastSendTime: 0,
    lastObstacleSend: 0,
    inputCooldown: 0,
    laneChanging: false
};

const $ = id => document.getElementById(id);
const sections = {
    mode: $('mode-section'), join: $('join-section'),
    waiting: $('waiting-section'), game: $('game-section'), over: $('gameover-section')
};

function showSection(name) {
    Object.values(sections).forEach(el => el && el.classList.add('hidden'));
    if (sections[name]) sections[name].classList.remove('hidden');
}

function laneX(lane) {
    return ROAD_LEFT + lane * LANE_W + (LANE_W - CAR_W) / 2;
}

// ── Game init ──────────────────────────────────────────────────
function initGame() {
    gs.lane = 1;
    gs.x = laneX(1);
    gs.targetX = gs.x;
    gs.health = MAX_HEALTH;
    gs.score = 0;
    gs.alive = true;
    gs.obstacles = [];
    gs.scrollY = 0;
    gs.speedMult = 1;
    gs.lastObstacleTime = 0;
    gs.others = {};
    gs.players.forEach(p => {
        if (p.id !== socket.id) {
            gs.others[p.id] = {
                lane: 1, x: laneX(1), color: p.color, name: p.name, alive: true, score: 0
            };
        }
    });
}

// ── Physics ────────────────────────────────────────────────────
function update(ts) {
    if (gs.over) return;
    const dt = ts - gs.lastTime;
    gs.lastTime = ts;

    // Difficulty ramp
    gs.speedMult = 1 + gs.score / 2000;
    const scroll = SCROLL_BASE * gs.speedMult;
    gs.scrollY = (gs.scrollY + scroll) % 80;

    // Lane change input
    if (gs.inputCooldown > 0) gs.inputCooldown -= dt;
    if (gs.alive && gs.inputCooldown <= 0) {
        if ((gs.keys['ArrowLeft'] || gs.keys['a']) && gs.lane > 0) {
            gs.lane--;
            gs.targetX = laneX(gs.lane);
            gs.inputCooldown = 250;
        } else if ((gs.keys['ArrowRight'] || gs.keys['d']) && gs.lane < LANE_COUNT - 1) {
            gs.lane++;
            gs.targetX = laneX(gs.lane);
            gs.inputCooldown = 250;
        }
    }

    // Smooth car slide
    gs.x += (gs.targetX - gs.x) * 0.2;

    // Move obstacles
    gs.obstacles.forEach(o => { o.y += scroll; });
    gs.obstacles = gs.obstacles.filter(o => o.y < H + OBS_H);

    // Host: spawn + broadcast obstacles
    if (gs.isHost) {
        const now = performance.now();
        if (now - gs.lastObstacleTime > SPAWN_INTERVAL / gs.speedMult) {
            spawnObstacle();
            gs.lastObstacleTime = now;
        }
        if (now - gs.lastObstacleSend > 100) {
            socket.emit('rf_obstacles', {
                room_code: gs.roomCode,
                obstacles: gs.obstacles,
                scroll_y: gs.scrollY
            });
            gs.lastObstacleSend = now;
        }
    }

    // Collision detection (for myself)
    if (gs.alive) {
        const myCarY = H - 120;
        gs.obstacles.forEach(o => {
            const dx = Math.abs(gs.x + CAR_W / 2 - (o.x + OBS_W / 2));
            const dy = Math.abs(myCarY + CAR_H / 2 - (o.y + OBS_H / 2));
            if (dx < (CAR_W + OBS_W) / 2 - 8 && dy < (CAR_H + OBS_H) / 2 - 10) {
                o.hit = true;
                gs.health--;
                gs.obstacles = gs.obstacles.filter(obs => obs !== o);
                if (gs.health <= 0) {
                    gs.alive = false;
                    checkAllDead();
                }
            }
        });
        gs.score += Math.round(scroll);
    }

    // Send my state
    const now = performance.now();
    if (now - gs.lastSendTime > 80) {
        socket.emit('rf_player_update', {
            room_code: gs.roomCode,
            x: gs.x, lane: gs.lane,
            health: gs.health, score: gs.score, alive: gs.alive
        });
        gs.lastSendTime = now;
    }
}

function spawnObstacle() {
    const lane = Math.floor(Math.random() * LANE_COUNT);
    const doubleWide = Math.random() < 0.2 && lane < LANE_COUNT - 1;
    gs.obstacles.push({
        x: ROAD_LEFT + lane * LANE_W + (LANE_W - OBS_W) / 2,
        y: -OBS_H,
        w: doubleWide ? OBS_W + LANE_W : OBS_W,
        color: OBS_COLORS[Math.floor(Math.random() * OBS_COLORS.length)],
        hit: false
    });
}

function checkAllDead() {
    const othersDead = Object.values(gs.others).every(o => !o.alive);
    if (!gs.alive && othersDead) {
        const results = gs.players.map(p => ({
            id: p.id,
            name: p.name,
            score: p.id === socket.id ? gs.score : (gs.others[p.id]?.score || 0)
        })).sort((a, b) => b.score - a.score);
        if (gs.isHost) {
            socket.emit('rf_game_over', { room_code: gs.roomCode, results });
        }
    }
}

// ── Render ─────────────────────────────────────────────────────
function render() {
    // Sky / background
    ctx.fillStyle = '#0a0015';
    ctx.fillRect(0, 0, W, H);

    // Road
    ctx.fillStyle = '#1a1a2e';
    ctx.fillRect(ROAD_LEFT, 0, ROAD_W, H);

    // Road edges glow
    ctx.shadowColor = '#00f5ff';
    ctx.shadowBlur = 15;
    ctx.strokeStyle = '#00f5ff';
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(ROAD_LEFT, 0); ctx.lineTo(ROAD_LEFT, H);
    ctx.moveTo(ROAD_RIGHT, 0); ctx.lineTo(ROAD_RIGHT, H);
    ctx.stroke();
    ctx.shadowBlur = 0;

    // Lane dividers (dashed, scrolling)
    ctx.strokeStyle = 'rgba(255,255,255,0.15)';
    ctx.lineWidth = 2;
    ctx.setLineDash([30, 25]);
    ctx.lineDashOffset = -gs.scrollY * 2;
    for (let i = 1; i < LANE_COUNT; i++) {
        const x = ROAD_LEFT + i * LANE_W;
        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke();
    }
    ctx.setLineDash([]);

    // Side scenery (buildings)
    drawScenery();

    // Obstacles
    gs.obstacles.forEach(o => drawObstacleCar(o));

    // Other players
    Object.values(gs.others).forEach(o => {
        if (o.alive) drawMyCar(o.x, H - 120, o.color, false);
    });

    // My car
    const myY = H - 120;
    if (gs.alive) {
        drawMyCar(gs.x, myY, gs.myColor, true);
    } else {
        ctx.globalAlpha = 0.3;
        drawMyCar(gs.x, myY, '#888', true);
        ctx.globalAlpha = 1;
    }

    // HUD
    drawHUD();
}

function drawMyCar(x, y, color, isMe) {
    // Body
    ctx.shadowColor = color;
    ctx.shadowBlur = isMe ? 20 : 8;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.roundRect(x, y, CAR_W, CAR_H, 8);
    ctx.fill();

    // Windshield
    ctx.fillStyle = 'rgba(0,0,0,0.4)';
    ctx.beginPath();
    ctx.roundRect(x + 6, y + 8, CAR_W - 12, 24, 4);
    ctx.fill();

    // Headlights
    ctx.shadowColor = '#ffffaa';
    ctx.shadowBlur = 15;
    ctx.fillStyle = '#ffffcc';
    [[x + 5, y + 6], [x + CAR_W - 13, y + 6]].forEach(([lx, ly]) => {
        ctx.beginPath(); ctx.roundRect(lx, ly, 8, 4, 2); ctx.fill();
    });

    // Taillights (at bottom of car)
    ctx.shadowColor = '#ff4444';
    ctx.shadowBlur = 12;
    ctx.fillStyle = '#ff2222';
    [[x + 5, y + CAR_H - 10], [x + CAR_W - 13, y + CAR_H - 10]].forEach(([lx, ly]) => {
        ctx.beginPath(); ctx.roundRect(lx, ly, 8, 5, 2); ctx.fill();
    });
    ctx.shadowBlur = 0;
}

function drawObstacleCar(o) {
    ctx.shadowColor = o.color;
    ctx.shadowBlur = 10;
    ctx.fillStyle = o.color;
    ctx.beginPath();
    ctx.roundRect(o.x, o.y, o.w || OBS_W, OBS_H, 8);
    ctx.fill();
    // Windshield
    ctx.fillStyle = 'rgba(0,0,0,0.4)';
    ctx.beginPath();
    ctx.roundRect(o.x + 6, o.y + OBS_H - 32, (o.w || OBS_W) - 12, 22, 4);
    ctx.fill();
    // Headlights (at bottom since coming toward player)
    ctx.fillStyle = '#ffffcc';
    ctx.shadowColor = '#ffffaa';
    ctx.shadowBlur = 15;
    [[o.x + 5, o.y + OBS_H - 10], [o.x + (o.w || OBS_W) - 13, o.y + OBS_H - 10]].forEach(([lx, ly]) => {
        ctx.beginPath(); ctx.roundRect(lx, ly, 8, 4, 2); ctx.fill();
    });
    ctx.shadowBlur = 0;
}

function drawScenery() {
    // Simple scrolling building silhouettes
    const offset = (gs.scrollY * 1.5) % 200;
    ctx.fillStyle = 'rgba(20,10,40,0.8)';
    const buildings = [[5,120,40,offset],[20,80,35,offset+60],[10,100,45,offset+120]];
    buildings.forEach(([x, h, w, dy]) => {
        ctx.fillRect(x, H - h + (dy % 200) - 200, w, h);
        ctx.fillRect(x, H - h + (dy % 200), w, h);
        ctx.fillRect(W - x - w, H - h + (dy % 200 + 100) - 200, w, h);
        ctx.fillRect(W - x - w, H - h + (dy % 200 + 100), w, h);
    });
}

function drawHUD() {
    // Speed/score
    ctx.fillStyle = 'rgba(0,0,0,0.6)';
    ctx.beginPath(); ctx.roundRect(8, 8, 150, 60, 8); ctx.fill();

    ctx.font = 'bold 13px Orbitron, monospace';
    ctx.fillStyle = gs.myColor;
    ctx.textAlign = 'left';
    ctx.fillText(`SCORE: ${gs.score}`, 18, 30);
    ctx.font = '12px Space Grotesk, sans-serif';
    ctx.fillStyle = 'rgba(255,255,255,0.7)';
    ctx.fillText(`SPEED: ${(gs.speedMult * 100).toFixed(0)}km/h`, 18, 52);

    // Health
    for (let i = 0; i < MAX_HEALTH; i++) {
        ctx.fillStyle = i < gs.health ? '#ff2244' : 'rgba(255,255,255,0.15)';
        ctx.font = '18px monospace';
        ctx.textAlign = 'right';
        ctx.fillText('♥', W - 12 - (MAX_HEALTH - 1 - i) * 22, 36);
    }

    // Controls
    ctx.font = '10px Space Grotesk, sans-serif';
    ctx.fillStyle = 'rgba(255,255,255,0.3)';
    ctx.textAlign = 'center';
    ctx.fillText('← → to change lanes', W / 2, H - 8);

    // Dead overlay
    if (!gs.alive) {
        ctx.fillStyle = 'rgba(255,0,0,0.15)';
        ctx.fillRect(0, 0, W, H);
        ctx.font = 'bold 28px Orbitron, monospace';
        ctx.fillStyle = '#ff4444';
        ctx.textAlign = 'center';
        ctx.fillText('WRECKED', W / 2, H / 2);
    }
}

// ── Main loop ─────────────────────────────────────────────────
function loop(ts) {
    if (gs.over) return;
    update(ts);
    render();
    gs.rafId = requestAnimationFrame(loop);
}

// ── Socket events ─────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    bindUI();
    setupSocket();
    showSection('mode');
});

function bindUI() {
    cleanup.addEventListener($('create-btn'), 'click', () =>
        socket.emit('create_room', { game_type: 'roadfighter', player_name: getUserName() }));
    cleanup.addEventListener($('join-btn-show'), 'click', () => showSection('join'));
    cleanup.addEventListener($('back-to-mode'), 'click', () => showSection('mode'));
    cleanup.addEventListener($('join-submit'), 'click', doJoin);
    cleanup.addEventListener($('room-code-input'), 'keypress', e => { if (e.key === 'Enter') doJoin(); });
    cleanup.addEventListener($('copy-code-btn'), 'click', () => copyToClipboard(gs.roomCode, () => showMessage('Copied!', 'success')));
    cleanup.addEventListener($('start-btn'), 'click', () =>
        socket.emit('start_game', { game_type: 'roadfighter', room_code: gs.roomCode }));
    cleanup.addEventListener($('leave-btn'), 'click', leaveRoom);
    cleanup.addEventListener($('play-again-btn'), 'click', () => { leaveRoom(); cleanup.addTimeout(setTimeout(() => showSection('mode'), 100)); });
    cleanup.addEventListener($('exit-btn'), 'click', () => window.location.href = '/');
}

function doJoin() {
    const code = $('room-code-input').value.trim().toUpperCase();
    if (!code) { showMessage('Enter a room code', 'error'); return; }
    socket.emit('join_room', { game_type: 'roadfighter', room_code: code, player_name: getUserName() });
}

function leaveRoom() {
    if (gs.roomCode) socket.emit('leave_room', { game_type: 'roadfighter', room_code: gs.roomCode });
    gs.roomCode = null; gs.started = false; gs.over = false;
    cancelAnimationFrame(gs.rafId);
    showSection('mode');
}

function setupSocket() {
    cleanup.addSocketListener(socket, 'room_created', data => {
        gs.roomCode = data.room_code; gs.isHost = true;
        gs.myIndex = data.your_index; gs.myColor = data.your_color;
        gs.players = data.players;
        updateWaiting(); showSection('waiting');
    });
    cleanup.addSocketListener(socket, 'room_joined', data => {
        gs.roomCode = data.room_code; gs.isHost = false;
        gs.myIndex = data.your_index; gs.myColor = data.your_color;
        gs.players = data.players;
        updateWaiting(); showSection('waiting');
    });
    cleanup.addSocketListener(socket, 'player_joined', data => { gs.players = data.players; updateWaiting(); });
    cleanup.addSocketListener(socket, 'player_left', data => { gs.players = data.players; updateWaiting(); });

    cleanup.addSocketListener(socket, 'game_started', data => {
        gs.players = data.players;
        gs.started = true; gs.over = false;
        initGame();
        showSection('game');
        bindKeys();
        gs.lastTime = performance.now();
        gs.rafId = requestAnimationFrame(loop);
    });

    cleanup.addSocketListener(socket, 'rf_player_update', data => {
        if (data.player_id === socket.id) return;
        if (gs.others[data.player_id]) {
            gs.others[data.player_id].x = data.x;
            gs.others[data.player_id].lane = data.lane;
            gs.others[data.player_id].alive = data.alive;
            gs.others[data.player_id].score = data.score;
        }
        if (!data.alive) checkAllDead();
    });

    cleanup.addSocketListener(socket, 'rf_obstacles', data => {
        if (gs.isHost) return; // guest only
        gs.obstacles = data.obstacles;
        gs.scrollY = data.scroll_y;
    });

    cleanup.addSocketListener(socket, 'rf_game_over', data => {
        gs.over = true;
        cancelAnimationFrame(gs.rafId);
        if (data.results) {
            const myRank = data.results.findIndex(r => r.id === socket.id);
            $('result-text').textContent = myRank === 0 ? 'You Win!' : `You finished #${myRank + 1}`;
            $('final-scores').innerHTML = data.results.map((r, i) =>
                `<div class="ranking-item${i === 0 ? ' winner' : ''}">
                  <span class="rank">${i === 0 ? '1st' : i === 1 ? '2nd' : '3rd'}</span>
                  <span>${r.name}</span>
                  <span style="margin-left:auto;color:var(--primary-color)">${r.score} pts</span>
                </div>`
            ).join('');
        }
        showSection('over');
    });

    cleanup.addSocketListener(socket, 'error', data => showMessage(data.message, 'error'));
}

function bindKeys() {
    cleanup.addEventListener(window, 'keydown', e => {
        gs.keys[e.key] = true;
        if (['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)) e.preventDefault();
    });
    cleanup.addEventListener(window, 'keyup', e => { gs.keys[e.key] = false; });
}

function updateWaiting() {
    $('display-room-code').textContent = gs.roomCode;
    $('waiting-players').innerHTML = gs.players.map(p =>
        `<div class="player-item${p.is_host ? ' host' : ''}">
          <div class="player-number" style="background:${p.color}">${p.index + 1}</div>
          <span>${p.name}</span>${p.is_host ? '<span class="host-badge">HOST</span>' : ''}
         </div>`
    ).join('');
    const startBtn = $('start-btn');
    if (startBtn) startBtn.classList.toggle('hidden', !gs.isHost);
}
