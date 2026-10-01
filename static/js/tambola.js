// Tambola (Housie) client-side logic
let socket;
let gameId;
let playerId;
let isHost = false;
let claimedWins = new Set();

document.addEventListener('DOMContentLoaded', () => {
    socket = io();

    document.getElementById('createGame').addEventListener('click', createGame);
    document.getElementById('joinGame').addEventListener('click', joinGame);
    document.getElementById('callNumber').addEventListener('click', callNumber);
    document.getElementById('startGame').addEventListener('click', startGame);

    socket.on('tambola_joined', handleJoined);
    socket.on('tambola_player_count', handlePlayerCount);
    socket.on('tambola_started', handleStarted);
    socket.on('tambola_number_called', handleNumberCalled);
    socket.on('tambola_win_announced', handleWinAnnounced);
    socket.on('tambola_win_rejected', handleWinRejected);
    socket.on('tambola_game_over', handleGameOver);
    socket.on('tambola_error', handleError);
});

function createGame() {
    const playerName = document.getElementById('playerNameInput').value.trim() || 'Host';

    fetch('/tambola/create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ player_name: playerName })
    })
    .then(res => res.json())
    .then(data => {
        if (data.status !== 'ok') {
            showStatus('Error: ' + data.message, 'error');
            return;
        }

        gameId = data.game_id;
        playerId = data.player_id;
        isHost = true;

        socket.emit('tambola_join', { game_id: gameId, player_id: playerId });

        showGameArea(data.ticket);
        document.getElementById('hostControls').style.display = 'block';
        document.getElementById('startGame').style.display = 'inline-block';
        document.getElementById('callNumber').style.display = 'none';
        showStatus('Game created! Share this Game ID with others: ' + gameId);
    })
    .catch(() => showStatus('Failed to create game. Please try again.', 'error'));
}

function joinGame() {
    const inputId = document.getElementById('gameIdInput').value.trim().toUpperCase();
    const playerName = document.getElementById('playerNameInput').value.trim() || 'Player';

    if (!inputId) {
        showStatus('Please enter a Game ID to join.', 'error');
        return;
    }

    fetch(`/tambola/join/${inputId}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ player_name: playerName })
    })
    .then(res => res.json())
    .then(data => {
        if (data.status !== 'ok') {
            showStatus('Error: ' + data.message, 'error');
            return;
        }

        gameId = data.game_id;
        playerId = data.player_id;
        isHost = false;

        socket.emit('tambola_join', { game_id: gameId, player_id: playerId });

        showGameArea(data.ticket);
        showStatus('Joined game ' + gameId + '. Waiting for host to start…');
    })
    .catch(() => showStatus('Failed to join game. Please try again.', 'error'));
}

function showGameArea(ticket) {
    document.getElementById('lobby').style.display = 'none';
    document.getElementById('gameArea').style.display = 'block';
    document.getElementById('gameIdDisplay').textContent = gameId;
    renderTicket(ticket);
}

function startGame() {
    socket.emit('tambola_start', { game_id: gameId, player_id: playerId });
}

function callNumber() {
    socket.emit('tambola_call_number', { game_id: gameId, player_id: playerId });
}

function claimWin(winType) {
    if (claimedWins.has(winType)) return;
    socket.emit('tambola_claim_win', { game_id: gameId, player_id: playerId, win_type: winType });
}

// --- Ticket rendering ---

function renderTicket(ticket) {
    const grid = document.getElementById('ticketGrid');
    grid.innerHTML = '';

    ticket.grid.forEach(row => {
        row.forEach(cell => {
            const div = document.createElement('div');
            div.className = 'ticket-cell' + (cell === null ? ' empty' : '');
            if (cell !== null) {
                div.textContent = cell;
                div.dataset.number = cell;
            }
            grid.appendChild(div);
        });
    });
}

function autoMarkNumber(number) {
    document.querySelectorAll('.ticket-cell').forEach(cell => {
        if (parseInt(cell.dataset.number) === number) {
            cell.classList.add('marked');
        }
    });
}

// --- Socket event handlers ---

function handleJoined(data) {
    document.getElementById('playerCount').textContent = data.player_count;

    if (data.called_numbers && data.called_numbers.length > 0) {
        data.called_numbers.forEach(n => {
            addCalledBadge(n);
            autoMarkNumber(n);
        });
        document.getElementById('currentNumber').textContent =
            data.called_numbers[data.called_numbers.length - 1];
        document.getElementById('remainingCount').textContent =
            90 - data.called_numbers.length;
    }
}

function handlePlayerCount(data) {
    document.getElementById('playerCount').textContent = data.player_count;
}

function handleStarted(data) {
    showStatus('Game started with ' + data.player_count + ' players!', 'success');
    if (isHost) {
        document.getElementById('startGame').style.display = 'none';
        document.getElementById('callNumber').style.display = 'inline-block';
    }
}

function handleNumberCalled(data) {
    document.getElementById('currentNumber').textContent = data.number;
    document.getElementById('remainingCount').textContent = data.remaining;
    addCalledBadge(data.number);
    autoMarkNumber(data.number);
}

function addCalledBadge(number) {
    const badge = document.createElement('span');
    badge.className = 'called-badge';
    badge.textContent = number;
    document.getElementById('calledList').appendChild(badge);
}

function handleWinAnnounced(data) {
    const label = data.win_type.replace(/_/g, ' ').toUpperCase();
    showStatus(data.player_id + ' won ' + label + '!', 'success');

    // Disable the claim button for this prize for everyone
    const btn = document.getElementById('btn-' + data.win_type);
    if (btn) {
        btn.classList.add('claimed');
        btn.disabled = true;
        btn.textContent = '✓ ' + btn.textContent;
    }

    // Track locally so current player doesn't re-claim
    claimedWins.add(data.win_type);
}

function handleWinRejected(data) {
    const label = data.win_type.replace(/_/g, ' ').toUpperCase();
    showStatus('Invalid claim for ' + label + ': ' + data.message, 'error');
}

function handleGameOver(data) {
    showStatus(data.message, 'success');
    document.getElementById('callNumber').disabled = true;

    let summary = 'Game Over!\n\nWinners:\n';
    for (const [type, pid] of Object.entries(data.wins || {})) {
        summary += `  ${type.replace(/_/g, ' ')}: ${pid}\n`;
    }
    setTimeout(() => alert(summary), 300);
}

function handleError(data) {
    showStatus(data.message, 'error');
}

function showStatus(message, type = 'info') {
    const el = document.getElementById('statusMessage');
    el.textContent = message;
    el.className = 'status-' + type;
}
