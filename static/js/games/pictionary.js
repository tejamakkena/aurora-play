/* Pictionary client - all listeners/timers routed through CleanupManager */
const cleanup = new CleanupManager();

const socket = io();
let roomCode = null;
let playerId = null;
let isHost = false;
let isDrawing = false;
let currentTool = 'pen';
let currentColor = 'black';
let canvas = null;
let ctx = null;
let drawing = false;
let lastX = 0;
let lastY = 0;
let timerInterval = null;

// Initialize canvas
document.addEventListener('DOMContentLoaded', function() {
    canvas = document.getElementById('drawingCanvas');
    ctx = canvas.getContext('2d');
    ctx.lineWidth = 3;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    // Mouse events
    cleanup.addEventListener(canvas, 'mousedown', startDrawing);
    cleanup.addEventListener(canvas, 'mousemove', draw);
    cleanup.addEventListener(canvas, 'mouseup', stopDrawing);
    cleanup.addEventListener(canvas, 'mouseout', stopDrawing);

    // Touch events for mobile
    cleanup.addEventListener(canvas, 'touchstart', handleTouch);
    cleanup.addEventListener(canvas, 'touchmove', handleTouch);
    cleanup.addEventListener(canvas, 'touchend', stopDrawing);

    // Enter key to submit guess
    cleanup.addEventListener(document.getElementById('guessInput'), 'keypress', function(e) {
        if (e.key === 'Enter') submitGuess();
    });

    // Lobby / control buttons (were inline onclick handlers)
    cleanup.addEventListener(document.getElementById('pict-join-btn'), 'click', joinRoom);
    cleanup.addEventListener(document.getElementById('pict-create-btn'), 'click', createRoom);
    cleanup.addEventListener(document.getElementById('startGameBtn'), 'click', startGame);
    cleanup.addEventListener(document.getElementById('pict-leave-btn'), 'click', leaveRoom);
    cleanup.addEventListener(document.getElementById('tool-pen'), 'click', () => selectTool('pen'));
    cleanup.addEventListener(document.getElementById('tool-eraser'), 'click', () => selectTool('eraser'));
    cleanup.addEventListener(document.getElementById('pict-clear-btn'), 'click', clearCanvas);
    cleanup.addEventListener(document.getElementById('pict-send-btn'), 'click', submitGuess);
    cleanup.addEventListener(document.getElementById('pict-next-turn-btn'), 'click', nextTurn);
    cleanup.addEventListener(document.getElementById('pict-play-again-btn'), 'click', () => location.reload());

    document.querySelectorAll('.color-btn').forEach(btn => {
        cleanup.addEventListener(btn, 'click', () => selectColor(btn.dataset.color, btn));
    });
});

function createRoom() {
    const playerName = document.getElementById('playerName').value.trim() || 'Player';
    socket.emit('create_pictionary_room', {
        player_name: playerName,
        time_limit: 60,
        max_rounds: 3,
        difficulty: 'medium'
    });
}

function joinRoom() {
    const playerName = document.getElementById('playerName').value.trim() || 'Player';
    const code = document.getElementById('roomCodeInput').value.trim().toUpperCase();

    if (!code) {
        alert('Please enter a room code');
        return;
    }

    socket.emit('join_pictionary_room', {
        room_code: code,
        player_name: playerName
    });
}

function startGame() {
    socket.emit('start_pictionary_game', { room_code: roomCode });
}

function leaveRoom() {
    if (roomCode) {
        socket.emit('leave_pictionary_room', { room_code: roomCode });
    }
    location.reload();
}

function selectTool(tool) {
    currentTool = tool;
    document.querySelectorAll('.tool-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.tool === tool);
    });
}

function selectColor(color, btnEl) {
    currentColor = color;
    document.querySelectorAll('.color-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    if (btnEl) {
        btnEl.classList.add('active');
    }
}

function clearCanvas() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    socket.emit('draw_action', {
        room_code: roomCode,
        action: { type: 'clear' }
    });
}

function startDrawing(e) {
    if (!isDrawing) return;
    drawing = true;
    const rect = canvas.getBoundingClientRect();
    lastX = e.clientX - rect.left;
    lastY = e.clientY - rect.top;
}

function draw(e) {
    if (!isDrawing || !drawing) return;

    const rect = canvas.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;

    drawLine(lastX, lastY, x, y);

    socket.emit('draw_action', {
        room_code: roomCode,
        action: {
            type: currentTool,
            fromX: lastX,
            fromY: lastY,
            toX: x,
            toY: y,
            color: currentColor,
            size: document.getElementById('brushSize').value
        }
    });

    lastX = x;
    lastY = y;
}

function stopDrawing() {
    drawing = false;
}

function handleTouch(e) {
    e.preventDefault();
    const touch = e.touches[0];
    const mouseEvent = new MouseEvent(e.type === 'touchstart' ? 'mousedown' :
                                     e.type === 'touchmove' ? 'mousemove' : 'mouseup', {
        clientX: touch.clientX,
        clientY: touch.clientY
    });
    canvas.dispatchEvent(mouseEvent);
}

function drawLine(fromX, fromY, toX, toY) {
    ctx.strokeStyle = currentTool === 'eraser' ? 'white' : currentColor;
    ctx.lineWidth = document.getElementById('brushSize').value;
    ctx.beginPath();
    ctx.moveTo(fromX, fromY);
    ctx.lineTo(toX, toY);
    ctx.stroke();
}

function submitGuess() {
    const guess = document.getElementById('guessInput').value.trim();
    if (!guess) return;

    socket.emit('submit_guess', {
        room_code: roomCode,
        guess: guess
    });

    document.getElementById('guessInput').value = '';
}

function nextTurn() {
    document.getElementById('turnEndModal').classList.remove('active');
    if (isHost) {
        socket.emit('next_turn', { room_code: roomCode });
    }
}

function updatePlayersList(players, gameScreen = false) {
    const listElement = document.getElementById(gameScreen ? 'gamePlayersList' : 'playersList');
    listElement.innerHTML = players.map(p => `
        <div class="player-item ${p.is_drawing ? 'drawing' : ''}">
            <span>${p.name} ${p.is_host ? '(Host)' : ''}</span>
            <span>${gameScreen ? p.score + ' pts' : (p.ready ? 'Ready' : 'Waiting')}</span>
        </div>
    `).join('');
}

function addChatMessage(message, isCorrect = false) {
    const chatMessages = document.getElementById('chatMessages');
    const div = document.createElement('div');
    div.className = 'chat-message' + (isCorrect ? ' correct' : '');
    div.textContent = message;
    chatMessages.appendChild(div);
    chatMessages.scrollTop = chatMessages.scrollHeight;
}

function startTimer(seconds) {
    cleanup.clearInterval(timerInterval);
    let timeLeft = seconds;
    const timerElement = document.getElementById('timer');

    timerInterval = cleanup.addInterval(setInterval(() => {
        timeLeft--;
        timerElement.textContent = timeLeft;

        if (timeLeft <= 10) {
            timerElement.classList.add('warning');
        }

        if (timeLeft <= 0) {
            cleanup.clearInterval(timerInterval);
            if (isDrawing) {
                socket.emit('time_up', { room_code: roomCode });
            }
        }
    }, 1000));
}

// Socket event handlers (tracked for cleanup)
cleanup.addSocketListener(socket, 'pictionary_room_created', function(data) {
    roomCode = data.room_code;
    playerId = data.player_id;
    isHost = true;

    document.getElementById('lobbyScreen').style.display = 'none';
    document.getElementById('waitingRoom').style.display = 'block';
    document.getElementById('waitingRoomCode').textContent = roomCode;
    document.getElementById('startGameBtn').style.display = 'block';

    updatePlayersList(data.players);
});

cleanup.addSocketListener(socket, 'pictionary_room_joined', function(data) {
    roomCode = data.room_code;
    playerId = data.player_id;

    document.getElementById('lobbyScreen').style.display = 'none';
    document.getElementById('waitingRoom').style.display = 'block';
    document.getElementById('waitingRoomCode').textContent = roomCode;

    updatePlayersList(data.players);
});

cleanup.addSocketListener(socket, 'pictionary_player_joined', function(data) {
    updatePlayersList(data.players);
});

cleanup.addSocketListener(socket, 'turn_start_drawer', function(data) {
    isDrawing = true;

    document.getElementById('waitingRoom').style.display = 'none';
    document.getElementById('gameScreen').style.display = 'block';
    document.getElementById('roomInfo').style.display = 'block';
    document.getElementById('roomCode').textContent = roomCode;
    document.getElementById('currentRound').textContent = data.round;
    document.getElementById('maxRounds').textContent = data.max_rounds;

    document.getElementById('roleMessage').textContent = `You are drawing: ${data.word}`;
    document.getElementById('wordDisplay').textContent = data.word;
    document.getElementById('drawingTools').style.display = 'flex';
    document.getElementById('guessInput').disabled = true;

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    startTimer(data.time_limit);
});

cleanup.addSocketListener(socket, 'turn_start_guesser', function(data) {
    isDrawing = false;

    document.getElementById('waitingRoom').style.display = 'none';
    document.getElementById('gameScreen').style.display = 'block';
    document.getElementById('roomInfo').style.display = 'block';
    document.getElementById('roomCode').textContent = roomCode;
    document.getElementById('currentRound').textContent = data.round;
    document.getElementById('maxRounds').textContent = data.max_rounds;

    document.getElementById('roleMessage').textContent = `${data.drawer_name} is drawing!`;
    document.getElementById('wordDisplay').textContent = data.word_hint;
    document.getElementById('drawingTools').style.display = 'none';
    document.getElementById('guessInput').disabled = false;

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    startTimer(data.time_limit);
});

cleanup.addSocketListener(socket, 'drawing_update', function(data) {
    const action = data.action;

    if (action.type === 'clear') {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
    } else {
        ctx.strokeStyle = action.type === 'eraser' ? 'white' : action.color;
        ctx.lineWidth = action.size;
        ctx.beginPath();
        ctx.moveTo(action.fromX, action.fromY);
        ctx.lineTo(action.toX, action.toY);
        ctx.stroke();
    }
});

cleanup.addSocketListener(socket, 'player_guessed', function(data) {
    addChatMessage(`${data.player_name}: ${data.guess}`);
});

cleanup.addSocketListener(socket, 'correct_guess', function(data) {
    addChatMessage(`${data.player_name} guessed correctly! +${data.points} points`, true);
    updatePlayersList(data.players, true);
});

cleanup.addSocketListener(socket, 'turn_end', function(data) {
    cleanup.clearInterval(timerInterval);
    document.getElementById('revealedWord').textContent = data.word;
    document.getElementById('turnScores').innerHTML = data.players
        .sort((a, b) => b.score - a.score)
        .map(p => `<p>${p.name}: ${p.score} points</p>`)
        .join('');
    document.getElementById('turnEndModal').classList.add('active');

    updatePlayersList(data.players, true);
});

cleanup.addSocketListener(socket, 'game_over', function(data) {
    cleanup.clearInterval(timerInterval);
    document.getElementById('finalScores').innerHTML = data.final_results
        .map(r => `<p>${r.rank}. ${r.name}: ${r.score} points</p>`)
        .join('');
    document.getElementById('gameOverModal').classList.add('active');
});

cleanup.addSocketListener(socket, 'pictionary_error', function(data) {
    alert(data.message);
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    cleanup.cleanup();
});

console.log('Pictionary script loaded with CleanupManager');
