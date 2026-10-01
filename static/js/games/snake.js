console.log('=== SNAKE-LADDER.JS FILE START ===');

// Check Socket.IO
if (typeof io === 'undefined') {
    console.error('❌ Socket.IO NOT loaded!');
    alert('Socket.IO failed to load. Please refresh.');
} else {
    console.log('✅ Socket.IO loaded');
    var socket = io();
}

// Initialize CleanupManager for proper resource cleanup
const cleanup = new CleanupManager();

// Game Configuration
const BOARD_SIZE = 100;
const SNAKES = {
    99: 5, 95: 24, 92: 51, 87: 13, 85: 17, 80: 40,
    73: 28, 69: 33, 64: 16, 62: 18, 54: 31, 48: 9,
    36: 6, 32: 10
};

const LADDERS = {
    4: 56, 12: 50, 14: 55, 22: 58, 41: 79, 54: 88,
    63: 81, 70: 90, 78: 98
};

// Game State
let gameState = {
    mode: null,
    roomCode: null,
    isHost: false,
    players: [],
    currentPlayer: 0,
    myPlayerId: null,
    aiCount: 1,
    aiDifficulty: 'easy',
    playerPositions: {},
    gameActive: false,
    lastDiceRoll: null
};

// Player colors
const PLAYER_COLORS = ['#00f5ff', '#ff6b6b', '#4ecdc4', '#ffe66d', '#a8e6cf', '#ff8b94'];

// DOM Elements
let modeSelection, soloSetup, multiplayerLobby, waitingRoom, gameScreen, resultsScreen;

// Wait for DOM
if (document.readyState === 'loading') {
    console.log('⏳ Waiting for DOM...');
    cleanup.addEventListener(document, 'DOMContentLoaded', init);
} else {
    console.log('✅ DOM ready, initializing...');
    init();
}

function init() {
    console.log('=== INIT FUNCTION CALLED ===');
    
    // Get all screen elements
    modeSelection = document.getElementById('mode-selection');
    soloSetup = document.getElementById('solo-setup');
    multiplayerLobby = document.getElementById('multiplayer-lobby');
    waitingRoom = document.getElementById('waiting-room');
    gameScreen = document.getElementById('game-screen');
    resultsScreen = document.getElementById('results-screen');
    
    console.log('Screen elements:', {
        modeSelection: !!modeSelection,
        soloSetup: !!soloSetup,
        multiplayerLobby: !!multiplayerLobby,
        waitingRoom: !!waitingRoom,
        gameScreen: !!gameScreen,
        resultsScreen: !!resultsScreen
    });
    
    // Initialize all event listeners
    initializeModeSelection();
    initializeSoloSetup();
    initializeMultiplayerLobby();
    initializeGameControls();
    
    // Generate the board
    generateBoard();
    
    // Initialize Socket.IO events
    initializeSocketEvents();
    
    console.log('=== INIT COMPLETE ===');
}

function initializeModeSelection() {
    console.log('🎮 Initializing mode selection...');
    
    const soloBtn = document.getElementById('solo-mode-btn');
    const multiBtn = document.getElementById('multiplayer-mode-btn');
    
    if (soloBtn) {
        console.log('✅ Adding solo button listener');
        cleanup.addEventListener(soloBtn, 'click', function(e) {
            console.log('🤖 SOLO BUTTON CLICKED!');
            e.preventDefault();
            gameState.mode = 'solo';
            if (modeSelection) modeSelection.style.display = 'none';
            if (soloSetup) soloSetup.style.display = 'block';
        });
    }
    
    if (multiBtn) {
        console.log('✅ Adding multiplayer button listener');
        cleanup.addEventListener(multiBtn, 'click', function(e) {
            console.log('👥 MULTIPLAYER BUTTON CLICKED!');
            e.preventDefault();
            gameState.mode = 'multiplayer';
            if (modeSelection) modeSelection.style.display = 'none';
            if (multiplayerLobby) multiplayerLobby.style.display = 'block';
            loadRooms();
        });
    }
}

function initializeSoloSetup() {
    console.log('🤖 Initializing solo setup...');
    
    // AI Count buttons
    document.querySelectorAll('.count-btn').forEach(btn => {
        cleanup.addEventListener(btn, 'click', function(e) {
            e.stopPropagation();
            console.log('AI count selected:', this.dataset.count);
            document.querySelectorAll('.count-btn').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            gameState.aiCount = parseInt(this.dataset.count);
        });
    });
    
    // Difficulty buttons
    document.querySelectorAll('.diff-btn').forEach(btn => {
        cleanup.addEventListener(btn, 'click', function(e) {
            e.stopPropagation();
            console.log('Difficulty selected:', this.dataset.diff);
            document.querySelectorAll('.diff-btn').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            gameState.aiDifficulty = this.dataset.diff;
        });
    });
    
    // Start solo game button
    const startSoloBtn = document.getElementById('start-solo-btn');
    if (startSoloBtn) {
        console.log('✅ Adding start solo button listener');
        cleanup.addEventListener(startSoloBtn, 'click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            console.log('🎮 START SOLO GAME CLICKED!');
            startSoloGame();
        });
    }
    
    // Back button
    const backFromSolo = document.getElementById('back-from-solo-btn');
    if (backFromSolo) {
        cleanup.addEventListener(backFromSolo, 'click', function() {
            console.log('⬅️ Back from solo');
            if (soloSetup) soloSetup.style.display = 'none';
            if (modeSelection) modeSelection.style.display = 'block';
        });
    }
}

function initializeMultiplayerLobby() {
    console.log('👥 Initializing multiplayer lobby...');
    
    const createRoomBtn = document.getElementById('create-room-btn');
    const joinRoomBtn = document.getElementById('join-room-btn');
    const refreshRoomsBtn = document.getElementById('refresh-rooms-btn');
    const backFromLobby = document.getElementById('back-from-lobby-btn');
    const leaveRoomBtn = document.getElementById('leave-room-btn');
    const startMultiplayerBtn = document.getElementById('start-multiplayer-btn');
    const copyRoomCodeBtn = document.getElementById('copy-room-code-btn');
    
    if (createRoomBtn) {
        cleanup.addEventListener(createRoomBtn, 'click', createRoom);
    }
    
    if (joinRoomBtn) {
        cleanup.addEventListener(joinRoomBtn, 'click', joinRoom);
    }
    
    if (refreshRoomsBtn) {
        cleanup.addEventListener(refreshRoomsBtn, 'click', loadRooms);
    }
    
    if (backFromLobby) {
        cleanup.addEventListener(backFromLobby, 'click', function() {
            console.log('⬅️ Back from lobby');
            if (multiplayerLobby) multiplayerLobby.style.display = 'none';
            if (modeSelection) modeSelection.style.display = 'block';
        });
    }
    
    if (leaveRoomBtn) {
        cleanup.addEventListener(leaveRoomBtn, 'click', leaveRoom);
    }
    
    if (startMultiplayerBtn) {
        cleanup.addEventListener(startMultiplayerBtn, 'click', startMultiplayerGame);
    }
    
    if (copyRoomCodeBtn) {
        cleanup.addEventListener(copyRoomCodeBtn, 'click', copyRoomCode);
    }
}

function initializeGameControls() {
    console.log('🎲 Initializing game controls...');
    
    const rollDiceBtn = document.getElementById('roll-dice-btn');
    if (rollDiceBtn) {
        cleanup.addEventListener(rollDiceBtn, 'click', rollDice);
    }
    
    const playAgainBtn = document.getElementById('play-again-btn');
    if (playAgainBtn) {
        cleanup.addEventListener(playAgainBtn, 'click', playAgain);
    }
    
    const newGameBtn = document.getElementById('new-game-btn');
    if (newGameBtn) {
        cleanup.addEventListener(newGameBtn, 'click', newGame);
    }
}

function getUserName() {
    console.log('🔍 Getting user name...');
    
    // Method 1: Try to get from data-user attribute (set by base.html)
    const bodyElement = document.querySelector('body[data-user]');
    if (bodyElement && bodyElement.dataset.user) {
        try {
            const user = JSON.parse(bodyElement.dataset.user);
            console.log('✅ User from session:', user);
            
            const name = user.first_name || user.name || user.email?.split('@')[0];
            if (name) {
                console.log('✅ Using name:', name);
                return name;
            }
        } catch (e) {
            console.error('❌ Error parsing user data:', e);
        }
    }
    
    // Method 2: Check localStorage
    let name = localStorage.getItem('playerName');
    if (name) {
        console.log('✅ Name from localStorage:', name);
        return name;
    }
    
    // Method 3: Prompt user for name
    name = prompt('Enter your name:');
    if (name && name.trim()) {
        name = name.trim();
        localStorage.setItem('playerName', name);
        console.log('✅ Name from prompt:', name);
        return name;
    }
    
    // Fallback
    const fallbackName = 'Player_' + Math.floor(Math.random() * 1000);
    console.log('⚠️ Using fallback name:', fallbackName);
    return fallbackName;
}

function startSoloGame() {
    console.log('🎮 Starting solo game...');
    console.log('AI Count:', gameState.aiCount);
    console.log('AI Difficulty:', gameState.aiDifficulty);
    
    const playerName = getUserName();
    console.log('Player name:', playerName);
    
    // Initialize players
    gameState.players = [
        { id: 0, name: playerName, position: 0, color: PLAYER_COLORS[0], isAI: false }
    ];
    
    // Add AI players
    for (let i = 0; i < gameState.aiCount; i++) {
        gameState.players.push({
            id: i + 1,
            name: `AI ${i + 1}`,
            position: 0,
            color: PLAYER_COLORS[i + 1],
            isAI: true
        });
    }
    
    gameState.myPlayerId = 0;
    gameState.currentPlayer = 0;
    gameState.gameActive = true;
    
    // Initialize positions
    gameState.playerPositions = {};
    gameState.players.forEach(player => {
        gameState.playerPositions[player.id] = 0;
    });
    
    console.log('Players:', gameState.players);
    
    // Hide solo setup, show game screen
    if (soloSetup) soloSetup.style.display = 'none';
    if (gameScreen) gameScreen.style.display = 'block';
    
    // Update room code display
    const roomCodeGame = document.getElementById('room-code-game');
    if (roomCodeGame) roomCodeGame.textContent = 'SOLO';
    
    // Initialize game UI
    updatePlayersPanel();
    updateBoard();
    updateTurnDisplay();
    enableDice();
    
    console.log('✅ Solo game started!');
}

function generateBoard() {
    console.log('🎲 Generating board...');
    const board = document.getElementById('game-board');
    if (!board) {
        console.error('❌ Game board element not found!');
        return;
    }
    
    board.innerHTML = '';
    let cellNumber = 100;
    
    for (let row = 0; row < 10; row++) {
        for (let col = 0; col < 10; col++) {
            const cell = document.createElement('div');
            cell.className = 'board-cell';
            cell.dataset.position = cellNumber;
            
            const actualCol = row % 2 === 0 ? 9 - col : col;
            cell.style.gridColumn = actualCol + 1;
            cell.style.gridRow = row + 1;
            
            const cellContent = document.createElement('div');
            cellContent.className = 'cell-content';
            
            if (SNAKES[cellNumber]) {
                cell.classList.add('snake-cell');
                cellContent.innerHTML = `<div class="cell-number">${cellNumber}</div><div class="snake-icon">S</div>`;
            } else if (LADDERS[cellNumber]) {
                cell.classList.add('ladder-cell');
                cellContent.innerHTML = `<div class="cell-number">${cellNumber}</div><div class="ladder-icon">L</div>`;
            } else {
                cellContent.innerHTML = `<div class="cell-number">${cellNumber}</div>`;
            }
            
            const piecesContainer = document.createElement('div');
            piecesContainer.className = 'pieces-container';
            piecesContainer.id = `pieces-${cellNumber}`;
            
            cell.appendChild(cellContent);
            cell.appendChild(piecesContainer);
            board.appendChild(cell);
            
            cellNumber--;
        }
    }
    console.log('✅ Board generated');
}

function updatePlayersPanel() {
    const playersInfo = document.getElementById('players-info');
    if (!playersInfo) return;
    
    playersInfo.innerHTML = gameState.players.map(player => `
        <div class="player-card ${player.id === gameState.currentPlayer ? 'active' : ''}" data-player="${player.id}">
            <div class="player-piece" style="background: ${player.color};">
                <span class="player-initial">${player.name[0]}</span>
            </div>
            <div class="player-details">
                <div class="player-name">
                    ${player.name} 
                    ${player.id === gameState.currentPlayer ? '(turn)' : ''}
                </div>
                <div class="player-position">
                    Position: <span id="pos-${player.id}" style="color: ${player.color}; font-weight: bold; font-size: 1.2em;">0</span>
                </div>
            </div>
        </div>
    `).join('');
}

function updateBoard() {
    // Clear all pieces
    document.querySelectorAll('.pieces-container').forEach(container => {
        container.innerHTML = '';
    });
    
    // Place players on board
    gameState.players.forEach(player => {
        const position = gameState.playerPositions[player.id];
        const container = document.getElementById(`pieces-${position}`);
        
        if (container) {
            const piece = document.createElement('div');
            piece.className = 'player-piece-small';
            piece.style.background = player.color;
            piece.textContent = player.name[0];
            container.appendChild(piece);
        }
        
        const posDisplay = document.getElementById(`pos-${player.id}`);
        if (posDisplay) {
            posDisplay.textContent = position;
        }
    });
    
    updatePlayersPanel();
}

function updateTurnDisplay() {
    const currentPlayer = gameState.players[gameState.currentPlayer];
    const turnDisplay = document.getElementById('current-turn-display');
    if (turnDisplay) {
        turnDisplay.textContent = currentPlayer.name;
    }
}

function enableDice() {
    const diceBtn = document.getElementById('roll-dice-btn');
    if (diceBtn) {
        diceBtn.disabled = false;
        diceBtn.style.opacity = '1';
    }
}

function disableDice() {
    const diceBtn = document.getElementById('roll-dice-btn');
    if (diceBtn) {
        diceBtn.disabled = true;
        diceBtn.style.opacity = '0.5';
    }
}

function rollDice() {
    console.log('🎲 Rolling dice...');
    
    // Multiplayer mode - send to server
    if (gameState.mode === 'multiplayer') {
        if (gameState.currentPlayer !== gameState.myPlayerId) {
            showMessage('Not your turn!');
            return;
        }
        
        const diceBtn = document.getElementById('roll-dice-btn');
        diceBtn.disabled = true;
        
        const roll = Math.floor(Math.random() * 6) + 1;
        
        if (socket) {
            socket.emit('snake_roll_dice', {
                room_code: gameState.roomCode,
                roll: roll
            });
        }
        
        animateDice(roll);
        return;
    }
    
    // Solo mode
    const diceBtn = document.getElementById('roll-dice-btn');
    diceBtn.disabled = true;
    
    const finalRoll = Math.floor(Math.random() * 6) + 1;
    animateDice(finalRoll, () => {
        gameState.lastDiceRoll = finalRoll;
        movePlayer(gameState.currentPlayer, finalRoll);
    });
}

function animateDice(finalRoll, callback) {
    const diceDisplay = document.getElementById('dice-display');
    const diceResult = document.getElementById('dice-result');
    
    let rollCount = 0;
    const rollInterval = setInterval(() => {
        const randomFace = Math.floor(Math.random() * 6) + 1;
        diceDisplay.innerHTML = `<div class="dice-face rolling">${getDiceFace(randomFace)}</div>`;
        rollCount++;
        
        if (rollCount > 10) {
            clearInterval(rollInterval);
            diceDisplay.innerHTML = `<div class="dice-face">${getDiceFace(finalRoll)}</div>`;
            if (diceResult) diceResult.textContent = `Rolled: ${finalRoll}`;
            
            if (callback) {
                setTimeout(callback, 500);
            }
        }
    }, 100);
}

function getDiceFace(number) {
    const faces = ['1', '2', '3', '4', '5', '6'];
    return faces[number - 1];
}

function movePlayer(playerId, steps) {
    console.log(`Moving player ${playerId} by ${steps} steps`);
    const currentPos = gameState.playerPositions[playerId];
    let newPos = currentPos + steps;
    
    if (newPos > 100) {
        newPos = currentPos;
        showMessage('Too high! Stay in position.');
    }
    
    gameState.playerPositions[playerId] = newPos;
    updateBoard();
    
    if (SNAKES[newPos]) {
        setTimeout(() => {
            showMessage(`Snake! Going down to ${SNAKES[newPos]}`);
            gameState.playerPositions[playerId] = SNAKES[newPos];
            updateBoard();
            checkWinner(playerId);
        }, 1000);
    } else if (LADDERS[newPos]) {
        setTimeout(() => {
            showMessage(`Ladder! Climbing up to ${LADDERS[newPos]}`);
            gameState.playerPositions[playerId] = LADDERS[newPos];
            updateBoard();
            checkWinner(playerId);
        }, 1000);
    } else {
        checkWinner(playerId);
    }
}

function checkWinner(playerId) {
    const position = gameState.playerPositions[playerId];
    
    if (position === 100) {
        gameState.gameActive = false;
        const winner = gameState.players.find(p => p.id === playerId);
        
        setTimeout(() => {
            showResults({ winner: winner.name, players: gameState.players });
        }, 1500);
    } else {
        setTimeout(() => {
            nextTurn();
        }, 1500);
    }
}

function nextTurn() {
    gameState.currentPlayer = (gameState.currentPlayer + 1) % gameState.players.length;
    updateTurnDisplay();
    
    const currentPlayer = gameState.players[gameState.currentPlayer];
    
    if (gameState.mode === 'solo' && currentPlayer.isAI) {
        disableDice();
        showMessage('AI is thinking...');
        setTimeout(() => {
            rollDice();
        }, 1500);
    } else if (gameState.mode === 'multiplayer') {
        if (currentPlayer.id === gameState.myPlayerId) {
            enableDice();
            showMessage('Your turn! Roll the dice.');
        } else {
            disableDice();
            showMessage(`Waiting for ${currentPlayer.name}...`);
        }
    } else {
        enableDice();
        showMessage('Your turn! Roll the dice.');
    }
}

function showMessage(msg) {
    const diceResult = document.getElementById('dice-result');
    if (diceResult) {
        diceResult.textContent = msg;
    }
}

function showResults(data) {
    console.log('🏆 Game over!', data);
    
    if (gameScreen) gameScreen.style.display = 'none';
    if (resultsScreen) resultsScreen.style.display = 'block';
    
    const resultIcon = document.getElementById('result-icon');
    const resultTitle = document.getElementById('result-title');
    const resultMessage = document.getElementById('result-message');
    const rankingsList = document.getElementById('final-rankings-list');
    
    const sortedPlayers = [...gameState.players].sort((a, b) => {
        return gameState.playerPositions[b.id] - gameState.playerPositions[a.id];
    });
    
    if (rankingsList) {
        rankingsList.innerHTML = sortedPlayers.map((player, index) => {
            let medal = '';
            if (index === 0) medal = '1st';
            else if (index === 1) medal = '2nd';
            else if (index === 2) medal = '3rd';
            
            return `
                <div class="ranking-item ${index === 0 ? 'winner' : ''}">
                    <span class="rank">${medal || (index + 1)}</span>
                    <div class="player-piece-small" style="background: ${player.color};">${player.name[0]}</div>
                    <span class="player-name">${player.name}</span>
                    <span class="final-position">Position: ${gameState.playerPositions[player.id]}</span>
                </div>
            `;
        }).join('');
    }
    
    if (sortedPlayers[0].id === gameState.myPlayerId) {
        if (resultIcon) resultIcon.textContent = '';
        if (resultTitle) resultTitle.textContent = 'You Won!';
        if (resultMessage) resultMessage.textContent = 'Congratulations! You reached 100 first!';
    } else {
        if (resultIcon) resultIcon.textContent = '';
        if (resultTitle) resultTitle.textContent = 'Game Over!';
        if (resultMessage) resultMessage.textContent = `${data.winner} won the game!`;
    }
}

function playAgain() {
    resetToMenu();
}

function newGame() {
    resetToMenu();
}

function resetToMenu() {
    gameState = {
        mode: null,
        roomCode: null,
        isHost: false,
        players: [],
        currentPlayer: 0,
        myPlayerId: null,
        aiCount: 1,
        aiDifficulty: 'easy',
        playerPositions: {},
        gameActive: false,
        lastDiceRoll: null
    };
    
    if (modeSelection) modeSelection.style.display = 'block';
    if (soloSetup) soloSetup.style.display = 'none';
    if (multiplayerLobby) multiplayerLobby.style.display = 'none';
    if (waitingRoom) waitingRoom.style.display = 'none';
    if (gameScreen) gameScreen.style.display = 'none';
    if (resultsScreen) resultsScreen.style.display = 'none';
}

// Multiplayer Functions
function createRoom() {
    console.log('🎮 Creating room...');
    const playerName = getUserName();
    console.log('📝 Player name for room creation:', playerName);
    
    if (socket) {
        socket.emit('create_snake_room', { player_name: playerName });
    }
}

function joinRoom() {
    console.log('🎮 Joining room...');
    const roomCode = document.getElementById('room-code-input').value.toUpperCase().trim();
    const playerName = getUserName();
    
    console.log('📝 Room code:', roomCode);
    console.log('📝 Player name for joining:', playerName);
    
    if (!roomCode) {
        alert('Please enter a room code');
        return;
    }
    
    if (socket) {
        socket.emit('join_snake_room', { room_code: roomCode, player_name: playerName });
    }
}

function leaveRoom() {
    console.log('👋 Leaving room...');
    if (gameState.roomCode && socket) {
        socket.emit('leave_snake_room', { room_code: gameState.roomCode });
    }
    resetToMenu();
}

function startMultiplayerGame() {
    console.log('🎮 Starting multiplayer game...');
    if (gameState.roomCode && socket) {
        socket.emit('start_snake_game', { room_code: gameState.roomCode });
    }
}

function loadRooms() {
    console.log('📋 Loading rooms...');
    if (socket) {
        socket.emit('get_snake_rooms');
    }
}

function copyRoomCode() {
    const code = document.getElementById('waiting-room-code').textContent;
    navigator.clipboard.writeText(code).then(() => {
        const btn = document.getElementById('copy-room-code-btn');
        btn.textContent = 'Copied!';
        setTimeout(() => {
            btn.textContent = 'Copy';
        }, 2000);
    });
}

function updateWaitingRoom(players) {
    console.log('📊 Updating waiting room with players:', players);
    console.log('🎮 My player ID:', gameState.myPlayerId);
    
    const playersList = document.getElementById('waiting-players-list');
    if (!playersList) {
        console.error('❌ waiting-players-list element not found!');
        return;
    }
    
    playersList.innerHTML = players.map((player, index) => `
        <div class="player-item ${player.is_host ? 'host' : ''}">
            <div class="player-number" style="background: ${PLAYER_COLORS[index % PLAYER_COLORS.length]};">
                ${index + 1}
            </div>
            <span class="player-name">${player.name}</span>
            ${player.is_host ? '<span class="host-badge">Host</span>' : ''}
        </div>
    `).join('');
    
    const countDisplay = document.getElementById('players-count');
    if (countDisplay) {
        countDisplay.textContent = `${players.length}/6`;
        console.log(`✅ Updated player count: ${players.length}/6`);
    }
    
    const startBtn = document.getElementById('start-multiplayer-btn');
    if (startBtn) {
        const isHost = players.some(p => p.id === gameState.myPlayerId && p.is_host);
        const hasEnoughPlayers = players.length >= 2;
        
        console.log('🔍 Button visibility check:');
        console.log('  - Is host:', isHost);
        console.log('  - Enough players:', hasEnoughPlayers);
        console.log('  - Player count:', players.length);
        
        if (isHost) {
            startBtn.style.display = 'block';
            if (hasEnoughPlayers) {
                startBtn.disabled = false;
                startBtn.textContent = 'Start Game';
                console.log('✅ Start button ENABLED for host');
            } else {
                startBtn.disabled = true;
                startBtn.textContent = `⏳ Waiting for players (${players.length}/2)`;
                console.log('⚠️ Start button shown but DISABLED (need more players)');
            }
        } else {
            startBtn.style.display = 'none';
            console.log('🔒 Start button hidden (not host)');
        }
    } else {
        console.error('❌ start-multiplayer-btn element not found!');
    }
    
    const waitingStatus = document.getElementById('waiting-status');
    if (waitingStatus) {
        const isHost = players.some(p => p.id === gameState.myPlayerId && p.is_host);
        if (isHost) {
            if (players.length >= 2) {
                waitingStatus.textContent = 'Ready to start! Click "Start Game" button.';
            } else {
                waitingStatus.textContent = 'Waiting for more players to join...';
            }
        } else {
            waitingStatus.textContent = 'Waiting for host to start the game...';
        }
    }
}

function startMultiplayerGameplay(data) {
    gameState.mode = 'multiplayer';
    gameState.players = data.players.map((player, index) => ({
        id: player.id,
        name: player.name,
        position: 0,
        color: PLAYER_COLORS[index % PLAYER_COLORS.length],
        isAI: false
    }));
    gameState.currentPlayer = data.current_player;
    gameState.gameActive = true;
    
    gameState.playerPositions = {};
    gameState.players.forEach(player => {
        gameState.playerPositions[player.id] = 0;
    });
    
    if (waitingRoom) waitingRoom.style.display = 'none';
    if (gameScreen) gameScreen.style.display = 'block';
    
    const roomCodeGame = document.getElementById('room-code-game');
    if (roomCodeGame) roomCodeGame.textContent = gameState.roomCode;
    
    updatePlayersPanel();
    updateBoard();
    updateTurnDisplay();
    
    if (gameState.currentPlayer === gameState.myPlayerId) {
        enableDice();
        showMessage('Your turn! Roll the dice.');
    } else {
        disableDice();
        const currentPlayerName = gameState.players.find(p => p.id === gameState.currentPlayer)?.name;
        showMessage(`Waiting for ${currentPlayerName}...`);
    }
}

function handleRemoteDiceRoll(data) {
    gameState.lastDiceRoll = data.roll;
    const diceDisplay = document.getElementById('dice-display');
    const diceResult = document.getElementById('dice-result');
    
    if (diceDisplay) {
        diceDisplay.innerHTML = `<div class="dice-face">${getDiceFace(data.roll)}</div>`;
    }
    if (diceResult) {
        const playerName = gameState.players.find(p => p.id === data.player_id)?.name;
        diceResult.textContent = `${playerName} rolled: ${data.roll}`;
    }
}

function handleRemotePlayerMove(data) {
    gameState.playerPositions[data.player_id] = data.new_position;
    updateBoard();
    
    if (data.snake_or_ladder) {
        const playerName = gameState.players.find(p => p.id === data.player_id)?.name;
        if (data.snake_or_ladder.type === 'snake') {
            showMessage(`${playerName} hit a snake! Going down to ${data.new_position}`);
        } else {
            showMessage(`${playerName} climbed a ladder! Going up to ${data.new_position}`);
        }
    }
}

function handleTurnChange(data) {
    gameState.currentPlayer = data.current_player;
    updateTurnDisplay();
    
    if (data.current_player === gameState.myPlayerId) {
        enableDice();
        showMessage('Your turn! Roll the dice.');
    } else {
        disableDice();
        const currentPlayerName = gameState.players.find(p => p.id === data.current_player)?.name;
        showMessage(`Waiting for ${currentPlayerName}...`);
    }
}

function handleGameEnd(data) {
    gameState.gameActive = false;
    showResults({
        winner: data.winner_name,
        players: gameState.players
    });
}

function displayRoomsList(rooms) {
    const roomsList = document.getElementById('rooms-list');
    const emptyRooms = document.getElementById('empty-rooms');
    
    if (!roomsList) return;
    
    if (rooms.length === 0) {
        if (roomsList) roomsList.innerHTML = '';
        if (emptyRooms) emptyRooms.style.display = 'block';
        return;
    }
    
    if (emptyRooms) emptyRooms.style.display = 'none';
    
    roomsList.innerHTML = rooms.map(room => `
        <div class="room-item">
            <div class="room-info">
                <div class="room-code">${room.code}</div>
                <div class="room-status ${room.status}">
                    ${room.player_count}/${room.max_players} players • ${room.status}
                </div>
            </div>
            <button 
                class="join-room-btn btn btn-primary" 
                onclick="joinRoomByCode('${room.code}')"
                ${room.status !== 'waiting' ? 'disabled' : ''}
            >
                ${room.status === 'waiting' ? 'Join' : room.status}
            </button>
        </div>
    `).join('');
}

function joinRoomByCode(code) {
    const playerName = getUserName();
    if (socket) {
        socket.emit('join_snake_room', { 
            room_code: code, 
            player_name: playerName 
        });
    }
}

// Socket.IO Event Handlers
function initializeSocketEvents() {
    if (typeof socket === 'undefined') {
        console.error('❌ Socket not initialized!');
        return;
    }
    
    console.log('🔌 Initializing socket events...');
    
    cleanup.addSocketListener(socket, 'connect', () => {
        console.log('✅ Connected to server');
    });
    
    cleanup.addSocketListener(socket, 'disconnect', () => {
        console.log('⚠️ Disconnected from server');
    });
    
    cleanup.addSocketListener(socket, 'snake_room_created', (data) => {
        console.log('✅ Room created:', data);
        gameState.roomCode = data.room_code;
        gameState.isHost = true;
        gameState.myPlayerId = data.player_id;
        
        console.log('🎮 Set myPlayerId:', gameState.myPlayerId);
        
        if (multiplayerLobby) multiplayerLobby.style.display = 'none';
        if (waitingRoom) waitingRoom.style.display = 'block';
        
        const roomCodeDisplay = document.getElementById('waiting-room-code');
        if (roomCodeDisplay) roomCodeDisplay.textContent = data.room_code;
        
        updateWaitingRoom(data.players);
    });
    
    cleanup.addSocketListener(socket, 'snake_room_joined', (data) => {
        console.log('✅ Joined room:', data);
        gameState.roomCode = data.room_code;
        gameState.isHost = false;
        gameState.myPlayerId = data.player_id;
        
        console.log('🎮 Set myPlayerId:', gameState.myPlayerId);
        
        if (multiplayerLobby) multiplayerLobby.style.display = 'none';
        if (waitingRoom) waitingRoom.style.display = 'block';
        
        const roomCodeDisplay = document.getElementById('waiting-room-code');
        if (roomCodeDisplay) roomCodeDisplay.textContent = data.room_code;
        
        updateWaitingRoom(data.players);
    });
    
    cleanup.addSocketListener(socket, 'snake_player_joined', (data) => {
        console.log('👥 Player joined event received:', data);
        updateWaitingRoom(data.players);
    });
    
    cleanup.addSocketListener(socket, 'snake_player_left', (data) => {
        console.log('👋 Player left:', data);
        updateWaitingRoom(data.players);
    });
    
    cleanup.addSocketListener(socket, 'snake_game_started', (data) => {
        console.log('🎮 Game started:', data);
        startMultiplayerGameplay(data);
    });
    
    cleanup.addSocketListener(socket, 'snake_dice_rolled', (data) => {
        console.log('🎲 Dice rolled:', data);
        handleRemoteDiceRoll(data);
    });
    
    cleanup.addSocketListener(socket, 'snake_player_moved', (data) => {
        console.log('📍 Player moved:', data);
        handleRemotePlayerMove(data);
    });
    
    cleanup.addSocketListener(socket, 'snake_turn_changed', (data) => {
        console.log('🔄 Turn changed:', data);
        handleTurnChange(data);
    });
    
    cleanup.addSocketListener(socket, 'snake_game_ended', (data) => {
        console.log('🏁 Game ended:', data);
        handleGameEnd(data);
    });
    
    cleanup.addSocketListener(socket, 'snake_rooms_list', (data) => {
        console.log('📋 Rooms list:', data);
        displayRoomsList(data.rooms);
    });
    
    cleanup.addSocketListener(socket, 'snake_error', (data) => {
        console.error('❌ Error:', data.message);
        alert(data.message);
    });
    
    console.log('✅ Socket events initialized');
}

console.log('=== SNAKE-LADDER.JS FILE END ===');
// Cleanup on page unload to prevent memory leaks
window.addEventListener('beforeunload', () => {
    cleanup.cleanup();
    if (socket && socket.connected) {
        socket.disconnect();
    }
});
