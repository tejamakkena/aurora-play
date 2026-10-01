/* Raja Mantri Chor Sipahi client - all listeners/timers routed through CleanupManager */
const cleanup = new CleanupManager();

// ── Mode navigation ──────────────────────────────────────────────────────────
function showMode() {
    document.getElementById('modeSection').style.display = 'block';
    document.getElementById('localSetup').style.display = 'none';
    document.getElementById('networkLobby').style.display = 'none';
}
function showLocalSetup() {
    document.getElementById('modeSection').style.display = 'none';
    document.getElementById('localSetup').style.display = 'block';
}
function showNetworkLobby() {
    document.getElementById('modeSection').style.display = 'none';
    document.getElementById('networkLobby').style.display = 'block';
}

// ── Local game (pass-and-play) ───────────────────────────────────────────────
let players = [];
let roles = ['Raja', 'Mantri', 'Chor', 'Sipahi'];
let playerRoles = {};
let revealedCount = 0;

function startLocalGame() {
    const names = ['player1','player2','player3','player4'].map(id =>
        document.getElementById(id).value.trim());
    if (names.some(n => !n)) { alert('Please enter all 4 player names!'); return; }

    players = names;
    const shuffled = [...roles].sort(() => Math.random() - 0.5);
    players.forEach((p, i) => { playerRoles[p] = shuffled[i]; });
    revealedCount = 0;

    document.getElementById('localSetup').style.display = 'none';
    document.getElementById('gameSection').style.display = 'block';
    createRoleButtons();
}

function createRoleButtons() {
    const container = document.getElementById('playerButtons');
    container.innerHTML = '';
    players.forEach(player => {
        const col = document.createElement('div');
        col.className = 'col-md-6 mb-2';

        const button = document.createElement('button');
        button.className = 'btn btn-outline-primary w-100';
        button.textContent = `${player} — Click to See Role`;
        cleanup.addEventListener(button, 'click', () => revealRole(player));

        col.appendChild(button);
        container.appendChild(col);
    });
}

function revealRole(player) {
    alert(`${player}, your role is: ${playerRoles[player]}`);
    revealedCount++;
    if (revealedCount === 4) showMantri();
}

function showMantri() {
    document.getElementById('roleReveal').style.display = 'none';
    const mantri = Object.keys(playerRoles).find(p => playerRoles[p] === 'Mantri');
    document.getElementById('mantriName').textContent = `${mantri} is the Mantri!`;
    document.getElementById('mantriSection').style.display = 'block';
    cleanup.addTimeout(setTimeout(showGuessingPhase, 3000));
}

function showGuessingPhase() {
    document.getElementById('mantriSection').style.display = 'none';
    const sipahi = Object.keys(playerRoles).find(p => playerRoles[p] === 'Sipahi');
    document.getElementById('sipahiName').textContent = `${sipahi}, you are the Sipahi!`;
    const guessContainer = document.getElementById('guessButtons');
    guessContainer.innerHTML = '';
    players.forEach(player => {
        if (player !== sipahi) {
            const btn = document.createElement('button');
            btn.className = 'btn btn-warning m-2';
            btn.textContent = player;
            cleanup.addEventListener(btn, 'click', () => localSubmitGuess(player));
            guessContainer.appendChild(btn);
        }
    });
    document.getElementById('guessSection').style.display = 'block';
}

function localSubmitGuess(guess) {
    document.getElementById('guessSection').style.display = 'none';
    const chor = Object.keys(playerRoles).find(p => playerRoles[p] === 'Chor');
    const sipahi = Object.keys(playerRoles).find(p => playerRoles[p] === 'Sipahi');
    const isCorrect = guess === chor;

    const resultsEl = document.getElementById('results');
    resultsEl.innerHTML = '';

    const title = document.createElement('h4');
    title.textContent = 'Final Scores:';
    resultsEl.appendChild(title);

    const list = document.createElement('ul');
    players.forEach(player => {
        const r = playerRoles[player];
        let score = r === 'Raja' ? 1000 : r === 'Mantri' ? 800
            : r === 'Sipahi' ? (isCorrect ? 500 : 0)
            : (isCorrect ? -500 : 0);

        const li = document.createElement('li');
        const strong = document.createElement('strong');
        strong.textContent = player;
        li.appendChild(strong);
        li.appendChild(document.createTextNode(` (${r}): ${score} pts`));
        list.appendChild(li);
    });
    resultsEl.appendChild(list);

    const sipahiGuess = document.createElement('p');
    sipahiGuess.textContent = `Sipahi guessed: ${guess}`;
    resultsEl.appendChild(sipahiGuess);

    const actualChor = document.createElement('p');
    actualChor.textContent = `Actual Chor: ${chor}`;
    resultsEl.appendChild(actualChor);

    const verdict = document.createElement('p');
    verdict.className = 'lead';
    const verdictStrong = document.createElement('strong');
    verdictStrong.textContent = isCorrect ? 'Correct!' : 'Wrong!';
    verdict.appendChild(verdictStrong);
    resultsEl.appendChild(verdict);

    document.getElementById('resultsSection').style.display = 'block';
}

// ── Network multiplayer ──────────────────────────────────────────────────────
let socket = null;
let netRoomCode = null;
let netPlayerId = null;
let netIsHost = false;
let netMyRole = null;
let netPlayers = [];
let netSipahiId = null;

function initSocket() {
    if (socket) return;
    socket = io();

    cleanup.addSocketListener(socket, 'raja_room_created', data => {
        netRoomCode = data.room_code;
        netPlayerId = data.player_id;
        netIsHost = true;
        netPlayers = data.players;
        showNetWaiting();
    });

    cleanup.addSocketListener(socket, 'raja_room_joined', data => {
        netRoomCode = data.room_code;
        netPlayerId = data.player_id;
        netIsHost = false;
        netPlayers = data.players;
        showNetWaiting();
    });

    cleanup.addSocketListener(socket, 'raja_player_joined', data => {
        netPlayers = data.players;
        renderNetPlayerList();
        if (netIsHost && netPlayers.length === 4) {
            document.getElementById('netStartBtn').style.display = 'inline-block';
            document.getElementById('netWaitMsg').textContent = 'All 4 players ready!';
        }
    });

    cleanup.addSocketListener(socket, 'raja_player_left', data => {
        netPlayers = data.players;
        renderNetPlayerList();
        document.getElementById('netStartBtn').style.display = 'none';
        document.getElementById('netWaitMsg').textContent = 'Waiting for players…';
    });

    cleanup.addSocketListener(socket, 'raja_game_started', data => {
        netMyRole = data.your_role;
        netPlayers = data.players;
        netSipahiId = null;
        showNetRoleReveal(data.your_name, data.your_role);
    });

    cleanup.addSocketListener(socket, 'raja_show_mantri', data => {
        document.getElementById('networkRoleReveal').style.display = 'none';
        document.getElementById('networkMantriReveal').style.display = 'block';
        document.getElementById('netMantriInfo').textContent = `${data.mantri_name} is the Mantri!`;

        const guessDiv = document.getElementById('netGuessButtons');
        guessDiv.innerHTML = '';

        if (netMyRole === 'Sipahi') {
            document.getElementById('netGuessingPrompt').textContent = 'You are the Sipahi — guess who the Chor is:';
            netPlayers.forEach(p => {
                if (p.id !== netPlayerId && p.id !== data.mantri_id) {
                    const btn = document.createElement('button');
                    btn.className = 'btn btn-warning m-1';
                    btn.textContent = p.name;
                    cleanup.addEventListener(btn, 'click', () => netMakeGuess(p.id));
                    guessDiv.appendChild(btn);
                }
            });
        } else {
            document.getElementById('netGuessingPrompt').textContent = 'Waiting for the Sipahi to guess…';
        }
    });

    cleanup.addSocketListener(socket, 'raja_game_result', data => {
        document.getElementById('networkMantriReveal').style.display = 'none';
        document.getElementById('networkResults').style.display = 'block';

        const playerMap = Object.fromEntries(data.players.map(p => [p.id, p.name]));
        let html = `<p><strong>Sipahi guessed:</strong> ${data.guessed_name}</p>`;
        html += `<p><strong>Actual Chor:</strong> ${data.chor_name}</p>`;
        html += `<p class="lead"><strong>${data.is_correct ? 'Correct guess!' : 'Wrong guess!'}</strong></p>`;
        html += '<h5>Scores:</h5><ul>';
        data.players.forEach(p => {
            const role = data.roles[p.id];
            const score = data.scores[p.id];
            const highlight = p.id === netPlayerId ? ' (you)' : '';
            html += `<li><strong>${p.name}</strong>${highlight} — ${role}: ${score} pts</li>`;
        });
        html += '</ul>';
        document.getElementById('netResultsContent').innerHTML = html;
    });

    cleanup.addSocketListener(socket, 'raja_error', data => {
        alert(data.message);
    });
}

function netCreateRoom() {
    const name = document.getElementById('netPlayerName').value.trim();
    if (!name) { alert('Enter your name'); return; }
    initSocket();
    socket.emit('create_raja_room', { player_name: name });
}

function netJoinRoom() {
    const name = document.getElementById('netJoinName').value.trim();
    const code = document.getElementById('netRoomCode').value.trim().toUpperCase();
    if (!name || !code) { alert('Enter your name and room code'); return; }
    initSocket();
    socket.emit('join_raja_room', { player_name: name, room_code: code });
}

function showNetWaiting() {
    document.getElementById('networkLobby').style.display = 'none';
    document.getElementById('networkWaiting').style.display = 'block';
    document.getElementById('netRoomDisplay').textContent = netRoomCode;
    renderNetPlayerList();
    if (netIsHost) {
        document.getElementById('netWaitMsg').textContent = 'Share this code with 3 friends.';
    }
}

function renderNetPlayerList() {
    const list = document.getElementById('netPlayerList');
    list.innerHTML = netPlayers.map((p, i) =>
        `<span class="badge bg-secondary me-2">${p.name}${i === 0 ? ' (Host)' : ''}</span>`
    ).join('');
}

function netStartGame() {
    socket.emit('start_raja_game', { room_code: netRoomCode });
}

function showNetRoleReveal(name, role) {
    document.getElementById('networkWaiting').style.display = 'none';
    document.getElementById('networkRoleReveal').style.display = 'block';
    document.getElementById('netRevealTitle').textContent = `${name}, here is your role:`;
    const icons = { Raja: 'R', Mantri: 'M', Chor: 'C', Sipahi: 'S' };
    document.getElementById('netRoleCard').innerHTML =
        `${icons[role] || ''} <strong>${role}</strong>`;
}

function netRoleRevealed() {
    document.getElementById('networkRoleReveal').style.display = 'none';
    socket.emit('raja_reveal_done', { room_code: netRoomCode });
    // Show a waiting screen until mantri is revealed
    document.getElementById('networkMantriReveal').style.display = 'block';
    document.getElementById('netMantriInfo').textContent = '⏳ Waiting for all players to reveal their roles…';
    document.getElementById('netGuessingPrompt').textContent = '';
    document.getElementById('netGuessButtons').innerHTML = '';
}

function netMakeGuess(guessedId) {
    socket.emit('raja_sipahi_guess', { room_code: netRoomCode, guessed_id: guessedId });
}

// ── DOM wiring (tracked for cleanup) ──────────────────────
document.addEventListener('DOMContentLoaded', () => {
    cleanup.addEventListener(document.getElementById('rm-local-btn'), 'click', showLocalSetup);
    cleanup.addEventListener(document.getElementById('rm-network-btn'), 'click', showNetworkLobby);
    cleanup.addEventListener(document.getElementById('rm-start-local-btn'), 'click', startLocalGame);
    cleanup.addEventListener(document.getElementById('rm-net-create-btn'), 'click', netCreateRoom);
    cleanup.addEventListener(document.getElementById('rm-net-join-btn'), 'click', netJoinRoom);
    cleanup.addEventListener(document.getElementById('netStartBtn'), 'click', netStartGame);
    cleanup.addEventListener(document.getElementById('rm-role-read-btn'), 'click', netRoleRevealed);

    document.querySelectorAll('.rm-back-btn').forEach(btn => {
        cleanup.addEventListener(btn, 'click', showMode);
    });
    document.querySelectorAll('.rm-play-again-btn').forEach(btn => {
        cleanup.addEventListener(btn, 'click', () => location.reload());
    });
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    cleanup.cleanup();
});

console.log('Raja Mantri script loaded with CleanupManager');
