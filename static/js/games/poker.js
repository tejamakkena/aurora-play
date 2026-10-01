console.log('=== POKER.JS LOADED ===');

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

// Game State
let gameState = {
    roomCode: null,
    playerId: null,
    playerName: null,
    startingChips: 1000,
    myChips: 1000,
    myBet: 0,
    myHand: [],
    communityCards: [],
    pot: 0,
    currentBet: 0,
    currentTurn: -1,
    myPosition: -1,
    players: [],
    phase: 'waiting',
    isHost: false,
    gameStarted: false
};

// DOM Elements
let modeSelection, joinRoomSection, waitingRoom, gameScreen;
let actionButtons, betControls;

// Initialize
document.addEventListener('DOMContentLoaded', init);

function init() {
    console.log('=== INITIALIZING POKER ===');
    
    // Get DOM elements
    modeSelection = document.getElementById('mode-selection');
    joinRoomSection = document.getElementById('join-room-section');
    waitingRoom = document.getElementById('waiting-room');
    gameScreen = document.getElementById('game-screen');
    actionButtons = document.getElementById('action-buttons');
    betControls = document.getElementById('raise-controls');
    
    // Get player name
    gameState.playerName = getUserName();
    console.log('Player name:', gameState.playerName);
    
    // Initialize event listeners
    initializeEventListeners();
    initializeSocketEvents();
    
    console.log('✅ Poker initialized');
}

function getUserName() {
    const bodyElement = document.querySelector('body[data-user]');
    if (bodyElement && bodyElement.dataset.user) {
        try {
            const user = JSON.parse(bodyElement.dataset.user);
            return user.first_name || user.name || user.email?.split('@')[0] || 'Player';
        } catch (e) {
            console.error('Error parsing user data:', e);
        }
    }
    
    let name = localStorage.getItem('playerName');
    if (name) return name;
    
    name = prompt('Enter your name:');
    if (name && name.trim()) {
        name = name.trim();
        localStorage.setItem('playerName', name);
        return name;
    }
    
    return 'Player_' + Math.floor(Math.random() * 1000);
}

function initializeEventListeners() {
    console.log('Setting up event listeners...');
    
    // Starting chips selection
    document.querySelectorAll('.chip-option-btn').forEach(btn => {
        cleanup.addEventListener(btn, 'click', function() {
            document.querySelectorAll('.chip-option-btn').forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            gameState.startingChips = parseInt(this.dataset.chips);
            console.log('Selected starting chips:', gameState.startingChips);
        });
    });
    
    // Mode selection
    const createRoomBtn = document.getElementById('create-room-btn');
    const joinRoomBtnStart = document.getElementById('join-room-btn-start');
    if (createRoomBtn) cleanup.addEventListener(createRoomBtn, 'click', createRoom);
    if (joinRoomBtnStart) cleanup.addEventListener(joinRoomBtnStart, 'click', () => {
        modeSelection.classList.add('hidden');
        joinRoomSection.classList.remove('hidden');
    });
    
    // Join room
    const joinRoomSubmitBtn = document.getElementById('join-room-submit-btn');
    const backToModeBtn = document.getElementById('back-to-mode-btn');
    if (joinRoomSubmitBtn) cleanup.addEventListener(joinRoomSubmitBtn, 'click', joinRoom);
    if (backToModeBtn) cleanup.addEventListener(backToModeBtn, 'click', () => {
        joinRoomSection.classList.add('hidden');
        modeSelection.classList.remove('hidden');
    });
    
    // Waiting room
    const copyCodeBtn = document.getElementById('copy-code-btn');
    const startGameBtn = document.getElementById('start-game-btn');
    const leaveRoomBtn = document.getElementById('leave-room-btn');
    if (copyCodeBtn) cleanup.addEventListener(copyCodeBtn, 'click', copyRoomCode);
    if (startGameBtn) cleanup.addEventListener(startGameBtn, 'click', startGame);
    if (leaveRoomBtn) cleanup.addEventListener(leaveRoomBtn, 'click', leaveRoom);
    
    // Game actions
    const foldBtn = document.getElementById('fold-btn');
    const checkBtn = document.getElementById('check-btn');
    const callBtn = document.getElementById('call-btn');
    const raiseBtn = document.getElementById('raise-btn');
    const allinBtn = document.getElementById('allin-btn');
    
    if (foldBtn) cleanup.addEventListener(foldBtn, 'click', () => {
        console.log('Fold clicked');
        playerAction('fold');
    });
    
    if (checkBtn) cleanup.addEventListener(checkBtn, 'click', () => {
        console.log('Check clicked');
        playerAction('check');
    });
    
    if (callBtn) cleanup.addEventListener(callBtn, 'click', () => {
        console.log('Call clicked');
        playerAction('call');
    });
    
    if (raiseBtn) cleanup.addEventListener(raiseBtn, 'click', () => {
        console.log('Raise clicked');
        showRaiseControls();
    });
    
    if (allinBtn) cleanup.addEventListener(allinBtn, 'click', () => {
        console.log('All-in clicked');
        playerAction('allin');
    });
    
    // Raise controls
    const raiseSlider = document.getElementById('raise-slider');
    const confirmRaiseBtn = document.getElementById('confirm-raise-btn');
    const cancelRaiseBtn = document.getElementById('cancel-raise-btn');
    
    if (raiseSlider) cleanup.addEventListener(raiseSlider, 'input', function() {
        document.getElementById('raise-amount-display').textContent = `$${this.value}`;
    });
    
    if (confirmRaiseBtn) cleanup.addEventListener(confirmRaiseBtn, 'click', confirmRaise);
    if (cancelRaiseBtn) cleanup.addEventListener(cancelRaiseBtn, 'click', hideRaiseControls);
    
    // New hand
    const newHandBtn = document.getElementById('new-hand-btn');
    if (newHandBtn) cleanup.addEventListener(newHandBtn, 'click', dealNewHand);
}

function initializeSocketEvents() {
    console.log('Setting up socket events...');
    
    cleanup.addSocketListener(socket, 'poker_room_created', (data) => {
        console.log('✅ Room created:', data);
        gameState.roomCode = data.room_code;
        gameState.playerId = data.player_id;
        gameState.isHost = true;
        gameState.players = data.players;
        gameState.myChips = data.starting_chips;
        
        document.getElementById('display-room-code').textContent = data.room_code;
        document.getElementById('start-game-btn').classList.remove('hidden');
        
        updatePlayersList(data.players);
        modeSelection.classList.add('hidden');
        waitingRoom.classList.remove('hidden');
        
        showMessage('Room created! Share the code with friends.', 'success');
    });
    
    cleanup.addSocketListener(socket, 'poker_room_joined', (data) => {
        console.log('✅ Room joined:', data);
        gameState.roomCode = data.room_code;
        gameState.playerId = data.player_id;
        gameState.players = data.players;
        
        document.getElementById('display-room-code').textContent = data.room_code;
        
        updatePlayersList(data.players);
        joinRoomSection.classList.add('hidden');
        waitingRoom.classList.remove('hidden');
        
        showMessage('Joined room successfully!', 'success');
    });
    
    cleanup.addSocketListener(socket, 'poker_player_joined', (data) => {
        console.log('Player joined:', data);
        gameState.players = data.players;
        updatePlayersList(data.players);
        showMessage(`${data.player_name} joined the game!`, 'info');
    });
    
    cleanup.addSocketListener(socket, 'hand_dealt', (data) => {
        console.log('✅ Hand dealt:', data);
        
        gameState.myHand = data.hand;
        gameState.communityCards = [];
        gameState.pot = data.pot;
        gameState.currentBet = data.current_bet;
        gameState.currentTurn = data.current_turn;
        gameState.players = data.players;
        gameState.phase = data.phase;
        gameState.gameStarted = true;
        gameState.myPosition = data.your_position;  // Store my position
        gameState.playerId = data.player_id;  // Store my player ID
        
        console.log('🎮 Game State Updated:', {
            myPosition: gameState.myPosition,
            myPlayerId: gameState.playerId,
            currentTurn: gameState.currentTurn,
            isMyTurn: gameState.myPosition === gameState.currentTurn,
            players: gameState.players.length
        });
        
        waitingRoom.classList.add('hidden');
        gameScreen.classList.remove('hidden');
        
        renderGame();
        updatePhase(data.phase);
        
        if (gameState.myPosition === gameState.currentTurn) {
            showMessage("It's your turn!", 'success');
            console.log("🎯 ENABLING BUTTONS - IT'S YOUR TURN");
        } else {
            const currentPlayerName = gameState.players[gameState.currentTurn]?.name || 'Unknown';
            showMessage(`⏳ Waiting for ${currentPlayerName}...`, 'info');
            console.log("⏳ Waiting for turn...");
        }
    });
    
    cleanup.addSocketListener(socket, 'player_action', (data) => {
        console.log('👤 Player action:', data);
        gameState.pot = data.pot;
        gameState.players = data.players;
        
        // Update current bet if there was a raise
        if (data.action === 'raise') {
            gameState.currentBet = data.amount;
        }
        
        renderGame();
        
        showMessage(`${data.player} ${data.action}${data.amount ? ' $' + data.amount : ''}`, 'info');
    });
    
    cleanup.addSocketListener(socket, 'next_turn', (data) => {
        console.log('⏭️ Next turn:', data);
        gameState.currentTurn = data.current_turn;
        gameState.pot = data.pot;
        gameState.players = data.players;
        
        renderGame();
        
        if (gameState.myPosition === gameState.currentTurn) {
            showMessage("It's your turn!", 'success');
            console.log("🎯 IT'S MY TURN NOW");
        } else {
            const currentPlayerName = gameState.players[gameState.currentTurn]?.name || 'Unknown';
            showMessage(`⏳ Waiting for ${currentPlayerName}...`, 'info');
            console.log(`⏳ Waiting for ${currentPlayerName}...`);
        }
    });
    
    cleanup.addSocketListener(socket, 'next_phase', (data) => {
        console.log('🎴 Next phase:', data);
        gameState.phase = data.phase;
        gameState.communityCards = data.community_cards;
        gameState.pot = data.pot;
        gameState.currentTurn = data.current_turn;
        gameState.players = data.players;
        gameState.currentBet = 0; // Reset current bet for new round
        
        renderGame();
        updatePhase(data.phase);
        
        showMessage(`Moving to ${data.phase.toUpperCase()}`, 'info');
        
        const myPlayerIndex = gameState.players.findIndex(p => p.id === gameState.playerId);
        if (myPlayerIndex === gameState.currentTurn) {
            showMessage("It's your turn!", 'success');
        }
    });
    
    cleanup.addSocketListener(socket, 'showdown', (data) => {
        console.log('🏆 Showdown:', data);
        gameState.players = data.players;
        
        renderGame();
        showWinner(data.winner, data.pot, data.hands);
        
        document.getElementById('new-hand-btn').classList.remove('hidden');
        disableActionButtons();
    });
    
    cleanup.addSocketListener(socket, 'hand_complete', (data) => {
        console.log('✅ Hand complete:', data);
        gameState.players = data.players;
        
        renderGame();
        showMessage(`${data.winner} wins $${data.pot}!`, 'success');
        
        document.getElementById('new-hand-btn').classList.remove('hidden');
        disableActionButtons();
    });
    
    cleanup.addSocketListener(socket, 'poker_error', (data) => {
        console.error('❌ Poker error:', data.message);
        showMessage(data.message, 'error');
    });
}

function createRoom() {
    console.log('Creating poker room...', {
        player_name: gameState.playerName,
        starting_chips: gameState.startingChips
    });
    
    socket.emit('create_poker_room', {
        player_name: gameState.playerName,
        starting_chips: gameState.startingChips
    });
}

function joinRoom() {
    const roomCode = document.getElementById('room-code-input').value.toUpperCase().trim();
    
    if (!roomCode || roomCode.length !== 6) {
        showMessage('Please enter a valid 6-character room code', 'error');
        return;
    }
    
    console.log('Joining poker room:', roomCode);
    
    socket.emit('join_poker_room', {
        room_code: roomCode,
        player_name: gameState.playerName
    });
}

function startGame() {
    console.log('Starting poker game...');
    
    socket.emit('start_poker_game', {
        room_code: gameState.roomCode
    });
}

function leaveRoom() {
    if (gameState.roomCode) {
        socket.emit('leave_poker_room', {
            room_code: gameState.roomCode
        });
    }
    socket.disconnect();
    setTimeout(() => location.reload(), 100);
}

function copyRoomCode() {
    const code = document.getElementById('display-room-code').textContent;
    navigator.clipboard.writeText(code);
    const btn = document.getElementById('copy-code-btn');
    btn.textContent = 'Copied!';
    setTimeout(() => {
        btn.textContent = 'Copy Code';
    }, 2000);
}

function updatePlayersList(players) {
    const list = document.getElementById('waiting-players-list');
    list.innerHTML = players.map((player, index) => `
        <div class="player-item ${player.is_host ? 'host' : ''}">
            <div class="player-number">${index + 1}</div>
            <span class="player-name">${player.name}</span>
            ${player.is_host ? '<span class="host-badge">Host</span>' : ''}
            <span class="player-chips">${player.chips}</span>
        </div>
    `).join('');
}

function renderGame() {
    console.log('=== RENDER GAME ===', {
        phase: gameState.phase,
        currentTurn: gameState.currentTurn,
        players: gameState.players.length,
        communityCards: gameState.communityCards.length
    });
    
    // Render community cards
    const communityEl = document.getElementById('community-cards');
    if (communityEl) {
        communityEl.innerHTML = '';
        if (gameState.communityCards.length === 0) {
            communityEl.innerHTML = '<div style="color: #666; font-style: italic;">Community cards will appear here</div>';
        } else {
            gameState.communityCards.forEach(card => {
                communityEl.appendChild(createCardElement(card));
            });
        }
    }
    
    // Render my hand
    const myCardsEl = document.getElementById('my-cards');
    if (myCardsEl) {
        myCardsEl.innerHTML = '';
        gameState.myHand.forEach(card => {
            const cardEl = createCardElement(card);
            cardEl.style.width = '100px';
            cardEl.style.height = '140px';
            myCardsEl.appendChild(cardEl);
        });
    }
    
    // Render all player seats
    renderPlayerSeats();
    
    // Update displays
    updateDisplay();
    updateActionButtons();
}

function createCardElement(card) {
    const cardEl = document.createElement('div');
    const suitClass = (card.suit === '♥' || card.suit === '♦') ? 'hearts' : 
                      (card.suit === '♠' || card.suit === '♣') ? 'spades' : '';
    cardEl.className = `card ${suitClass}`;
    cardEl.innerHTML = `
        <div class="card-value">${card.value}</div>
        <div class="card-suit">${card.suit}</div>
    `;
    return cardEl;
}

/**
 * Optimized renderPlayerSeats - updates only changed elements instead of full rebuild
 */
function renderPlayerSeats() {
    const container = document.getElementById('player-seats-container');
    if (!container) return;
    
    const seatPositions = [
        'seat-bottom',
        'seat-bottom-left', 
        'seat-left',
        'seat-top-left',
        'seat-top',
        'seat-top-right',
        'seat-right',
        'seat-bottom-right'
    ];
    
    // Get existing seats or create container structure
    let existingSeats = container.querySelectorAll('.player-seat');
    
    let seatIndex = 0;
    gameState.players.forEach((player, index) => {
        // Skip rendering myself - I'm in the bottom panel
        if (player.is_me || player.id === gameState.playerId) {
            return;
        }
        
        const isDealer = index === 0;
        const isActive = index === gameState.currentTurn;
        
        let statusClass = 'status-waiting';
        let statusText = 'Waiting';
        
        if (player.folded) {
            statusClass = 'status-folded';
            statusText = 'Folded';
        } else if (isActive) {
            statusClass = 'status-betting';
            statusText = 'Thinking...';
        } else if (player.bet > 0) {
            statusClass = 'status-betting';
            statusText = `Bet: $${player.bet}`;
        }
        
        // Try to reuse existing seat element
        let seatDiv = existingSeats[seatIndex];
        
        if (!seatDiv || seatDiv.dataset.playerId !== player.id.toString()) {
            // Create new seat if doesn't exist or player changed
            if (seatDiv) {
                seatDiv.remove();
            }
            
            seatDiv = document.createElement('div');
            seatDiv.className = `player-seat ${seatPositions[seatIndex]}`;
            seatDiv.dataset.playerId = player.id;
            
            seatDiv.innerHTML = `
                <div class="player-name-tag"></div>
                <div class="player-chips-display">
                    <span class="chip-label">Chips:</span>
                    <span class="chip-amount"></span>
                </div>
                <div class="player-cards-container"></div>
                <div class="player-status"></div>
            `;
            
            container.appendChild(seatDiv);
        }
        
        // Update classes
        seatDiv.className = `player-seat ${seatPositions[seatIndex]} ${isActive ? 'active-turn' : ''}`;
        
        // Update content only if changed (reduces DOM manipulation)
        const nameTag = seatDiv.querySelector('.player-name-tag');
        const newNameContent = `${isDealer ? '<span class="dealer-button">D</span>' : ''}${player.name}`;
        if (nameTag.innerHTML !== newNameContent) {
            nameTag.innerHTML = newNameContent;
        }
        
        const chipAmount = seatDiv.querySelector('.chip-amount');
        const newChipText = `$${player.chips}`;
        if (chipAmount.textContent !== newChipText) {
            chipAmount.textContent = newChipText;
        }
        
        const cardsContainer = seatDiv.querySelector('.player-cards-container');
        const newCardsHTML = !player.folded ? `
            <div class="card back"></div>
            <div class="card back"></div>
        ` : '';
        if (cardsContainer.innerHTML !== newCardsHTML) {
            cardsContainer.innerHTML = newCardsHTML;
        }
        
        const statusEl = seatDiv.querySelector('.player-status');
        statusEl.className = `player-status ${statusClass}`;
        if (statusEl.textContent !== statusText) {
            statusEl.textContent = statusText;
        }
        
        seatIndex++;
    });
    
    // Remove extra seats if players left
    while (seatIndex < existingSeats.length) {
        existingSeats[seatIndex].remove();
        seatIndex++;
    }
}

function updateDisplay() {
    const potEl = document.getElementById('pot-amount');
    if (potEl) {
        potEl.textContent = `$${gameState.pot}`;
    }
    
    const myPlayer = gameState.players.find(p => p.id === gameState.playerId);
    if (myPlayer) {
        const chipsEl = document.getElementById('my-chips');
        const betEl = document.getElementById('my-bet');
        const callEl = document.getElementById('to-call');
        
        if (chipsEl) chipsEl.textContent = `$${myPlayer.chips}`;
        if (betEl) betEl.textContent = `$${myPlayer.bet}`;
        if (callEl) {
            const toCall = Math.max(0, gameState.currentBet - myPlayer.bet);
            callEl.textContent = `$${toCall}`;
        }
    }
}

function updatePhase(phase) {
    const phaseNames = {
        'preflop': 'Pre-Flop',
        'flop': 'Flop',
        'turn': 'Turn',
        'river': 'River',
        'showdown': 'Showdown'
    };
    const phaseEl = document.getElementById('phase-indicator');
    if (phaseEl) {
        phaseEl.textContent = phaseNames[phase] || phase;
    }
}
function updateActionButtons() {
    const isMyTurn = gameState.myPosition === gameState.currentTurn;
    const myPlayer = gameState.players.find(p => p.id === gameState.playerId);
    
    console.log('📊 Update action buttons:', {
        myPosition: gameState.myPosition,
        currentTurn: gameState.currentTurn,
        isMyTurn,
        currentBet: gameState.currentBet,
        myBet: myPlayer?.bet,
        myChips: myPlayer?.chips,
        folded: myPlayer?.folded
    });
    
    if (!isMyTurn || !myPlayer || myPlayer.folded) {
        disableActionButtons();
        return;
    }
    
    // Enable/disable specific buttons
    const foldBtn = document.getElementById('fold-btn');
    const checkBtn = document.getElementById('check-btn');
    const callBtn = document.getElementById('call-btn');
    const raiseBtn = document.getElementById('raise-btn');
    const allinBtn = document.getElementById('allin-btn');
    
    // Always enable fold when it's your turn
    if (foldBtn) {
        foldBtn.disabled = false;
        console.log('✅ Fold button enabled');
    }
    
    // Check if we can check (our bet matches current bet)
    const canCheck = myPlayer.bet >= gameState.currentBet;
    if (checkBtn) {
        checkBtn.disabled = !canCheck;
        console.log(`${canCheck ? '✅' : '❌'} Check button ${canCheck ? 'enabled' : 'disabled'}`);
    }
    
    // Check if we need to call
    const needToCall = myPlayer.bet < gameState.currentBet;
    const callAmount = gameState.currentBet - myPlayer.bet;
    if (callBtn) {
        callBtn.disabled = !needToCall || myPlayer.chips < callAmount;
        if (needToCall) {
            callBtn.textContent = `Call $${callAmount}`;
        } else {
            callBtn.textContent = 'Call';
        }
        console.log(`${needToCall && myPlayer.chips >= callAmount ? '✅' : '❌'} Call button`);
    }
    
    // Can always raise if we have chips
    if (raiseBtn) {
        raiseBtn.disabled = myPlayer.chips <= 0;
        console.log(`${myPlayer.chips > 0 ? '✅' : '❌'} Raise button`);
    }
    
    // Can always go all-in if we have chips
    if (allinBtn) {
        allinBtn.disabled = myPlayer.chips <= 0;
        console.log(`${myPlayer.chips > 0 ? '✅' : '❌'} All-in button`);
    }
}

function disableActionButtons() {
    const buttons = ['fold-btn', 'check-btn', 'call-btn', 'raise-btn', 'allin-btn'];
    buttons.forEach(btnId => {
        const btn = document.getElementById(btnId);
        if (btn) btn.disabled = true;
    });
}

function playerAction(action) {
    console.log('🎮 Player action:', action);
    
    socket.emit('poker_action', {
        room_code: gameState.roomCode,
        action: action
    });
    
    disableActionButtons();
    showMessage(`You ${action}`, 'info');
}

function showRaiseControls() {
    if (actionButtons) actionButtons.classList.add('hidden');
    if (betControls) betControls.classList.remove('hidden');
    
    const myPlayer = gameState.players.find(p => p.id === gameState.playerId);
    const minRaise = Math.max(gameState.currentBet * 2, gameState.currentBet + 50);
    const maxRaise = myPlayer.chips + myPlayer.bet;
    
    const slider = document.getElementById('raise-slider');
    if (slider) {
        slider.min = minRaise;
        slider.max = maxRaise;
        slider.value = minRaise;
        document.getElementById('raise-amount-display').textContent = `$${minRaise}`;
    }
}

function hideRaiseControls() {
    if (betControls) betControls.classList.add('hidden');
    if (actionButtons) actionButtons.classList.remove('hidden');
}

function confirmRaise() {
    const raiseAmount = parseInt(document.getElementById('raise-slider').value);
    
    console.log('Confirming raise:', raiseAmount);
    
    socket.emit('poker_action', {
        room_code: gameState.roomCode,
        action: 'raise',
        raise_amount: raiseAmount
    });
    
    hideRaiseControls();
    disableActionButtons();
    showMessage(`You raised to $${raiseAmount}`, 'info');
}

function dealNewHand() {
    document.getElementById('new-hand-btn').classList.add('hidden');
    
    socket.emit('deal_new_hand', {
        room_code: gameState.roomCode
    });
    
    showMessage('Dealing new hand...', 'info');
}

function showMessage(message, type) {
    console.log(`[${type.toUpperCase()}] ${message}`);
    
    const msgDiv = document.createElement('div');
    msgDiv.className = `poker-message poker-message-${type}`;
    msgDiv.textContent = message;
    msgDiv.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        padding: 15px 25px;
        background: ${type === 'success' ? '#00ff00' : type === 'error' ? '#ff0000' : '#00f5ff'};
        color: black;
        border-radius: 8px;
        z-index: 10000;
        font-weight: bold;
        box-shadow: 0 4px 15px rgba(0, 0, 0, 0.5);
    `;
    
    document.body.appendChild(msgDiv);
    
    setTimeout(() => {
        msgDiv.style.opacity = '0';
        msgDiv.style.transition = 'opacity 0.3s';
        setTimeout(() => msgDiv.remove(), 300);
    }, 3000);
}

function showWinner(winner, pot, hands) {
    const announcement = document.createElement('div');
    announcement.className = 'winner-announcement';
    announcement.style.cssText = `
        position: fixed;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        background: rgba(0, 0, 0, 0.95);
        border: 3px solid gold;
        border-radius: 20px;
        padding: 40px;
        z-index: 10000;
        text-align: center;
        color: white;
        box-shadow: 0 0 50px rgba(255, 215, 0, 0.8);
    `;
    
    announcement.innerHTML = `
        <h2 style="color: #FFD700; font-size: 2.5em; margin-bottom: 20px;">${winner} Wins!</h2>
        <p style="font-size: 2em; color: #00ff00;">Won $${pot}</p>
        <div style="margin-top: 30px; text-align: left;">
            <h3 style="color: #00f5ff; margin-bottom: 15px;">Final Hands:</h3>
            ${Object.entries(hands).map(([name, hand]) => `
                <div style="margin: 10px 0; padding: 10px; background: rgba(255, 255, 255, 0.1); border-radius: 5px;">
                    <strong style="color: #FFD700;">${name}:</strong> 
                    <span style="color: white;">${hand.map(c => c.value + c.suit).join(' ')}</span>
                </div>
            `).join('')}
        </div>
    `;
    
    document.body.appendChild(announcement);
    
    setTimeout(() => {
        announcement.style.opacity = '0';
        announcement.style.transition = 'opacity 0.5s';
        setTimeout(() => announcement.remove(), 500);
    }, 5000);
}

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    cleanup.cleanup();
    if (socket && socket.connected) {
        socket.disconnect();
    }
});

console.log('✅ Poker JS fully loaded and ready');