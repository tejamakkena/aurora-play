// Cleanup manager for proper resource cleanup
const cleanup = new CleanupManager();

let currentRoomCode = null;
let playerId = null;
let playerSymbol = null;
let pollingInterval = null;

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', initGame);

function initGame() {
    // Set up event listeners with cleanup tracking
    cleanup.addEventListener(document.getElementById('create-game-btn'), 'click', createGame);
    cleanup.addEventListener(document.getElementById('join-game-btn'), 'click', joinGameManual);
    cleanup.addEventListener(document.getElementById('back-to-lobby'), 'click', backToLobby);
    cleanup.addEventListener(document.getElementById('refresh-rooms-btn'), 'click', loadRooms);
    cleanup.addEventListener(document.getElementById('play-again-btn'), 'click', playAgain);
    cleanup.addEventListener(document.getElementById('exit-to-lobby-btn'), 'click', backToLobby);
    
    // Restore session if page reloaded
    if (sessionStorage.getItem('playerSymbol')) {
        playerSymbol = sessionStorage.getItem('playerSymbol');
        currentRoomCode = sessionStorage.getItem('currentRoomCode');
        playerId = sessionStorage.getItem('playerId');
    }
    
    // Load rooms on page load
    loadRooms();
    startRoomsPolling();
}

async function loadRooms() {
    const response = await fetch('/tictactoe/rooms');
    const data = await response.json();
    
    const roomsList = document.getElementById('rooms-list');
    
    if (data.success && data.rooms.length > 0) {
        roomsList.innerHTML = data.rooms.map(room => {
            const statusClass = room.is_full ? 'full' : (room.status === 'PLAYING' ? 'playing' : 'waiting');
            const statusText = room.is_full ? 'Full' : (room.status === 'PLAYING' ? 'Playing' : 'Waiting for players');
            
            return `
                <div class="room-item">
                    <div class="room-info">
                        <div class="room-code">${room.room_code}</div>
                        <div class="room-status ${statusClass}">
                            ${room.player_count}/${room.max_players} • ${statusText}
                        </div>
                    </div>
                    <button class="join-room-btn btn" 
                            onclick="joinGameByCode('${room.room_code}')" 
                            ${room.is_full ? 'disabled' : ''}>
                        ${room.is_full ? 'Full' : 'Join'}
                    </button>
                </div>
            `;
        }).join('');
    } else {
        roomsList.innerHTML = '<div class="empty-rooms">No active rooms. Create one to start playing!</div>';
    }
}

function startRoomsPolling() {
    if (pollingInterval) return; // Already polling
    // Increased interval from 3000ms to 5000ms for better performance
    pollingInterval = cleanup.addInterval(setInterval(loadRooms, 5000));
}

function stopRoomsPolling() {
    if (pollingInterval) {
        clearInterval(pollingInterval);
        pollingInterval = null;
    }
}

// Pause polling when tab is hidden to save resources
document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
        // Page is hidden, stop polling
        if (pollingInterval) {
            console.log('TicTacToe: Tab hidden, pausing room polling');
            stopRoomsPolling();
        }
    } else {
        // Page is visible again, restart polling if in lobby
        const lobby = document.getElementById('lobby');
        if (!pollingInterval && lobby && !lobby.classList.contains('hidden')) {
            console.log('TicTacToe: Tab visible, resuming room polling');
            startRoomsPolling();
            loadRooms(); // Immediate refresh
        }
    }
});

async function createGame() {
    const response = await fetch('/tictactoe/create', {
        method: 'POST'
    });
    const data = await response.json();
    
    console.log('=== CREATE RESPONSE ===', data);
    
    if (data.success) {
        currentRoomCode = data.room_code;
        playerId = data.player_id;
        playerSymbol = data.symbol;
        
        // Store in sessionStorage
        sessionStorage.setItem('playerSymbol', playerSymbol);
        sessionStorage.setItem('currentRoomCode', currentRoomCode);
        sessionStorage.setItem('playerId', playerId);
        
        console.log('=== CREATE GAME ===');
        console.log('Player ID:', playerId);
        console.log('Symbol:', playerSymbol);
        
        showGame();
        document.getElementById('room-code-display').textContent = `Room Code: ${currentRoomCode}`;
        document.getElementById('room-code-display').classList.remove('hidden');
        document.getElementById('game-status').textContent = 'Waiting for opponent...';
        
        startGamePolling();
        stopRoomsPolling();
    }
}

async function joinGameManual() {
    const roomCode = document.getElementById('room-code-input').value.toUpperCase();
    if (!roomCode) {
        alert('Please enter a room code');
        return;
    }
    await joinGameByCode(roomCode);
}

async function joinGameByCode(roomCode) {
    const response = await fetch(`/tictactoe/join/${roomCode}`, {
        method: 'POST'
    });
    const data = await response.json();
    
    console.log('=== JOIN RESPONSE ===', data);
    
    if (data.success) {
        currentRoomCode = roomCode;
        playerId = data.player_id;
        playerSymbol = data.symbol;
        
        // Store in sessionStorage
        sessionStorage.setItem('playerSymbol', playerSymbol);
        sessionStorage.setItem('currentRoomCode', currentRoomCode);
        sessionStorage.setItem('playerId', playerId);
        
        console.log('=== JOIN GAME ===');
        console.log('Player ID:', playerId);
        console.log('Symbol:', playerSymbol);
        
        showGame();
        document.getElementById('room-code-display').textContent = `Room Code: ${currentRoomCode}`;
        document.getElementById('room-code-display').classList.remove('hidden');
        updateGameState(data.game_state);
        startGamePolling();
        stopRoomsPolling();
    } else {
        alert(data.error);
    }
}

// Cell click handlers stored for proper cleanup
const cellClickHandlers = new Map();

function showGame() {
    document.getElementById('lobby').classList.add('hidden');
    document.getElementById('game-area').classList.remove('hidden');
    
    // Add cell listeners with cleanup tracking
    document.querySelectorAll('.cell').forEach(cell => {
        const handler = makeMoveHandler(cell);
        cellClickHandlers.set(cell, handler);
        cleanup.addEventListener(cell, 'click', handler);
    });
}

function makeMoveHandler(cell) {
    return async function(e) {
        const position = parseInt(e.target.dataset.index);
        
        const response = await fetch(`/tictactoe/move/${currentRoomCode}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ position })
        });
        
        const data = await response.json();
        
        if (data.success) {
            updateGameState(data.game_state);
        } else {
            alert(data.error);
        }
    };
}

async function pollGameState() {
    if (!currentRoomCode) return;
    
    try {
        const response = await fetch(`/tictactoe/state/${currentRoomCode}`);
        const data = await response.json();
        
        if (data.success) {
            updateGameState(data.game_state);
        }
    } catch (error) {
        console.error('Error polling game state:', error);
    }
}

function updateGameState(gameState) {
    gameState.board.forEach((symbol, index) => {
        const cell = document.querySelector(`[data-index="${index}"]`);
        cell.textContent = symbol;
        if (symbol) {
            cell.classList.add('taken');
            if (symbol === '⭕') {
                cell.classList.add('circle-symbol');
            } else if (symbol === '❌') {
                cell.classList.add('x-symbol');
            }
        }
    });
    
    if (gameState.winner) {
        document.getElementById('game-status').textContent = `${gameState.winner} wins!`;
        stopGamePolling();
        
        // Get symbol from storage if lost
        if (!playerSymbol) {
            playerSymbol = sessionStorage.getItem('playerSymbol');
        }
        
        showGameEndModal(gameState.winner, false);
    } else if (gameState.is_draw) {
        document.getElementById('game-status').textContent = "It's a draw!";
        stopGamePolling();
        showGameEndModal(null, true);
    } else if (gameState.state === 'PLAYING') {
        const isMyTurn = gameState.players[playerId] === gameState.current_turn;
        document.getElementById('game-status').textContent = 
            isMyTurn ? `Your turn (${gameState.current_turn})` : `Opponent's turn (${gameState.current_turn})`;
    }
}

function showGameEndModal(winner, isDraw) {
    // Ensure we have the symbol
    if (!playerSymbol) {
        playerSymbol = sessionStorage.getItem('playerSymbol');
    }
    
    const modal = document.getElementById('game-end-modal');
    const modalIcon = document.getElementById('modal-icon');
    const modalTitle = document.getElementById('modal-title');
    const modalMessage = document.getElementById('modal-message');
    const playerSymbolEl = document.getElementById('player-symbol');
    const gameResultEl = document.getElementById('game-result');
    
    playerSymbolEl.textContent = playerSymbol || 'N/A';
    
    if (isDraw) {
        modalIcon.textContent = '';
        modalTitle.textContent = "It's a Draw!";
        modalMessage.textContent = "Well played! Both players showed great skill.";
        gameResultEl.textContent = 'DRAW';
        gameResultEl.className = 'stat-value draw';
    } else if (!playerSymbol) {
        // Fallback if symbol still not found
        modalIcon.textContent = '?';
        modalTitle.textContent = "Game Over";
        modalMessage.textContent = "The game has ended.";
        gameResultEl.textContent = 'FINISHED';
        gameResultEl.className = 'stat-value';
    } else {
        // Normalize symbols for comparison
        const normalizedWinner = String(winner).trim();
        const normalizedPlayerSymbol = String(playerSymbol).trim();
        
        if (normalizedWinner === normalizedPlayerSymbol) {
            modalIcon.textContent = '';
            modalTitle.textContent = "Victory!";
            modalMessage.textContent = "Congratulations! You won the game!";
            gameResultEl.textContent = 'WIN';
            gameResultEl.className = 'stat-value win';
        } else {
            modalIcon.textContent = '';
            modalTitle.textContent = "Defeat";
            modalMessage.textContent = "Better luck next time!";
            gameResultEl.textContent = 'LOSS';
            gameResultEl.className = 'stat-value loss';
        }
    }
    
    modal.classList.remove('hidden');
    modal.classList.add('show');
}

function hideGameEndModal() {
    const modal = document.getElementById('game-end-modal');
    modal.classList.remove('show');
    modal.classList.add('hidden');
}

function playAgain() {
    hideGameEndModal();
    backToLobby();
}

function startGamePolling() {
    if (pollingInterval) return; // Already polling
    // Increased interval from 1000ms to 2000ms for better performance
    pollingInterval = cleanup.addInterval(setInterval(pollGameState, 2000));
}

function stopGamePolling() {
    if (pollingInterval) {
        cleanup.clearInterval(pollingInterval);
        pollingInterval = null;
    }
}

function backToLobby() {
    stopGamePolling();
    hideGameEndModal();
    
    // Clear session storage
    sessionStorage.removeItem('playerSymbol');
    sessionStorage.removeItem('currentRoomCode');
    sessionStorage.removeItem('playerId');
    
    currentRoomCode = null;
    playerId = null;
    playerSymbol = null;
    
    // Clear cell handlers
    cellClickHandlers.clear();
    
    document.querySelectorAll('.cell').forEach(cell => {
        cell.textContent = '';
        cell.classList.remove('taken', 'circle-symbol', 'x-symbol');
    });
    
    document.getElementById('lobby').classList.remove('hidden');
    document.getElementById('game-area').classList.add('hidden');
    document.getElementById('room-code-display').classList.add('hidden');
    
    loadRooms();
    startRoomsPolling();
}

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    console.log('TicTacToe: Cleaning up resources...');
    cleanup.cleanup();
    stopGamePolling();
    stopRoomsPolling();
});

console.log('✅ TicTacToe script loaded with CleanupManager');
