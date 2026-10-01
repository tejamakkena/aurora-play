// Cleanup manager for proper resource cleanup
const cleanup = new CleanupManager();

let currentRoomCode = null;
let playerId = null;
let playerInfo = null;
let pollingInterval = null;
let gameState = null;
let flippedIndices = [];
let isProcessing = false; // Prevent rapid card flips

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
    if (sessionStorage.getItem('playerInfo')) {
        playerInfo = JSON.parse(sessionStorage.getItem('playerInfo'));
        currentRoomCode = sessionStorage.getItem('currentRoomCode');
        playerId = sessionStorage.getItem('playerId');
    }
    
    // Load rooms on page load
    loadRooms();
    startRoomsPolling();
}

async function loadRooms() {
    try {
        const response = await fetch('/memory/rooms');
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
    } catch (error) {
        console.error('Error loading rooms:', error);
    }
}

function startRoomsPolling() {
    if (pollingInterval) return;
    pollingInterval = cleanup.addInterval(setInterval(loadRooms, 5000));
}

function stopRoomsPolling() {
    if (pollingInterval) {
        clearInterval(pollingInterval);
        pollingInterval = null;
    }
}

// Pause polling when tab is hidden
document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
        if (pollingInterval) {
            console.log('Memory: Tab hidden, pausing room polling');
            stopRoomsPolling();
        }
    } else {
        const lobby = document.getElementById('lobby');
        if (!pollingInterval && lobby && !lobby.classList.contains('hidden')) {
            console.log('Memory: Tab visible, resuming room polling');
            startRoomsPolling();
            loadRooms();
        }
    }
});

async function createGame() {
    try {
        const response = await fetch('/memory/create', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ grid_size: 16 }) // 4x4 grid
        });
        
        const data = await response.json();
        
        if (data.success) {
            currentRoomCode = data.room_code;
            playerId = data.player_id;
            playerInfo = data.player_info;
            
            // Save to session storage
            sessionStorage.setItem('currentRoomCode', currentRoomCode);
            sessionStorage.setItem('playerId', playerId);
            sessionStorage.setItem('playerInfo', JSON.stringify(playerInfo));
            
            switchToGameArea();
            startGamePolling();
        } else {
            alert('Failed to create game: ' + (data.error || 'Unknown error'));
        }
    } catch (error) {
        console.error('Error creating game:', error);
        alert('Failed to create game. Please try again.');
    }
}

function joinGameManual() {
    const roomCode = document.getElementById('room-code-input').value.trim().toUpperCase();
    if (!roomCode) {
        alert('Please enter a room code');
        return;
    }
    joinGameByCode(roomCode);
}

async function joinGameByCode(roomCode) {
    try {
        const response = await fetch(`/memory/join/${roomCode}`, {
            method: 'POST'
        });
        
        const data = await response.json();
        
        if (data.success) {
            currentRoomCode = roomCode;
            playerId = data.player_id;
            playerInfo = data.player_info;
            gameState = data.game_state;
            
            // Save to session storage
            sessionStorage.setItem('currentRoomCode', currentRoomCode);
            sessionStorage.setItem('playerId', playerId);
            sessionStorage.setItem('playerInfo', JSON.stringify(playerInfo));
            
            switchToGameArea();
            updateGameUI();
            startGamePolling();
        } else {
            alert('Failed to join game: ' + (data.error || 'Unknown error'));
        }
    } catch (error) {
        console.error('Error joining game:', error);
        alert('Failed to join game. Please try again.');
    }
}

function switchToGameArea() {
    document.getElementById('lobby').classList.add('hidden');
    document.getElementById('game-area').classList.remove('hidden');
    document.getElementById('room-code-display').textContent = `Room: ${currentRoomCode}`;
    stopRoomsPolling();
}

function startGamePolling() {
    if (pollingInterval) stopGamePolling();
    
    // Poll game state every 1 second
    pollingInterval = cleanup.addInterval(setInterval(async () => {
        await fetchGameState();
    }, 1000));
    
    // Initial fetch
    fetchGameState();
}

function stopGamePolling() {
    if (pollingInterval) {
        clearInterval(pollingInterval);
        pollingInterval = null;
    }
}

async function fetchGameState() {
    if (!currentRoomCode) return;
    
    try {
        const response = await fetch(`/memory/state/${currentRoomCode}`);
        const data = await response.json();
        
        if (data.success) {
            gameState = data.game_state;
            updateGameUI();
            
            // Check if game finished
            if (gameState.state === 'FINISHED') {
                stopGamePolling();
                showGameEndModal();
            }
        }
    } catch (error) {
        console.error('Error fetching game state:', error);
    }
}

function updateGameUI() {
    if (!gameState) return;
    
    // Update status
    const statusEl = document.getElementById('game-status');
    const currentPlayerName = gameState.players[gameState.current_player]?.name || 'Unknown';
    const isMyTurn = gameState.current_player === playerId;
    
    if (gameState.state === 'WAITING') {
        statusEl.textContent = 'Waiting for players...';
        statusEl.className = 'status-waiting';
    } else if (isMyTurn) {
        statusEl.textContent = 'Your Turn!';
        statusEl.className = 'status-your-turn';
    } else {
        statusEl.textContent = `${currentPlayerName}'s Turn`;
        statusEl.className = 'status-other-turn';
    }
    
    // Update scoreboard
    updateScoreboard();
    
    // Update grid
    updateGrid();
}

function updateScoreboard() {
    const scoreboard = document.getElementById('scoreboard');
    const players = gameState.players;
    
    scoreboard.innerHTML = Object.entries(players).map(([pid, pinfo]) => {
        const isCurrentPlayer = pid === gameState.current_player;
        const isMe = pid === playerId;
        const activeClass = isCurrentPlayer ? 'active-player' : '';
        const meClass = isMe ? 'me' : '';
        
        return `
            <div class="player-score ${activeClass} ${meClass}">
                <div class="player-name">${pinfo.name}${isMe ? ' (You)' : ''}</div>
                <div class="player-points">${pinfo.score} ${pinfo.score === 1 ? 'pair' : 'pairs'}</div>
            </div>
        `;
    }).join('');
}

function updateGrid() {
    const grid = document.getElementById('memory-grid');
    
    // Only create grid once
    if (grid.children.length === 0) {
        gameState.cards.forEach((card, index) => {
            const cardEl = document.createElement('div');
            cardEl.className = 'memory-card';
            cardEl.dataset.index = index;
            
            const cardInner = document.createElement('div');
            cardInner.className = 'card-inner';
            
            const cardFront = document.createElement('div');
            cardFront.className = 'card-front';
            cardFront.textContent = '?';
            
            const cardBack = document.createElement('div');
            cardBack.className = 'card-back';
            
            cardInner.appendChild(cardFront);
            cardInner.appendChild(cardBack);
            cardEl.appendChild(cardInner);
            
            cleanup.addEventListener(cardEl, 'click', () => handleCardClick(index));
            grid.appendChild(cardEl);
        });
    }
    
    // Update card states
    gameState.cards.forEach((card, index) => {
        const cardEl = grid.children[index];
        const cardBack = cardEl.querySelector('.card-back');
        cardBack.textContent = card.symbol;
        
        if (card.matched) {
            cardEl.classList.add('matched');
            cardEl.classList.add('flipped');
        } else if (card.flipped) {
            cardEl.classList.add('flipped');
        } else {
            cardEl.classList.remove('flipped');
            cardEl.classList.remove('matched');
        }
    });
}

async function handleCardClick(cardIndex) {
    if (isProcessing) return;
    if (gameState.current_player !== playerId) return;
    if (gameState.cards[cardIndex].matched) return;
    if (gameState.cards[cardIndex].flipped) return;
    if (gameState.flipped_cards.length >= 2) {
        // Need to reset first
        await resetFlippedCards();
        return;
    }
    
    isProcessing = true;
    
    try {
        const response = await fetch(`/memory/flip/${currentRoomCode}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ card_index: cardIndex })
        });
        
        const data = await response.json();
        
        if (data.success) {
            gameState = data.game_state;
            updateGameUI();
            
            // If we have a match result
            if (data.match_result) {
                if (data.match_result.matched) {
                    // Match! Keep cards flipped
                    setTimeout(() => {
                        isProcessing = false;
                    }, 500);
                } else {
                    // No match - auto reset after delay
                    setTimeout(async () => {
                        await resetFlippedCards();
                        isProcessing = false;
                    }, 1500);
                }
            } else {
                isProcessing = false;
            }
        } else {
            alert(data.error || 'Failed to flip card');
            isProcessing = false;
        }
    } catch (error) {
        console.error('Error flipping card:', error);
        isProcessing = false;
    }
}

async function resetFlippedCards() {
    try {
        const response = await fetch(`/memory/reset-flipped/${currentRoomCode}`, {
            method: 'POST'
        });
        
        const data = await response.json();
        
        if (data.success) {
            gameState = data.game_state;
            updateGameUI();
        }
    } catch (error) {
        console.error('Error resetting flipped cards:', error);
    }
}

function showGameEndModal() {
    const modal = document.getElementById('game-end-modal');
    const title = document.getElementById('modal-title');
    const message = document.getElementById('modal-message');
    const finalScores = document.getElementById('final-scores');
    
    if (gameState.winner === playerId) {
        title.textContent = 'You Won!';
        message.textContent = 'Congratulations! You found the most pairs!';
    } else if (gameState.winner === 'TIE') {
        title.textContent = 'It\'s a Tie!';
        message.textContent = 'Great game! You tied for the win!';
    } else {
        const winnerName = gameState.players[gameState.winner]?.name || 'Unknown';
        title.textContent = 'Game Over';
        message.textContent = `${winnerName} won the game!`;
    }
    
    // Show final scores
    const sortedPlayers = Object.entries(gameState.players)
        .sort(([, a], [, b]) => b.score - a.score);
    
    finalScores.innerHTML = sortedPlayers.map(([pid, pinfo], index) => `
        <div class="final-score-item ${pid === playerId ? 'highlight' : ''}">
            <span class="rank">#${index + 1}</span>
            <span class="name">${pinfo.name}${pid === playerId ? ' (You)' : ''}</span>
            <span class="score">${pinfo.score}</span>
        </div>
    `).join('');
    
    modal.classList.remove('hidden');
}

function playAgain() {
    sessionStorage.clear();
    location.reload();
}

function backToLobby() {
    if (currentRoomCode) {
        // Leave game
        fetch(`/memory/leave/${currentRoomCode}`, { method: 'POST' })
            .catch(err => console.error('Error leaving game:', err));
    }
    
    sessionStorage.clear();
    cleanup.cleanup();
    location.reload();
}

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    if (currentRoomCode) {
        navigator.sendBeacon(`/memory/leave/${currentRoomCode}`);
    }
});
