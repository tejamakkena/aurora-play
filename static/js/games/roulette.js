console.log('🎰 Roulette Casino loaded');

// Cleanup manager for proper resource cleanup
const cleanup = new CleanupManager();

// Game state
const gameState = {
    totalMoney: 1000,
    currentChipValue: 10,
    bets: {},
    isSpinning: false,
    wheelRotation: 0
};

// Roulette numbers in exact wheel order (European Roulette)
const rouletteNumbers = [
    { num: 0, color: 'green' },
    { num: 32, color: 'red' }, { num: 15, color: 'black' }, { num: 19, color: 'red' },
    { num: 4, color: 'black' }, { num: 21, color: 'red' }, { num: 2, color: 'black' },
    { num: 25, color: 'red' }, { num: 17, color: 'black' }, { num: 34, color: 'red' },
    { num: 6, color: 'black' }, { num: 27, color: 'red' }, { num: 13, color: 'black' },
    { num: 36, color: 'red' }, { num: 11, color: 'black' }, { num: 30, color: 'red' },
    { num: 8, color: 'black' }, { num: 23, color: 'red' }, { num: 10, color: 'black' },
    { num: 5, color: 'red' }, { num: 24, color: 'black' }, { num: 16, color: 'red' },
    { num: 33, color: 'black' }, { num: 1, color: 'red' }, { num: 20, color: 'black' },
    { num: 14, color: 'red' }, { num: 31, color: 'black' }, { num: 9, color: 'red' },
    { num: 22, color: 'black' }, { num: 18, color: 'red' }, { num: 29, color: 'black' },
    { num: 7, color: 'red' }, { num: 28, color: 'black' }, { num: 12, color: 'red' },
    { num: 35, color: 'black' }, { num: 3, color: 'red' }, { num: 26, color: 'black' }
];

const redNumbers = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36];

// DOM Elements
let modeSelection, rouletteGame, soloModeBtn, spinBtn, clearBetsBtn, canvas, ctx, ball;

// Performance optimization: Cache wheel rendering
let cachedWheelCanvas = null;

// Animation frame ID for cleanup
let animationFrameId = null;

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', init);

// ─── Multiplayer state ───────────────────────────────────────────────────────
let mpSocket = null;
let mpRoomCode = null;
let mpPlayerId = null;
let mpIsHost = false;
let mpChipValue = 10;

function initMultiplayer() {
    mpSocket = io();

    // UI references
    const lobby       = document.getElementById('multiplayer-lobby');
    const waiting     = document.getElementById('multiplayer-waiting');
    const mpGame      = document.getElementById('multiplayer-game');
    const modeSelEl   = document.getElementById('mode-selection');

    document.getElementById('multiplayer-mode-btn').addEventListener('click', () => {
        modeSelEl.classList.add('hidden');
        lobby.classList.remove('hidden');
    });

    document.getElementById('mp-back-btn').addEventListener('click', () => {
        lobby.classList.add('hidden');
        modeSelEl.classList.remove('hidden');
    });

    document.getElementById('mp-create-btn').addEventListener('click', () => {
        const name = document.getElementById('mp-player-name').value.trim() || 'Player';
        mpSocket.emit('create_roulette_room', { player_name: name });
    });

    document.getElementById('mp-join-btn').addEventListener('click', () => {
        const name = document.getElementById('mp-player-name').value.trim() || 'Player';
        const code = document.getElementById('mp-room-code').value.trim().toUpperCase();
        if (!code) { alert('Enter a room code'); return; }
        mpSocket.emit('join_roulette_room', { player_name: name, room_code: code });
    });

    document.getElementById('mp-start-spin-btn').addEventListener('click', () => {
        lobby.classList.add('hidden');
        waiting.classList.add('hidden');
        mpGame.classList.remove('hidden');
        document.getElementById('mp-room-label').textContent = mpRoomCode;
    });

    document.getElementById('mp-spin-btn').addEventListener('click', () => {
        mpSocket.emit('spin_wheel', { room_code: mpRoomCode });
    });

    // Chip selection (multiplayer)
    document.querySelectorAll('.mp-chip').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.mp-chip').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            mpChipValue = parseInt(btn.dataset.value);
        });
    });

    // Bet buttons (multiplayer)
    document.querySelectorAll('.mp-bet-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            mpSocket.emit('place_bet', {
                room_code: mpRoomCode,
                bet_type: btn.dataset.type,
                bet_amount: mpChipValue
            });
        });
    });

    // ── Socket events ──────────────────────────────────────────────────────────

    mpSocket.on('roulette_room_created', data => {
        mpRoomCode = data.room_code;
        mpPlayerId = data.player_id;
        mpIsHost = true;
        lobby.classList.add('hidden');
        waiting.classList.remove('hidden');
        document.getElementById('mp-room-display').textContent = mpRoomCode;
        document.getElementById('mp-start-spin-btn').classList.remove('hidden');
        document.getElementById('mp-waiting-msg').textContent = 'Share this code with friends!';
        renderMpPlayers(data.players, waiting);
    });

    mpSocket.on('roulette_room_joined', data => {
        mpRoomCode = data.room_code;
        mpPlayerId = data.player_id;
        mpIsHost = false;
        lobby.classList.add('hidden');
        waiting.classList.remove('hidden');
        document.getElementById('mp-room-display').textContent = mpRoomCode;
        document.getElementById('mp-waiting-msg').textContent = 'Waiting for host to start…';
        renderMpPlayers(data.players, waiting);
    });

    mpSocket.on('roulette_player_joined', data => {
        renderMpPlayers(data.players, waiting);
    });

    mpSocket.on('roulette_player_left', data => {
        renderMpPlayers(data.players, waiting.classList.contains('hidden') ? mpGame : waiting);
    });

    mpSocket.on('bet_placed', data => {
        if (data.player_id === mpPlayerId) {
            document.getElementById('mp-my-chips').textContent = '$' + data.remaining_chips;
        }
        renderMpChipsBar(data.players);
    });

    mpSocket.on('wheel_result', data => {
        const colorEmoji = data.color === 'red' ? 'Red' : data.color === 'green' ? 'Green' : 'Black';
        const myResult = data.player_results[mpPlayerId];
        const banner = document.getElementById('mp-result-banner');

        if (myResult) {
            const net = myResult.won > 0 ? `+$${myResult.won}` : 'No win';
            banner.textContent = `${colorEmoji} Number ${data.result} (${data.color.toUpperCase()}) — ${net}`;
            banner.className = 'result-message ' + (myResult.won > 0 ? 'result-success' : 'result-error');
            banner.classList.remove('hidden');
            document.getElementById('mp-my-chips').textContent = '$' + myResult.chips;
            setTimeout(() => banner.classList.add('hidden'), 5000);
        }

        renderMpChipsBar(data.players);
    });

    mpSocket.on('roulette_error', data => {
        alert(data.message);
    });
}

function renderMpPlayers(players, container) {
    const list = container.id === 'multiplayer-waiting'
        ? document.getElementById('mp-players-list')
        : null;
    if (!list) return;
    list.innerHTML = '';
    players.forEach(p => {
        const row = document.createElement('div');
        row.className = 'mp-player-row';
        row.innerHTML = `<span>${p.name}${p.is_host ? ' (Host)' : ''}</span><span>$${p.chips}</span>`;
        list.appendChild(row);
    });
}

function renderMpChipsBar(players) {
    const bar = document.getElementById('mp-players-chips');
    if (!bar) return;
    bar.innerHTML = '';
    players.forEach(p => {
        const row = document.createElement('div');
        row.className = 'mp-chip-row';
        row.style.background = p.id === mpPlayerId ? '#0f3460' : '#1a1a2e';
        row.innerHTML = `<span>${p.name}</span><span>$${p.chips}</span>`;
        bar.appendChild(row);
    });
}
// ─── End multiplayer ─────────────────────────────────────────────────────────

function init() {
    try {
        console.log('🎰 Initializing Roulette Casino...');

        initMultiplayer();

        // Cache DOM elements
        modeSelection = document.getElementById('mode-selection');
        rouletteGame = document.getElementById('roulette-game');
        soloModeBtn = document.getElementById('solo-mode-btn');
        spinBtn = document.getElementById('spin-btn');
        clearBetsBtn = document.getElementById('clear-bets-btn');
        canvas = document.getElementById('roulette-canvas');
        ctx = canvas ? canvas.getContext('2d') : null;
        ball = document.getElementById('ball');
        
        // Set up event listeners with cleanup tracking
        if (soloModeBtn) {
            cleanup.addEventListener(soloModeBtn, 'click', startGame);
        }
        
        // Chip selection
        document.querySelectorAll('.chip-btn').forEach(btn => {
            cleanup.addEventListener(btn, 'click', () => selectChip(btn));
        });
        
        // Betting buttons
        document.querySelectorAll('.bet-btn').forEach(btn => {
            cleanup.addEventListener(btn, 'click', () => placeBet(btn));
        });
        
        if (spinBtn) {
            cleanup.addEventListener(spinBtn, 'click', spinWheel);
        }
        
        if (clearBetsBtn) {
            cleanup.addEventListener(clearBetsBtn, 'click', () => clearBets(true));
        }
        
        if (canvas) {
            drawWheel();
        }
        
        console.log('✅ Roulette Casino initialized with CleanupManager');
    } catch (error) {
        console.error('❌ Failed to initialize Roulette Casino:', error);
        showMessage('Failed to initialize game. Please refresh the page.', 'error');
    }
}

function startGame() {
    try {
        console.log('🎮 Starting Roulette Casino...');
        if (modeSelection) modeSelection.classList.add('hidden');
        if (rouletteGame) rouletteGame.classList.remove('hidden');
        updateDisplay();
    } catch (error) {
        console.error('❌ Failed to start game:', error);
        showMessage('Failed to start game. Please try again.', 'error');
    }
}

function selectChip(btn) {
    try {
        document.querySelectorAll('.chip-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        gameState.currentChipValue = parseInt(btn.dataset.value);
        console.log(`💎 Selected chip: $${gameState.currentChipValue}`);
    } catch (error) {
        console.error('❌ Failed to select chip:', error);
    }
}

function placeBet(btn) {
    try {
        if (gameState.isSpinning) {
            showMessage('⏳ Wait for the spin to complete!', 'warning');
            return;
        }
        
        const betType = btn.dataset.type;
        const chipValue = gameState.currentChipValue;
        
        if (gameState.totalMoney < chipValue) {
            showMessage('Not enough money!', 'error');
            return;
        }
        
        // Add bet
        if (!gameState.bets[betType]) {
            gameState.bets[betType] = 0;
        }
        gameState.bets[betType] += chipValue;
        gameState.totalMoney -= chipValue;
        
        // Update display
        updateDisplay();
        updateBetDisplay(betType);
        
        // Enable spin button
        if (spinBtn) {
            spinBtn.disabled = false;
            spinBtn.innerHTML = 'SPIN TO WIN!';
            spinBtn.classList.add('btn-spin-ready');
        }
        
        console.log(`💰 Bet placed: ${betType} - $${chipValue}`);
    } catch (error) {
        console.error('❌ Failed to place bet:', error);
        showMessage('Failed to place bet. Please try again.', 'error');
    }
}

function updateBetDisplay(betType) {
    try {
        const betAmountEl = document.querySelector(`[data-bet="${betType}"]`);
        if (betAmountEl) {
            betAmountEl.textContent = `$${gameState.bets[betType] || 0}`;
            betAmountEl.parentElement.classList.add('bet-active');
        }
    } catch (error) {
        console.error('❌ Failed to update bet display:', error);
    }
}

function clearBets(refund = true) {
    try {
        if (gameState.isSpinning) return;
        
        // Only refund if explicitly clearing (not after a spin)
        if (refund) {
            Object.values(gameState.bets).forEach(amount => {
                gameState.totalMoney += amount;
            });
        }
        
        gameState.bets = {};
        
        // Clear visual indicators
        document.querySelectorAll('.bet-amount').forEach(el => {
            el.textContent = '$0';
            el.parentElement.classList.remove('bet-active');
        });
        
        if (spinBtn) {
            spinBtn.disabled = true;
            spinBtn.innerHTML = 'Place Bets First';
            spinBtn.classList.remove('btn-spin-ready');
        }
        
        updateDisplay();
        console.log(refund ? '🗑️ All bets cleared and refunded' : '🗑️ Bets cleared for new round');
    } catch (error) {
        console.error('❌ Failed to clear bets:', error);
    }
}

function updateDisplay() {
    try {
        const totalMoneyEl = document.getElementById('total-money');
        const currentBetEl = document.getElementById('current-bet-display');
        const roundTotalEl = document.getElementById('round-total');
        
        if (totalMoneyEl) {
            totalMoneyEl.textContent = `$${gameState.totalMoney}`;
        }
        
        const totalBets = Object.values(gameState.bets).reduce((sum, val) => sum + val, 0);
        
        if (currentBetEl) {
            currentBetEl.textContent = `$${gameState.currentChipValue}`;
        }
        
        if (roundTotalEl) {
            roundTotalEl.textContent = `$${totalBets}`;
        }
    } catch (error) {
        console.error('❌ Failed to update display:', error);
    }
}

/**
 * Cache static wheel rendering for performance optimization
 * Only called once or when wheel needs to be regenerated
 */
function cacheWheelRendering() {
    try {
        if (!canvas) return;
        
        // Create offscreen canvas for caching
        cachedWheelCanvas = document.createElement('canvas');
        cachedWheelCanvas.width = canvas.width;
        cachedWheelCanvas.height = canvas.height;
        const cacheCtx = cachedWheelCanvas.getContext('2d');
        
        const centerX = canvas.width / 2;
        const centerY = canvas.height / 2;
        const radius = 220;
        
        // Draw outer rim
        cacheCtx.beginPath();
        cacheCtx.arc(centerX, centerY, radius + 20, 0, Math.PI * 2);
        cacheCtx.strokeStyle = '#00f5ff';
        cacheCtx.lineWidth = 4;
        cacheCtx.stroke();
        cacheCtx.fillStyle = '#0a0a0a';
        cacheCtx.fill();
        
        // Draw wheel segments
        const segmentAngle = (Math.PI * 2) / rouletteNumbers.length;
        
        rouletteNumbers.forEach((item, index) => {
            const startAngle = index * segmentAngle;
            const endAngle = startAngle + segmentAngle;
            
            // Draw segment
            cacheCtx.beginPath();
            cacheCtx.moveTo(centerX, centerY);
            cacheCtx.arc(centerX, centerY, radius, startAngle, endAngle);
            cacheCtx.closePath();
            
            // Fill color
            if (item.color === 'green') {
                cacheCtx.fillStyle = '#00ff00';
            } else if (item.color === 'red') {
                cacheCtx.fillStyle = '#ff0000';
            } else {
                cacheCtx.fillStyle = '#000000';
            }
            cacheCtx.fill();
            
            // Draw border
            cacheCtx.strokeStyle = '#FFD700';
            cacheCtx.lineWidth = 2;
            cacheCtx.stroke();
            
            // Draw number
            cacheCtx.save();
            cacheCtx.translate(centerX, centerY);
            cacheCtx.rotate(startAngle + segmentAngle / 2);
            cacheCtx.textAlign = 'center';
            cacheCtx.textBaseline = 'middle';
            cacheCtx.fillStyle = 'white';
            cacheCtx.font = 'bold 16px Arial';
            cacheCtx.fillText(item.num, radius * 0.75, 0);
            cacheCtx.restore();
        });
        
        // Draw center circle
        cacheCtx.beginPath();
        cacheCtx.arc(centerX, centerY, 40, 0, Math.PI * 2);
        cacheCtx.fillStyle = '#1a1a1a';
        cacheCtx.fill();
        cacheCtx.strokeStyle = '#00f5ff';
        cacheCtx.lineWidth = 3;
        cacheCtx.stroke();
        
        console.log('✅ Wheel rendering cached for performance');
    } catch (error) {
        console.error('❌ Failed to cache wheel rendering:', error);
    }
}

/**
 * Optimized drawWheel - uses cached rendering and rotation transform
 */
function drawWheel() {
    try {
        if (!ctx) return;
        
        // Create cache if doesn't exist
        if (!cachedWheelCanvas) {
            cacheWheelRendering();
        }
        
        const centerX = canvas.width / 2;
        const centerY = canvas.height / 2;
        
        // Clear canvas
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        // Save context state
        ctx.save();
        
        // Translate to center, rotate, then translate back
        ctx.translate(centerX, centerY);
        ctx.rotate(gameState.wheelRotation);
        ctx.translate(-centerX, -centerY);
        
        // Draw cached wheel
        ctx.drawImage(cachedWheelCanvas, 0, 0);
        
        // Restore context state
        ctx.restore();
    } catch (error) {
        console.error('❌ Failed to draw wheel:', error);
    }
}

function spinWheel() {
    try {
        if (gameState.isSpinning) return;
        
        const totalBets = Object.values(gameState.bets).reduce((sum, val) => sum + val, 0);
        if (totalBets === 0) {
            showMessage('Place your bets first!', 'warning');
            return;
        }
        
        gameState.isSpinning = true;
        if (spinBtn) {
            spinBtn.disabled = true;
            spinBtn.innerHTML = 'SPINNING...';
        }
        
        // Select winning number and calculate target rotation
        const winningIndex = Math.floor(Math.random() * rouletteNumbers.length);
        const winningNumber = rouletteNumbers[winningIndex];
        
        // Calculate rotation needed to land on winning segment
        const segmentAngle = (Math.PI * 2) / rouletteNumbers.length;
        const extraSpins = 5; // Number of full rotations before stopping
        
        const targetAngle = (Math.PI * 2 * extraSpins) - (winningIndex * segmentAngle) - (segmentAngle / 2) + (Math.PI / 2);
        const startRotation = gameState.wheelRotation % (Math.PI * 2);
        const targetRotation = startRotation + targetAngle;
        
        const duration = 5000;
        const startTime = Date.now();
        
        function animate() {
            try {
                const elapsed = Date.now() - startTime;
                const progress = Math.min(elapsed / duration, 1);
                
                // Easing function (ease-out cubic)
                const easeOut = 1 - Math.pow(1 - progress, 3);
                
                // Update wheel rotation
                const currentRotation = startRotation + (targetAngle * easeOut);
                gameState.wheelRotation = currentRotation;
                
                // Redraw wheel
                drawWheel();
                
                // Update ball position to match wheel rotation
                updateBallPosition(currentRotation);
                
                if (progress < 1) {
                    animationFrameId = requestAnimationFrame(animate);
                } else {
                    // Normalize final rotation
                    gameState.wheelRotation = currentRotation % (Math.PI * 2);
                    drawWheel();
                    finishSpin(winningNumber);
                    animationFrameId = null;
                }
            } catch (error) {
                console.error('❌ Animation error:', error);
                gameState.isSpinning = false;
                if (spinBtn) {
                    spinBtn.disabled = false;
                    spinBtn.innerHTML = 'SPIN TO WIN!';
                }
            }
        }
        
        animate();
    } catch (error) {
        console.error('❌ Failed to spin wheel:', error);
        showMessage('Failed to spin wheel. Please try again.', 'error');
        gameState.isSpinning = false;
        if (spinBtn) {
            spinBtn.disabled = false;
            spinBtn.innerHTML = 'SPIN TO WIN!';
        }
    }
}

function updateBallPosition(currentRotation) {
    try {
        if (!ball) return;
        
        const ballRadius = 180; // Distance from center
        
        // Ball moves opposite to wheel rotation
        const ballAngle = -currentRotation + Math.PI / 2; // Adjust starting position
        
        const x = Math.cos(ballAngle) * ballRadius;
        const y = Math.sin(ballAngle) * ballRadius;
        
        ball.style.left = `calc(50% + ${x}px)`;
        ball.style.top = `calc(50% + ${y}px)`;
    } catch (error) {
        console.error('❌ Failed to update ball position:', error);
    }
}

function finishSpin(winningNumber) {
    try {
        gameState.isSpinning = false;
        
        // Display winning number
        const winningNumEl = document.getElementById('winning-number');
        if (winningNumEl) {
            winningNumEl.textContent = winningNumber.num;
            winningNumEl.style.color = 
                winningNumber.color === 'red' ? '#ff0000' : 
                winningNumber.color === 'green' ? '#00ff00' : '#ffffff';
        }
        
        // Calculate winnings
        let totalWin = 0;
        const results = [];
        
        Object.entries(gameState.bets).forEach(([betType, amount]) => {
            const won = checkBet(betType, winningNumber.num, winningNumber.color);
            if (won) {
                const payout = getBetPayout(betType);
                const winAmount = amount * payout;
                totalWin += winAmount;
                results.push(`${betType}: +$${winAmount}`);
            }
        });
        
        // Add winnings to total money
        gameState.totalMoney += totalWin;
        
        // Show result
        const totalBet = Object.values(gameState.bets).reduce((sum, val) => sum + val, 0);
        const netResult = totalWin - totalBet;
        
        let resultMessage = `Number: ${winningNumber.num} (${winningNumber.color.toUpperCase()})\n\n`;
        
        if (netResult > 0) {
            resultMessage += `YOU WON $${netResult}!`;
            if (results.length > 0) {
                resultMessage += `\n\nWinning Bets:\n${results.join('\n')}`;
            }
            showMessage(resultMessage, 'success');
        } else if (netResult < 0) {
            resultMessage += `You lost $${Math.abs(netResult)}`;
            showMessage(resultMessage, 'error');
        } else {
            resultMessage += `Break even!`;
            showMessage(resultMessage, 'info');
        }
        
        // Reset for next round (don't refund - bets were already deducted!)
        clearBets(false);
        updateDisplay();
        
        console.log(`🎲 Result: ${winningNumber.num} (${winningNumber.color}) - Net: $${netResult}`);
    } catch (error) {
        console.error('❌ Failed to finish spin:', error);
        showMessage('Failed to process game result. Please refresh the page.', 'error');
    }
}

function checkBet(betType, number, color) {
    switch(betType) {
        case 'red': return color === 'red';
        case 'black': return color === 'black';
        case 'zero': return number === 0;
        case 'even': return number !== 0 && number % 2 === 0;
        case 'odd': return number !== 0 && number % 2 === 1;
        case 'low': return number >= 1 && number <= 18;
        case 'high': return number >= 19 && number <= 36;
        case 'first12': return number >= 1 && number <= 12;
        case 'second12': return number >= 13 && number <= 24;
        case 'third12': return number >= 25 && number <= 36;
        default: return false;
    }
}

function getBetPayout(betType) {
    const payouts = {
        'red': 2, 'black': 2, 'zero': 36,
        'even': 2, 'odd': 2,
        'low': 2, 'high': 2,
        'first12': 3, 'second12': 3, 'third12': 3
    };
    return payouts[betType] || 1;
}

function showMessage(text, type) {
    try {
        const messageEl = document.getElementById('result-message');
        if (messageEl) {
            messageEl.textContent = text;
            messageEl.className = `result-message result-${type}`;
            messageEl.classList.remove('hidden');
            
            setTimeout(() => {
                messageEl.classList.add('hidden');
            }, 6000);
        }
    } catch (error) {
        console.error('❌ Failed to show message:', error);
    }
}

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    console.log('Roulette: Cleaning up resources...');
    
    // Cancel any pending animation frame
    if (animationFrameId) {
        cancelAnimationFrame(animationFrameId);
        animationFrameId = null;
    }
    
    // Clean up event listeners
    cleanup.cleanup();
});

console.log('✅ Roulette Casino script loaded with CleanupManager');
