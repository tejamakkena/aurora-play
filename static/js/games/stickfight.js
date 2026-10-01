// ============================================================
//  STICK FIGHT — Multiplayer Arena Brawler
//  Host runs authoritative physics; clients relay input state
// ============================================================

const socket = io('/stickfight');
const cleanup = new CleanupManager();

// ── Canvas ─────────────────────────────────────────────────────
const canvas = document.getElementById('sf-canvas');
const ctx = canvas.getContext('2d');
const W = 900, H = 550;
canvas.width = W; canvas.height = H;

// ── Constants ──────────────────────────────────────────────────
const GRAVITY = 0.55;
const JUMP_FORCE = -13;
const MOVE_SPEED = 4.5;
const MAX_FALL = 18;
const PLAYER_W = 22, PLAYER_H = 52;
const PUNCH_RANGE = 70, PUNCH_DMGLOW = 12, PUNCH_DMGHIGH = 18;
const KICK_RANGE = 90, KICK_DMG = 24;
const ATTACK_COOLDOWN = 600;
const GROUND_Y = H - 60;

const PLATFORMS = [
    { x: 0, y: GROUND_Y, w: W, h: 60, ground: true },
    { x: 180, y: 380, w: 180, h: 18 },
    { x: 540, y: 380, w: 180, h: 18 },
    { x: 350, y: 270, w: 200, h: 18 },
];

// ── Game state ─────────────────────────────────────────────────
let gs = {
    roomCode: null, isHost: false, myIndex: -1,
    myColor: '#00f5ff', players: [], started: false, over: false,
    entities: {}, // keyed by player_id
    keys: {},
    lastStateSend: 0
};

const $ = id => document.getElementById(id);
const sections = {
    mode: $('mode-section'),
    join: $('join-section'),
    waiting: $('waiting-section'),
    game: $('game-section'),
    over: $('gameover-section')
};

function showSection(name) {
    Object.values(sections).forEach(el => el && el.classList.add('hidden'));
    if (sections[name]) sections[name].classList.remove('hidden');
}

// ── Player entity factory ─────────────────────────────────────
function makeEntity(playerId, color, spawnX) {
    return {
        id: playerId, color,
        x: spawnX, y: GROUND_Y - PLAYER_H,
        vx: 0, vy: 0,
        onGround: true,
        facing: 1,
        health: 100,
        state: 'idle', // idle run jump attack hurt dead
        attackTimer: 0,
        hurtTimer: 0,
        dead: false,
        kills: 0
    };
}

function spawnEntities() {
    gs.entities = {};
    gs.players.forEach((p, i) => {
        const spawnX = 120 + i * (W - 240) / Math.max(gs.players.length - 1, 1);
        gs.entities[p.id] = makeEntity(p.id, p.color, spawnX);
    });
}

// ── Physics (host only) ────────────────────────────────────────
function updatePhysics(dt) {
    const me = gs.entities[socket.id];
    if (!me || me.dead) return;

    // Input
    const left = gs.keys['ArrowLeft'] || gs.keys['a'];
    const right = gs.keys['ArrowRight'] || gs.keys['d'];
    const jump = gs.keys['ArrowUp'] || gs.keys['w'] || gs.keys[' '];
    const punch = gs.keys['j'];
    const kick = gs.keys['k'];

    if (left) { me.vx = -MOVE_SPEED; me.facing = -1; }
    else if (right) { me.vx = MOVE_SPEED; me.facing = 1; }
    else { me.vx *= 0.7; }

    if (jump && me.onGround) { me.vy = JUMP_FORCE; me.onGround = false; }

    // Cooldowns
    if (me.attackTimer > 0) me.attackTimer -= dt;
    if (me.hurtTimer > 0) me.hurtTimer -= dt;

    // Attack
    if (punch && me.attackTimer <= 0) {
        me.state = 'attack';
        me.attackTimer = ATTACK_COOLDOWN;
        doAttack(me, PUNCH_RANGE, PUNCH_DMGLOW + Math.random() * (PUNCH_DMGHIGH - PUNCH_DMGLOW));
    } else if (kick && me.attackTimer <= 0) {
        me.state = 'attack';
        me.attackTimer = ATTACK_COOLDOWN * 1.5;
        doAttack(me, KICK_RANGE, KICK_DMG);
    }

    applyGravityAndCollision(me);

    // State machine
    if (!me.dead) {
        if (me.hurtTimer > 0) me.state = 'hurt';
        else if (me.attackTimer > ATTACK_COOLDOWN - 200) me.state = 'attack';
        else if (!me.onGround) me.state = 'jump';
        else if (Math.abs(me.vx) > 0.5) me.state = 'run';
        else me.state = 'idle';
    }

    // Fall death
    if (me.y > H + 100) {
        me.health -= 30;
        me.x = 120 + gs.myIndex * 200;
        me.y = GROUND_Y - PLAYER_H;
        me.vx = 0; me.vy = 0;
        if (me.health <= 0) killPlayer(me);
    }
}

function applyGravityAndCollision(e) {
    e.vy = Math.min(e.vy + GRAVITY, MAX_FALL);
    e.x += e.vx;
    e.y += e.vy;

    e.onGround = false;
    for (const plat of PLATFORMS) {
        if (e.x + PLAYER_W > plat.x && e.x < plat.x + plat.w &&
            e.y + PLAYER_H >= plat.y && e.y + PLAYER_H <= plat.y + 20 &&
            e.vy >= 0) {
            e.y = plat.y - PLAYER_H;
            e.vy = 0;
            e.onGround = true;
        }
    }
    e.x = Math.max(0, Math.min(W - PLAYER_W, e.x));
}

function doAttack(attacker, range, dmg) {
    Object.values(gs.entities).forEach(victim => {
        if (victim.id === attacker.id || victim.dead) return;
        const dx = victim.x - attacker.x;
        const dy = Math.abs((victim.y + PLAYER_H / 2) - (attacker.y + PLAYER_H / 2));
        if (Math.abs(dx) < range && dy < PLAYER_H * 0.8 &&
            Math.sign(dx) === attacker.facing) {
            victim.health = Math.max(0, victim.health - Math.round(dmg));
            victim.vx = attacker.facing * 6;
            victim.vy = -5;
            victim.hurtTimer = 300;
            if (victim.health <= 0) {
                killPlayer(victim);
                attacker.kills++;
            }
            // Host broadcasts hit
            socket.emit('sf_attack_hit', {
                room_code: gs.roomCode,
                attacker_id: attacker.id,
                victim_id: victim.id,
                damage: Math.round(dmg),
                victim_health: victim.health
            });
        }
    });
}

function killPlayer(e) {
    e.dead = true;
    e.state = 'dead';
    checkWin();
}

function checkWin() {
    const alive = Object.values(gs.entities).filter(e => !e.dead);
    if (alive.length <= 1) {
        const winner = alive[0];
        const scores = gs.players.map(p => ({
            id: p.id, name: p.name, kills: gs.entities[p.id]?.kills || 0
        }));
        socket.emit('sf_game_over', {
            room_code: gs.roomCode,
            winner_id: winner?.id || null,
            winner_name: winner ? gs.players.find(p => p.id === winner.id)?.name : 'Nobody',
            scores
        });
        endGame(winner?.id);
    }
}

// ── Host loop ────────────────────────────────────────────────
let lastTime = 0;
function hostLoop(ts) {
    if (gs.over) return;
    const dt = ts - lastTime; lastTime = ts;
    updatePhysics(dt);

    // Broadcast my state to others
    const me = gs.entities[socket.id];
    if (me) {
        const now = performance.now();
        if (now - gs.lastStateSend > 50) {
            socket.emit('sf_player_state', {
                room_code: gs.roomCode,
                x: me.x, y: me.y, vx: me.vx, vy: me.vy,
                facing: me.facing, state: me.state,
                health: me.health, attacking: me.attackTimer > ATTACK_COOLDOWN - 200
            });
            gs.lastStateSend = now;
        }
    }

    render();
    gs.rafId = requestAnimationFrame(hostLoop);
}

// ── Guest loop ───────────────────────────────────────────────
function guestLoop(ts) {
    if (gs.over) return;
    const dt = ts - lastTime; lastTime = ts;

    // Guest runs own physics locally too
    updatePhysics(dt);

    const me = gs.entities[socket.id];
    if (me) {
        const now = performance.now();
        if (now - gs.lastStateSend > 50) {
            socket.emit('sf_player_state', {
                room_code: gs.roomCode,
                x: me.x, y: me.y, vx: me.vx, vy: me.vy,
                facing: me.facing, state: me.state,
                health: me.health, attacking: me.attackTimer > ATTACK_COOLDOWN - 200
            });
            gs.lastStateSend = now;
        }
    }

    render();
    gs.rafId = requestAnimationFrame(guestLoop);
}

// ── Rendering ─────────────────────────────────────────────────
function render() {
    // Sky gradient
    const sky = ctx.createLinearGradient(0, 0, 0, H);
    sky.addColorStop(0, '#04000f');
    sky.addColorStop(1, '#0f002a');
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, W, H);

    // Stars
    ctx.fillStyle = 'rgba(255,255,255,0.3)';
    [[50,30],[150,80],[400,20],[650,60],[800,40],[250,100],[700,90]].forEach(([x,y]) => {
        ctx.beginPath(); ctx.arc(x, y, 1, 0, Math.PI*2); ctx.fill();
    });

    // Platforms
    PLATFORMS.forEach(plat => {
        if (plat.ground) {
            const grd = ctx.createLinearGradient(0, plat.y, 0, plat.y + plat.h);
            grd.addColorStop(0, '#1a0035');
            grd.addColorStop(1, '#0a0015');
            ctx.fillStyle = grd;
            ctx.fillRect(plat.x, plat.y, plat.w, plat.h);
            // Ground neon line
            ctx.shadowColor = '#00f5ff';
            ctx.shadowBlur = 10;
            ctx.fillStyle = '#00f5ff';
            ctx.fillRect(plat.x, plat.y, plat.w, 3);
            ctx.shadowBlur = 0;
        } else {
            ctx.shadowColor = '#bf5fff';
            ctx.shadowBlur = 12;
            const grd = ctx.createLinearGradient(plat.x, plat.y, plat.x, plat.y + plat.h);
            grd.addColorStop(0, '#bf5fff55');
            grd.addColorStop(1, '#7c3aed33');
            ctx.fillStyle = grd;
            ctx.beginPath();
            ctx.roundRect(plat.x, plat.y, plat.w, plat.h, 8);
            ctx.fill();
            ctx.strokeStyle = '#bf5fff';
            ctx.lineWidth = 2;
            ctx.stroke();
            ctx.shadowBlur = 0;
        }
    });

    // Entities
    Object.values(gs.entities).forEach(e => drawStickFigure(e));

    // HUD
    drawHUD();
}

function drawStickFigure(e) {
    if (e.dead) return;
    const { x, y, color, state, facing, health } = e;
    const cx = x + PLAYER_W / 2;
    const headY = y + 12;
    const bodyTop = y + 22;
    const bodyBot = y + 38;
    const alpha = e.hurtTimer > 0 ? (Math.sin(Date.now() / 60) > 0 ? 0.4 : 1) : 1;

    ctx.globalAlpha = alpha;
    ctx.shadowColor = color;
    ctx.shadowBlur = e.state === 'attack' ? 25 : 12;
    ctx.strokeStyle = color;
    ctx.lineWidth = 3;
    ctx.lineCap = 'round';

    // Head
    ctx.beginPath();
    ctx.arc(cx, headY, 10, 0, Math.PI * 2);
    ctx.stroke();

    // Body
    ctx.beginPath();
    ctx.moveTo(cx, bodyTop); ctx.lineTo(cx, bodyBot);
    ctx.stroke();

    // Legs
    if (state === 'run') {
        const t = Date.now() / 120;
        ctx.beginPath();
        ctx.moveTo(cx, bodyBot);
        ctx.lineTo(cx - 12 * Math.cos(t), y + PLAYER_H);
        ctx.moveTo(cx, bodyBot);
        ctx.lineTo(cx + 12 * Math.cos(t + Math.PI), y + PLAYER_H);
        ctx.stroke();
    } else {
        ctx.beginPath();
        ctx.moveTo(cx, bodyBot); ctx.lineTo(cx - 10, y + PLAYER_H);
        ctx.moveTo(cx, bodyBot); ctx.lineTo(cx + 10, y + PLAYER_H);
        ctx.stroke();
    }

    // Arms
    const armMid = bodyTop + 10;
    if (state === 'attack') {
        // Extended punch arm
        ctx.beginPath();
        ctx.moveTo(cx, armMid);
        ctx.lineTo(cx + facing * 40, armMid - 4);
        ctx.moveTo(cx, armMid);
        ctx.lineTo(cx - facing * 15, armMid + 10);
        ctx.stroke();
        // Fist glow
        ctx.shadowBlur = 30;
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(cx + facing * 40, armMid - 4, 6, 0, Math.PI * 2);
        ctx.fill();
    } else if (state === 'jump') {
        ctx.beginPath();
        ctx.moveTo(cx, armMid);
        ctx.lineTo(cx - 20, armMid - 20);
        ctx.moveTo(cx, armMid);
        ctx.lineTo(cx + 20, armMid - 20);
        ctx.stroke();
    } else {
        ctx.beginPath();
        ctx.moveTo(cx, armMid);
        ctx.lineTo(cx - 16, armMid + 15);
        ctx.moveTo(cx, armMid);
        ctx.lineTo(cx + 16, armMid + 15);
        ctx.stroke();
    }

    ctx.shadowBlur = 0;
    ctx.globalAlpha = 1;

    // Health bar
    const barW = 50, barH = 5;
    const barX = cx - barW / 2, barY = y - 18;
    ctx.fillStyle = 'rgba(0,0,0,0.5)';
    ctx.fillRect(barX, barY, barW, barH);
    const hp = Math.max(0, health) / 100;
    const hpColor = hp > 0.5 ? '#00ff88' : hp > 0.25 ? '#ffcc00' : '#ff4444';
    ctx.fillStyle = hpColor;
    ctx.fillRect(barX, barY, barW * hp, barH);

    // Name tag
    ctx.fillStyle = color;
    ctx.font = '11px Space Grotesk, sans-serif';
    ctx.textAlign = 'center';
    const pName = gs.players.find(p => p.id === e.id)?.name || '';
    ctx.fillText(pName, cx, y - 24);
}

function drawHUD() {
    const me = gs.entities[socket.id];
    if (!me) return;
    // Mini health indicator
    ctx.fillStyle = 'rgba(0,0,0,0.5)';
    ctx.beginPath();
    ctx.roundRect(16, 16, 200, 36, 8);
    ctx.fill();
    ctx.font = '12px Space Grotesk, sans-serif';
    ctx.fillStyle = gs.myColor;
    ctx.textAlign = 'left';
    ctx.fillText(`HP: ${Math.max(0, me.health)} | Kills: ${me.kills}`, 26, 39);

    // Controls reminder
    ctx.fillStyle = 'rgba(255,255,255,0.25)';
    ctx.font = '11px Space Grotesk, sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText('← → Move   ↑/W Jump   J Punch   K Kick', W - 16, H - 16);
}

// ── Socket ────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
    bindUI();
    setupSocket();
    showSection('mode');
});

function bindUI() {
    cleanup.addEventListener($('create-btn'), 'click', () => {
        socket.emit('create_room', { game_type: 'stickfight', player_name: getUserName() });
    });
    cleanup.addEventListener($('join-btn-show'), 'click', () => showSection('join'));
    cleanup.addEventListener($('back-to-mode'), 'click', () => showSection('mode'));
    cleanup.addEventListener($('join-submit'), 'click', joinRoom);
    cleanup.addEventListener($('room-code-input'), 'keypress', e => { if (e.key === 'Enter') joinRoom(); });
    cleanup.addEventListener($('copy-code-btn'), 'click', () => copyToClipboard(gs.roomCode, () => showMessage('Copied!', 'success')));
    cleanup.addEventListener($('start-btn'), 'click', () => socket.emit('start_game', { game_type: 'stickfight', room_code: gs.roomCode }));
    cleanup.addEventListener($('leave-btn'), 'click', leaveRoom);
    cleanup.addEventListener($('play-again-btn'), 'click', () => {
        leaveRoom();
        cleanup.addTimeout(setTimeout(() => showSection('mode'), 100));
    });
    cleanup.addEventListener($('exit-btn'), 'click', () => window.location.href = '/');
}

function joinRoom() {
    const code = $('room-code-input').value.trim().toUpperCase();
    if (!code) { showMessage('Enter a room code', 'error'); return; }
    socket.emit('join_room', { game_type: 'stickfight', room_code: code, player_name: getUserName() });
}

function leaveRoom() {
    if (gs.roomCode) socket.emit('leave_room', { game_type: 'stickfight', room_code: gs.roomCode });
    gs.roomCode = null; gs.started = false; gs.over = false;
    cancelAnimationFrame(gs.rafId);
    showSection('mode');
}

function setupSocket() {
    cleanup.addSocketListener(socket, 'room_created', data => {
        gs.roomCode = data.room_code; gs.isHost = true;
        gs.myIndex = data.your_index; gs.myColor = data.your_color;
        gs.players = data.players;
        updateWaiting();
        showSection('waiting');
    });

    cleanup.addSocketListener(socket, 'room_joined', data => {
        gs.roomCode = data.room_code; gs.isHost = false;
        gs.myIndex = data.your_index; gs.myColor = data.your_color;
        gs.players = data.players;
        updateWaiting();
        showSection('waiting');
    });

    cleanup.addSocketListener(socket, 'player_joined', data => {
        gs.players = data.players; updateWaiting();
    });

    cleanup.addSocketListener(socket, 'player_left', data => {
        gs.players = data.players; updateWaiting();
        if (gs.started) showMessage('A player left!', 'warning');
    });

    cleanup.addSocketListener(socket, 'game_started', data => {
        gs.players = data.players;
        gs.started = true; gs.over = false;
        spawnEntities();
        showSection('game');
        bindKeys();
        lastTime = performance.now();
        if (gs.isHost) gs.rafId = requestAnimationFrame(hostLoop);
        else gs.rafId = requestAnimationFrame(guestLoop);
    });

    // Receive other players' states
    cleanup.addSocketListener(socket, 'sf_player_state', data => {
        if (!gs.entities[data.player_id]) return;
        const e = gs.entities[data.player_id];
        if (data.player_id === socket.id) return; // own state
        e.x = data.x; e.y = data.y;
        e.vx = data.vx; e.vy = data.vy;
        e.facing = data.facing;
        e.state = data.state;
        e.health = data.health;
    });

    cleanup.addSocketListener(socket, 'sf_attack_hit', data => {
        const victim = gs.entities[data.victim_id];
        if (victim) {
            victim.health = data.victim_health;
            victim.hurtTimer = 300;
        }
    });

    cleanup.addSocketListener(socket, 'sf_game_over', data => {
        endGame(data.winner_id, data.winner_name, data.scores);
    });

    cleanup.addSocketListener(socket, 'error', data => showMessage(data.message, 'error'));
}

function endGame(winnerId, winnerName, scores) {
    gs.over = true;
    cancelAnimationFrame(gs.rafId);
    const isWinner = winnerId === socket.id;
    $('result-text').textContent = isWinner ? 'You Win!' : `${winnerName || 'No one'} wins!`;
    if (scores) {
        $('final-scores').innerHTML = scores.sort((a, b) => b.kills - a.kills)
            .map((s, i) => `<div class="ranking-item${i === 0 ? ' winner' : ''}">
              <span class="rank">${i === 0 ? '1st' : i === 1 ? '2nd' : '3rd'}</span>
              <span>${s.name}</span>
              <span style="margin-left:auto;color:var(--primary-color)">${s.kills} kills</span>
            </div>`).join('');
    }
    showSection('over');
}

function bindKeys() {
    cleanup.addEventListener(window, 'keydown', e => {
        gs.keys[e.key] = true;
        if (['ArrowUp','ArrowDown','ArrowLeft','ArrowRight',' '].includes(e.key)) e.preventDefault();
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
    if (startBtn) startBtn.classList.toggle('hidden', !gs.isHost || gs.players.length < 2);
}
