/* Mafia client - all listeners routed through CleanupManager */
const cleanup = new CleanupManager();

const socket = io();
let currentRoom = null;
let myPlayerId = null;
let myRole = null;
let selectedTarget = null;

function joinGame() {
    const playerName = document.getElementById('player-name').value.trim();
    const roomCode = document.getElementById('room-code').value.trim() || generateRoomCode();

    if (!playerName) {
        alert('Please enter your name');
        return;
    }

    currentRoom = roomCode;
    socket.emit('mafia_join', { room_code: roomCode, player_name: playerName });
}

function generateRoomCode() {
    return Math.random().toString(36).substring(2, 8).toUpperCase();
}

function startGame() {
    socket.emit('mafia_start', { room_code: currentRoom });
}

function startVoting() {
    socket.emit('mafia_start_voting', { room_code: currentRoom });
}

function selectTarget(targetId, btnEl) {
    selectedTarget = targetId;

    // Highlight selected button
    document.querySelectorAll('.target-btn').forEach(btn => {
        btn.classList.remove('selected');
    });
    if (btnEl) {
        btnEl.classList.add('selected');
    }
}

function confirmAction() {
    if (!selectedTarget) {
        alert('Please select a target');
        return;
    }

    const phase = document.getElementById('phase-display').textContent;

    if (phase.includes('Night')) {
        // Determine action based on role
        let action = '';
        if (myRole === 'mafia') action = 'kill';
        else if (myRole === 'doctor') action = 'save';
        else if (myRole === 'detective') action = 'investigate';

        socket.emit('mafia_night_action', {
            room_code: currentRoom,
            action: action,
            target: selectedTarget
        });
    } else if (phase.includes('Voting')) {
        socket.emit('mafia_vote', {
            room_code: currentRoom,
            target: selectedTarget
        });
    }

    selectedTarget = null;
}

function leaveGame() {
    socket.emit('mafia_leave', { room_code: currentRoom });
    currentRoom = null;
    document.getElementById('lobby').classList.remove('hidden');
    document.getElementById('game-area').classList.add('hidden');
}

// Socket event handlers (tracked for cleanup)
cleanup.addSocketListener(socket, 'mafia_joined', (data) => {
    document.getElementById('lobby').classList.add('hidden');
    document.getElementById('game-area').classList.remove('hidden');
    document.getElementById('display-room-code').textContent = data.room_code;
});

cleanup.addSocketListener(socket, 'mafia_state', (state) => {
    updateGameState(state);
});

cleanup.addSocketListener(socket, 'mafia_started', () => {
    document.getElementById('start-game-btn').classList.add('hidden');
});

cleanup.addSocketListener(socket, 'mafia_action_confirmed', () => {
    document.getElementById('action-panel').classList.add('hidden');
    alert('Action submitted!');
});

cleanup.addSocketListener(socket, 'mafia_vote_confirmed', () => {
    document.getElementById('action-panel').classList.add('hidden');
    alert('Vote submitted!');
});

cleanup.addSocketListener(socket, 'mafia_game_over', (data) => {
    const winner = data.winner === 'villagers' ? 'Villagers Win!' : 'Mafia Wins!';
    document.getElementById('winner-announcement').textContent = winner;
    document.getElementById('winner-announcement').classList.remove('hidden');
});

cleanup.addSocketListener(socket, 'mafia_error', (data) => {
    alert('Error: ' + data.error);
});

function updateGameState(state) {
    // Update phase display
    document.getElementById('phase-display').textContent =
        state.phase === 'lobby' ? 'Waiting for players...' :
        state.phase === 'night' ? `Night ${state.round}` :
        state.phase === 'day' ? `Day ${state.round}` :
        state.phase === 'voting' ? 'Voting Phase' :
        'Game Over';

    // Update players list
    const playersContainer = document.getElementById('players-container');
    playersContainer.innerHTML = '';

    state.players.forEach(player => {
        const playerCard = document.createElement('div');
        playerCard.className = 'player-card' + (player.alive ? '' : ' player-dead');
        playerCard.innerHTML = `
            <div class="player-name">${player.name}</div>
            <div class="player-status">${player.alive ? 'Alive' : 'Out'}</div>
        `;
        playersContainer.appendChild(playerCard);

        // Save my role
        if (player.role) {
            myRole = player.role;
            document.getElementById('player-role').textContent = player.role.toUpperCase();
            document.getElementById('role-card').classList.remove('hidden');

            const descriptions = {
                'mafia': 'Eliminate villagers during the night. Win when you equal or outnumber them.',
                'doctor': 'Save one player each night from the Mafia.',
                'detective': 'Investigate one player each night to discover if they are Mafia.',
                'villager': 'Find and eliminate the Mafia during day voting.'
            };
            document.getElementById('role-description').textContent = descriptions[player.role] || '';
        }
    });

    // Update action panel
    if (state.phase === 'night' && myRole && myRole !== 'villager') {
        showActionPanel(state.players, 'night');
    } else if (state.phase === 'voting') {
        showActionPanel(state.players, 'voting');
        document.getElementById('start-voting-btn').classList.add('hidden');
    } else {
        document.getElementById('action-panel').classList.add('hidden');

        if (state.phase === 'day') {
            document.getElementById('start-voting-btn').classList.remove('hidden');
        }
    }

    // Show investigation result
    if (state.investigation_result) {
        const result = state.investigation_result;
        document.getElementById('investigation-result').textContent =
            `Investigation: ${result.target} is ${result.is_mafia ? 'MAFIA' : 'NOT MAFIA'}`;
        document.getElementById('investigation-result').classList.remove('hidden');
    }

    // Update game log
    const logContainer = document.getElementById('log-container');
    logContainer.innerHTML = '';
    state.log.forEach(entry => {
        const logEntry = document.createElement('div');
        logEntry.className = 'log-entry';
        logEntry.textContent = entry;
        logContainer.appendChild(logEntry);
    });

    // Scroll log to bottom
    logContainer.scrollTop = logContainer.scrollHeight;
}

function showActionPanel(players, phase) {
    document.getElementById('action-panel').classList.remove('hidden');

    const actionButtons = document.getElementById('action-buttons');
    actionButtons.innerHTML = '';

    const actionTitle = document.getElementById('action-title');
    if (phase === 'night') {
        if (myRole === 'mafia') actionTitle.textContent = 'Choose a target to kill';
        else if (myRole === 'doctor') actionTitle.textContent = 'Choose a player to save';
        else if (myRole === 'detective') actionTitle.textContent = 'Choose a player to investigate';
    } else if (phase === 'voting') {
        actionTitle.textContent = 'Vote to eliminate';
    }

    // Create target buttons
    players.forEach(player => {
        if (player.alive && player.id !== socket.id) {
            const btn = document.createElement('button');
            btn.className = 'target-btn';
            btn.textContent = player.name;
            cleanup.addEventListener(btn, 'click', () => selectTarget(player.id, btn));
            actionButtons.appendChild(btn);
        }
    });
}

// ── DOM wiring (tracked for cleanup) ──────────────────────
document.addEventListener('DOMContentLoaded', () => {
    cleanup.addEventListener(document.getElementById('mafia-join-btn'), 'click', joinGame);
    cleanup.addEventListener(document.getElementById('mafia-confirm-btn'), 'click', confirmAction);
    cleanup.addEventListener(document.getElementById('start-game-btn'), 'click', startGame);
    cleanup.addEventListener(document.getElementById('start-voting-btn'), 'click', startVoting);
    cleanup.addEventListener(document.getElementById('mafia-leave-btn'), 'click', leaveGame);
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    cleanup.cleanup();
});

console.log('Mafia script loaded with CleanupManager');
