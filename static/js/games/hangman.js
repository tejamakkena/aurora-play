/* Hangman client - all listeners/timers routed through CleanupManager */
const cleanup = new CleanupManager();

const socket = io();

const BODY_PARTS = ['hm-head', 'hm-body', 'hm-left-arm', 'hm-right-arm', 'hm-left-leg', 'hm-right-leg'];
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');

const state = {
    roomCode: null,
    isHost: false,
    playerId: null,
    gameActive: false,
};

// ── Screens ──────────────────────────────────────────────
const screens = {
    mode:     document.getElementById('screen-mode'),
    join:     document.getElementById('screen-join'),
    waiting:  document.getElementById('screen-waiting'),
    setWord:  document.getElementById('screen-set-word'),
    waitWord: document.getElementById('screen-wait-word'),
    game:     document.getElementById('screen-game'),
    over:     document.getElementById('screen-over'),
};

function showScreen(name) {
    Object.values(screens).forEach(s => s.classList.add('hidden'));
    screens[name].classList.remove('hidden');
}

// ── Toast ─────────────────────────────────────────────────
let toastTimer;
function showToast(msg) {
    const t = document.getElementById('toast');
    t.textContent = msg;
    t.classList.add('show');
    cleanup.clearTimeout(toastTimer);
    toastTimer = cleanup.addTimeout(setTimeout(() => t.classList.remove('show'), 3000));
}

// ── Helpers ───────────────────────────────────────────────
function renderPlayers(players, containerId) {
    const el = document.getElementById(containerId);
    el.innerHTML = players.map(p => `
        <div class="player-item">
            <span>${p.name}${p.is_host ? '<span class="host-badge">host</span>' : ''}</span>
        </div>`).join('');
}

function buildWordDisplay(displayWord) {
    const wrap = document.getElementById('word-display');
    wrap.innerHTML = '';
    displayWord.forEach(ch => {
        if (ch === ' ') {
            const gap = document.createElement('div');
            gap.className = 'word-gap';
            wrap.appendChild(gap);
        } else {
            const slot = document.createElement('div');
            slot.className = 'letter-slot';
            const char = document.createElement('div');
            char.className = 'letter-char';
            char.textContent = ch !== '_' ? ch : '';
            const line = document.createElement('div');
            line.className = 'letter-line';
            slot.appendChild(char);
            slot.appendChild(line);
            wrap.appendChild(slot);
        }
    });
}

function updateHangman(wrongCount) {
    BODY_PARTS.forEach((id, i) => {
        const el = document.getElementById(id);
        if (!el) return;
        el.classList.toggle('visible', i < wrongCount);
        el.classList.toggle('wrong', i < wrongCount);
    });
}

function buildKeyboard(guessedLetters) {
    const kb = document.getElementById('keyboard');
    kb.innerHTML = '';
    ALPHABET.forEach(letter => {
        const btn = document.createElement('button');
        btn.className = 'key-btn';
        btn.textContent = letter;
        btn.dataset.letter = letter;
        if (guessedLetters.includes(letter)) {
            btn.disabled = true;
        }
        cleanup.addEventListener(btn, 'click', () => guessLetter(letter));
        kb.appendChild(btn);
    });
}

function markKey(letter, outcome) {
    const btn = document.querySelector(`.key-btn[data-letter="${letter}"]`);
    if (!btn) return;
    btn.disabled = true;
    btn.classList.add(outcome === 'correct' || outcome === 'win' ? 'correct' : 'wrong-key');
}

function applyGameState(data) {
    buildWordDisplay(data.display_word);
    updateHangman(data.wrong_count);

    const wrongDisp = document.getElementById('wrong-letters-disp');
    wrongDisp.textContent = data.wrong_guesses.join('  ') || '';

    document.getElementById('wrong-count-disp').textContent =
        `${data.wrong_count} / ${data.max_wrong} wrong`;

    const hintEl = document.getElementById('hint-disp');
    if (data.hint) {
        hintEl.textContent = `Hint: ${data.hint}`;
        hintEl.style.display = '';
    } else {
        hintEl.style.display = 'none';
    }

    if (state.isHost) {
        document.getElementById('host-panel').classList.remove('hidden');
        document.getElementById('keyboard').classList.add('hidden');
    } else {
        document.getElementById('host-panel').classList.add('hidden');
        document.getElementById('keyboard').classList.remove('hidden');
        buildKeyboard(data.guessed_letters);
    }
}

// ── Actions ───────────────────────────────────────────────
function createRoom() {
    socket.emit('hangman_create_room', {
        player_name: window.user.name,
    });
}

function joinRoom() {
    const code = document.getElementById('inp-room-code').value.trim().toUpperCase();
    if (!code) { showToast('Enter a room code!'); return; }
    socket.emit('hangman_join_room', {
        room_code: code,
        player_name: window.user.name,
    });
}

function startGame() {
    socket.emit('hangman_start_game', { room_code: state.roomCode });
}

function setWord() {
    const word = document.getElementById('inp-word').value.trim();
    const hint = document.getElementById('inp-hint').value.trim();
    if (!word) { showToast('Please enter a word!'); return; }
    socket.emit('hangman_set_word', { room_code: state.roomCode, word, hint });
}

function guessLetter(letter) {
    socket.emit('hangman_guess', { room_code: state.roomCode, letter });
}

function leaveRoom() {
    socket.emit('hangman_leave_room', { room_code: state.roomCode });
    state.roomCode = null;
    state.isHost = false;
    showScreen('mode');
}

function playAgain() {
    socket.emit('hangman_play_again', { room_code: state.roomCode });
}

// ── Socket events (tracked for cleanup) ───────────────────
cleanup.addSocketListener(socket, 'hangman_room_created', data => {
    state.roomCode = data.room_code;
    state.playerId = data.player_id;
    state.isHost = true;

    document.getElementById('disp-room-code').textContent = data.room_code;
    document.getElementById('btn-start').style.display = '';
    document.getElementById('waiting-hint').style.display = 'none';
    renderPlayers(data.players, 'players-container');
    showScreen('waiting');
});

cleanup.addSocketListener(socket, 'hangman_room_joined', data => {
    state.roomCode = data.room_code;
    state.playerId = data.player_id;
    state.isHost = false;

    document.getElementById('disp-room-code').textContent = data.room_code;
    document.getElementById('btn-start').style.display = 'none';
    document.getElementById('waiting-hint').style.display = '';
    renderPlayers(data.players, 'players-container');
    showScreen('waiting');
});

cleanup.addSocketListener(socket, 'hangman_player_joined', data => {
    renderPlayers(data.players, 'players-container');
});

cleanup.addSocketListener(socket, 'hangman_enter_word', () => {
    document.getElementById('inp-word').value = '';
    document.getElementById('inp-hint').value = '';
    showScreen('setWord');
});

cleanup.addSocketListener(socket, 'hangman_waiting_for_word', () => {
    showScreen('waitWord');
});

cleanup.addSocketListener(socket, 'hangman_game_started', data => {
    state.gameActive = true;

    if (state.isHost) {
        // Host sees the actual word
        document.getElementById('host-word-reveal').textContent = data.secret_word || '';
    }

    applyGameState(data);
    showScreen('game');
});

cleanup.addSocketListener(socket, 'hangman_letter_guessed', data => {
    applyGameState(data);

    if (!state.isHost && data.last_letter) {
        markKey(data.last_letter, data.outcome);
    }

    // Brief flash of who guessed
    if (data.guesser_name) {
        const verb = data.outcome === 'correct' ? 'correct' : 'wrong';
        showToast(`${data.guesser_name}: "${data.last_letter}" — ${verb}`);
    }
});

cleanup.addSocketListener(socket, 'hangman_game_over', data => {
    state.gameActive = false;

    // Final board state
    applyGameState(data);
    if (!state.isHost && data.last_letter) markKey(data.last_letter, data.outcome);

    // Over screen
    const resultEl = document.getElementById('over-result');
    if (data.winner === 'guessers') {
        resultEl.innerHTML = '<div class="result-win">Guessers Win!</div>';
    } else {
        resultEl.innerHTML = '<div class="result-lose">Host Wins!</div><p style="color:#aaa;margin-bottom:8px">The word was not guessed in time.</p>';
    }

    document.getElementById('over-word').textContent = data.secret_word || '';
    renderPlayers(data.players, 'over-players');

    // Only host gets "New Round" button
    document.getElementById('btn-play-again').style.display = state.isHost ? '' : 'none';

    showScreen('over');
});

cleanup.addSocketListener(socket, 'hangman_player_left', data => {
    renderPlayers(data.players, 'players-container');
    // If we are now host (new_host assigned server-side)
    const me = data.players.find(p => p.id === state.playerId);
    if (me && me.is_host && !state.isHost) {
        state.isHost = true;
        showToast('The host left — you are the new host!');
    }
    if (data.state === 'WAITING') {
        showScreen('waiting');
        document.getElementById('btn-start').style.display = state.isHost ? '' : 'none';
        document.getElementById('waiting-hint').style.display = state.isHost ? 'none' : '';
    }
});

cleanup.addSocketListener(socket, 'hangman_error', data => {
    showToast(data.message || 'Something went wrong!');
});

// ── DOM wiring (tracked for cleanup) ──────────────────────
document.addEventListener('DOMContentLoaded', () => {
    cleanup.addEventListener(document.getElementById('btn-create'), 'click', createRoom);
    cleanup.addEventListener(document.getElementById('btn-join-show'), 'click', () => showScreen('join'));
    cleanup.addEventListener(document.getElementById('btn-join-back'), 'click', () => showScreen('mode'));
    cleanup.addEventListener(document.getElementById('btn-join-submit'), 'click', joinRoom);
    cleanup.addEventListener(document.getElementById('inp-room-code'), 'keypress', e => {
        if (e.key === 'Enter') joinRoom();
    });
    cleanup.addEventListener(document.getElementById('btn-copy'), 'click', () => {
        navigator.clipboard.writeText(state.roomCode || '');
        showToast('Room code copied!');
    });
    cleanup.addEventListener(document.getElementById('btn-start'), 'click', startGame);
    cleanup.addEventListener(document.getElementById('btn-leave-waiting'), 'click', leaveRoom);
    cleanup.addEventListener(document.getElementById('btn-set-word'), 'click', setWord);
    cleanup.addEventListener(document.getElementById('inp-word'), 'keypress', e => {
        if (e.key === 'Enter') setWord();
    });
    cleanup.addEventListener(document.getElementById('btn-leave-game'), 'click', leaveRoom);
    cleanup.addEventListener(document.getElementById('btn-play-again'), 'click', playAgain);
    cleanup.addEventListener(document.getElementById('btn-exit'), 'click', leaveRoom);
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    cleanup.cleanup();
});

console.log('Hangman script loaded with CleanupManager');
