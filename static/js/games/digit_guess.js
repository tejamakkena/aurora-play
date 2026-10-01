console.log('Digit Guess script loading...');
console.log('User:', window.user);

// Initialize CleanupManager for proper resource cleanup
const cleanup = new CleanupManager();

// Socket connection
const socket = io('/digit_guess');

// Game state
let gameState = {
    roomCode: null,
    players: [],
    isHost: false,
    myPlayerId: null,
    currentTurn: null,
    mySecretNumber: null,
    gameStarted: false,
    gameOver: false,
    guessHistory: {}
};

// DOM elements
const sections = {
    modeSelection: document.getElementById('mode-selection'),
    joinRoom: document.getElementById('join-room-section'),
    waitingRoom: document.getElementById('waiting-room'),
    setNumber: document.getElementById('set-number-section'),
    gameScreen: document.getElementById('game-screen'),
    gameOver: document.getElementById('game-over-section')
};

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    console.log('DOM loaded, initializing Digit Guess...');
    initializeEventListeners();
});

function initializeEventListeners() {
    // Mode selection - use cleanup manager
    cleanup.addEventListener(document.getElementById('create-room-btn'), 'click', createRoom);
    cleanup.addEventListener(document.getElementById('join-room-btn-start'), 'click', showJoinRoom);
    
    // Join room
    cleanup.addEventListener(document.getElementById('back-to-mode-btn'), 'click', backToMode);
    cleanup.addEventListener(document.getElementById('join-room-submit-btn'), 'click', joinRoom);
    cleanup.addEventListener(document.getElementById('room-code-input'), 'keypress', (e) => {
        if (e.key === 'Enter') joinRoom();
    });
    
    // Waiting room
    cleanup.addEventListener(document.getElementById('copy-code-btn'), 'click', copyRoomCode);
    cleanup.addEventListener(document.getElementById('start-game-btn'), 'click', startGame);
    cleanup.addEventListener(document.getElementById('leave-room-btn'), 'click', leaveRoom);
    
    // Set secret number
    cleanup.addEventListener(document.getElementById('submit-secret-btn'), 'click', submitSecretNumber);
    cleanup.addEventListener(document.getElementById('secret-number-input'), 'keypress', (e) => {
        if (e.key === 'Enter') submitSecretNumber();
    });
    
    // Game
    cleanup.addEventListener(document.getElementById('submit-guess-btn'), 'click', submitGuess);
    cleanup.addEventListener(document.getElementById('guess-input'), 'keypress', (e) => {
        if (e.key === 'Enter') submitGuess();
    });
    cleanup.addEventListener(document.getElementById('leave-game-btn'), 'click', leaveGame);
    
    // Game over
    cleanup.addEventListener(document.getElementById('play-again-btn'), 'click', playAgain);
    cleanup.addEventListener(document.getElementById('exit-game-btn'), 'click', exitToMenu);
    
    // Socket listeners
    setupSocketListeners();
}

function setupSocketListeners() {
    // Use cleanup manager for socket handlers
    cleanup.addSocketListener(socket, 'connect', () => {
        console.log('Socket connected:', socket.id);
        gameState.myPlayerId = socket.id;
    });

    cleanup.addSocketListener(socket, 'room_created', (data) => {
        console.log('Room created:', data);
        gameState.roomCode = data.room_code;
        gameState.players = data.players || [];
        gameState.isHost = true;
        gameState.myPlayerId = data.player_id;
        showWaitingRoom();
        updatePlayersList();
    });

    cleanup.addSocketListener(socket, 'room_joined', (data) => {
        console.log('Room joined:', data);
        gameState.roomCode = data.room_code;
        gameState.players = data.players;
        gameState.isHost = data.is_host;
        gameState.myPlayerId = data.player_id;
        showWaitingRoom();
        updatePlayersList();
    });

    cleanup.addSocketListener(socket, 'player_joined', (data) => {
        console.log('Player joined:', data);
        gameState.players = data.players;
        updatePlayersList();
    });

    cleanup.addSocketListener(socket, 'player_left', (data) => {
        console.log('Player left:', data);
        gameState.players = data.players;
        updatePlayersList();
        
        if (gameState.gameStarted && !gameState.gameOver) {
            showMessage('Opponent left the game!');
            const timeout = cleanup.addTimeout(setTimeout(() => exitToMenu(), 2000));
        }
    });

    cleanup.addSocketListener(socket, 'game_started', (data) => {
        console.log('Game started:', data);
        gameState.gameStarted = true;
        showSetNumberSection();
    });

    cleanup.addSocketListener(socket, 'number_set', (data) => {
        console.log('Number set:', data);
        if (data.all_ready) {
            // Both players ready, will receive guessing_phase_started
        } else {
            // Show waiting message
            document.getElementById('secret-number-input').disabled = true;
            document.getElementById('submit-secret-btn').disabled = true;
            document.getElementById('waiting-opponent-msg').style.display = 'block';
        }
    });

    cleanup.addSocketListener(socket, 'guessing_phase_started', (data) => {
        console.log('Guessing phase started:', data);
        gameState.currentTurn = data.current_turn;
        gameState.players = data.players;
        showGameScreen();
        updateTurnIndicator();
    });

    cleanup.addSocketListener(socket, 'guess_made', (data) => {
        console.log('Guess made:', data);
        gameState.currentTurn = data.current_turn;
        gameState.guessHistory = data.guess_history;
        updateGuessHistory();
        updateTurnIndicator();
        
        // Clear input if it was my turn
        if (data.player_id === gameState.myPlayerId) {
            document.getElementById('guess-input').value = '';
        }
    });

    cleanup.addSocketListener(socket, 'game_over', (data) => {
        console.log('Game over:', data);
        gameState.gameOver = true;
        showGameOver(data);
    });

    cleanup.addSocketListener(socket, 'error', (data) => {
        console.error('Error:', data.message);
        showMessage(data.message);
    });
}

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    console.log('Digit Guess: Cleaning up resources...');
    cleanup.cleanup();
    if (gameState.roomCode && socket.connected) {
        socket.emit('leave_room', { room_code: gameState.roomCode });
    }
    socket.disconnect();
});

console.log('✅ Digit Guess script loaded with CleanupManager');

// UI Functions
function showSection(section) {
    Object.values(sections).forEach(s => s.classList.add('hidden'));
    section.classList.remove('hidden');
}

function showMessage(message) {
    const toast = document.getElementById('message-toast');
    toast.textContent = message;
    toast.classList.add('show');
    setTimeout(() => {
        toast.classList.remove('show');
    }, 3000);
}

function createRoom() {
    console.log('Creating room...');
    const playerName = window.user?.name || 'Player 1';
    socket.emit('create_room', {
        game_type: 'digit_guess',
        player_name: playerName
    });
}

function showJoinRoom() {
    showSection(sections.joinRoom);
    document.getElementById('room-code-input').focus();
}

function backToMode() {
    showSection(sections.modeSelection);
    document.getElementById('room-code-input').value = '';
}

function joinRoom() {
    const roomCode = document.getElementById('room-code-input').value.trim().toUpperCase();
    if (roomCode.length !== 6) {
        showMessage('Room code must be 6 characters');
        return;
    }
    
    const playerName = window.user?.name || 'Player 2';
    socket.emit('join_room', {
        game_type: 'digit_guess',
        room_code: roomCode,
        player_name: playerName
    });
}

function showWaitingRoom() {
    showSection(sections.waitingRoom);
    document.getElementById('display-room-code').textContent = gameState.roomCode;
    
    // Show/hide start button based on host status
    const startBtn = document.getElementById('start-game-btn');
    startBtn.style.display = gameState.isHost ? 'inline-block' : 'none';
}

function updatePlayersList() {
    const container = document.getElementById('players-list-container');
    container.innerHTML = '';
    
    gameState.players.forEach(player => {
        const playerDiv = document.createElement('div');
        playerDiv.className = 'player-item';
        
        const nameSpan = document.createElement('span');
        nameSpan.textContent = player.name;
        if (player.is_host) {
            nameSpan.textContent += ' (Host)';
        }
        
        const statusSpan = document.createElement('span');
        statusSpan.className = `player-status ${player.ready ? 'ready' : 'not-ready'}`;
        
        playerDiv.appendChild(nameSpan);
        playerDiv.appendChild(statusSpan);
        container.appendChild(playerDiv);
    });
}

function copyRoomCode() {
    const code = gameState.roomCode;
    navigator.clipboard.writeText(code).then(() => {
        showMessage('Room code copied!');
    }).catch(() => {
        showMessage('Failed to copy code');
    });
}

function startGame() {
    if (gameState.players.length !== 2) {
        showMessage('Need exactly 2 players to start!');
        return;
    }
    
    socket.emit('start_game', {
        room_code: gameState.roomCode
    });
}

function leaveRoom() {
    socket.emit('leave_room', {
        room_code: gameState.roomCode
    });
    resetGame();
    showSection(sections.modeSelection);
}

function showSetNumberSection() {
    showSection(sections.setNumber);
    document.getElementById('secret-number-input').value = '';
    document.getElementById('secret-number-input').disabled = false;
    document.getElementById('submit-secret-btn').disabled = false;
    document.getElementById('waiting-opponent-msg').style.display = 'none';
    document.getElementById('secret-number-input').focus();
}

function submitSecretNumber() {
    const input = document.getElementById('secret-number-input');
    const number = input.value.trim();
    
    if (number.length !== 4 || !/^\d{4}$/.test(number)) {
        showMessage('Please enter exactly 4 digits');
        return;
    }
    
    gameState.mySecretNumber = number;
    
    socket.emit('set_secret_number', {
        room_code: gameState.roomCode,
        secret_number: number
    });
}

function showGameScreen() {
    showSection(sections.gameScreen);
    updateGuessHistory();
    updateTurnIndicator();
    document.getElementById('guess-input').value = '';
}

function updateTurnIndicator() {
    const indicator = document.getElementById('turn-indicator');
    const isMyTurn = gameState.currentTurn === gameState.myPlayerId;
    
    if (isMyTurn) {
        indicator.textContent = 'Your Turn - Make a Guess!';
        indicator.style.borderColor = '#00ff88';
        document.getElementById('guess-input').disabled = false;
        document.getElementById('submit-guess-btn').disabled = false;
    } else {
        const opponentName = gameState.players.find(p => p.id === gameState.currentTurn)?.name || 'Opponent';
        indicator.textContent = `⏳ ${opponentName}'s Turn`;
        indicator.style.borderColor = '#ff6b6b';
        document.getElementById('guess-input').disabled = true;
        document.getElementById('submit-guess-btn').disabled = true;
    }
}

function updateGuessHistory() {
    const container = document.getElementById('guess-history-container');
    container.innerHTML = '';
    
    // Combine and sort all guesses by timestamp (we'll use index as proxy)
    const allGuesses = [];
    
    for (const playerId in gameState.guessHistory) {
        const player = gameState.players.find(p => p.id === playerId);
        const playerName = player?.name || 'Player';
        const isMine = playerId === gameState.myPlayerId;
        
        gameState.guessHistory[playerId].forEach((guessData, index) => {
            allGuesses.push({
                playerName,
                isMine,
                guess: guessData.guess,
                feedback: guessData.feedback,
                index
            });
        });
    }
    
    if (allGuesses.length === 0) {
        container.innerHTML = '<p style="color: #aaa; text-align: center;">No guesses yet</p>';
        return;
    }
    
    // Display most recent first
    allGuesses.reverse();
    
    allGuesses.forEach(item => {
        const guessDiv = document.createElement('div');
        guessDiv.className = `guess-item ${item.isMine ? 'my-guess' : 'opponent-guess'}`;
        
        guessDiv.innerHTML = `
            <div style="display: flex; justify-content: space-between; align-items: center;">
                <span style="font-weight: 600;">${item.playerName}</span>
                <span class="guess-number">${item.guess}</span>
            </div>
            <div class="guess-feedback">
                <span class="feedback-stat">${item.feedback.correct_positions} in position</span>
                <span class="feedback-stat">✓ ${item.feedback.correct_digits} total correct</span>
            </div>
        `;
        
        container.appendChild(guessDiv);
    });
}

function submitGuess() {
    const input = document.getElementById('guess-input');
    const guess = input.value.trim();
    
    if (guess.length !== 4 || !/^\d{4}$/.test(guess)) {
        showMessage('Please enter exactly 4 digits');
        return;
    }
    
    if (gameState.currentTurn !== gameState.myPlayerId) {
        showMessage('Not your turn!');
        return;
    }
    
    socket.emit('make_guess', {
        room_code: gameState.roomCode,
        guess: guess
    });
}

function leaveGame() {
    if (confirm('Are you sure you want to leave the game?')) {
        socket.emit('leave_room', {
            room_code: gameState.roomCode
        });
        resetGame();
        showSection(sections.modeSelection);
    }
}

function showGameOver(data) {
    showSection(sections.gameOver);
    
    const isWinner = data.winner_id === gameState.myPlayerId;
    
    document.getElementById('game-over-title').textContent = isWinner ? 'You Win!' : 'Game Over';
    document.getElementById('winner-announcement').textContent = 
        isWinner ? 'Congratulations! You cracked the code!' : `${data.winner_name} wins!`;
    
    // Show secret numbers
    const secretsContainer = document.getElementById('secrets-container');
    secretsContainer.innerHTML = '';
    
    gameState.players.forEach(player => {
        const secretDiv = document.createElement('div');
        secretDiv.style.margin = '15px 0';
        
        const isMine = player.id === gameState.myPlayerId;
        secretDiv.innerHTML = `
            <div style="color: ${isMine ? '#00ff88' : '#ff6b6b'}; font-weight: 600;">
                ${player.name}${isMine ? ' (You)' : ''}:
            </div>
            <div class="secret-number-display">${data.secret_numbers[player.id]}</div>
        `;
        
        secretsContainer.appendChild(secretDiv);
    });
}

function playAgain() {
    socket.emit('leave_room', {
        room_code: gameState.roomCode
    });
    resetGame();
    showSection(sections.modeSelection);
}

function exitToMenu() {
    if (!gameState.gameOver) {
        socket.emit('leave_room', {
            room_code: gameState.roomCode
        });
    }
    resetGame();
    showSection(sections.modeSelection);
}

function resetGame() {
    gameState = {
        roomCode: null,
        players: [],
        isHost: false,
        myPlayerId: socket.id,
        currentTurn: null,
        mySecretNumber: null,
        gameStarted: false,
        gameOver: false,
        guessHistory: {}
    };
}

console.log('Digit Guess script loaded successfully');
