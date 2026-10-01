// Socket.IO connection
const socket = io();

// Initialize cleanup manager for proper memory management
const cleanup = new CleanupManager();

// Game State
let gameState = {
    mode: null, // 'solo' or 'multiplayer'
    roomCode: null,
    isHost: false,
    players: [],
    topic: '',
    difficulty: 'easy',
    questionCount: 5,
    currentQuestion: 0,
    score: 0,
    correctAnswers: 0,
    wrongAnswers: 0,
    skippedAnswers: 0,
    questions: [],
    startTime: null,
    timer: null,
    timeLeft: 30
};

// DOM Elements
const modeSelection = document.getElementById('mode-selection');
const multiplayerLobby = document.getElementById('multiplayer-lobby');
const waitingRoom = document.getElementById('waiting-room');
const topicSelection = document.getElementById('topic-selection');
const loadingScreen = document.getElementById('loading-screen');
const gameScreen = document.getElementById('game-screen');
const resultsScreen = document.getElementById('results-screen');

// Wait for DOM to be ready
cleanup.addEventListener(document, 'DOMContentLoaded', function() {
    console.log('Trivia game initialized');
    
    // Mode Selection
    const soloModeBtn = document.getElementById('solo-mode-btn');
    const multiplayerModeBtn = document.getElementById('multiplayer-mode-btn');
    
    if (soloModeBtn) {
        cleanup.addEventListener(soloModeBtn, 'click', () => {
            console.log('Solo mode selected');
            gameState.mode = 'solo';
            modeSelection.classList.add('hidden');
            topicSelection.classList.remove('hidden');
        });
    }
    
    if (multiplayerModeBtn) {
        cleanup.addEventListener(multiplayerModeBtn, 'click', () => {
            console.log('Multiplayer mode selected');
            gameState.mode = 'multiplayer';
            modeSelection.classList.add('hidden');
            multiplayerLobby.classList.remove('hidden');
            loadRooms();
        });
    }
    
    // Back buttons
    const backToModeBtn = document.getElementById('back-to-mode-btn');
    if (backToModeBtn) {
        cleanup.addEventListener(backToModeBtn, 'click', () => {
            multiplayerLobby.classList.add('hidden');
            modeSelection.classList.remove('hidden');
        });
    }
    
    const backToModeSoloBtn = document.getElementById('back-to-mode-solo-btn');
    if (backToModeSoloBtn) {
        cleanup.addEventListener(backToModeSoloBtn, 'click', () => {
            topicSelection.classList.add('hidden');
            modeSelection.classList.remove('hidden');
        });
    }
    
    // Create Room
    const createRoomBtn = document.getElementById('create-room-btn');
    if (createRoomBtn) {
        cleanup.addEventListener(createRoomBtn, 'click', () => {
            console.log('Creating room...');
            const playerName = getUserName();
            socket.emit('create_trivia_room', { player_name: playerName });
        });
    }
    
    // Join Room
    const joinRoomBtn = document.getElementById('join-room-btn');
    if (joinRoomBtn) {
        cleanup.addEventListener(joinRoomBtn, 'click', () => {
            const roomCode = document.getElementById('room-code-input').value.toUpperCase();
            const playerName = getUserName();
            
            if (roomCode) {
                console.log('Joining room:', roomCode);
                socket.emit('join_trivia_room', { room_code: roomCode, player_name: playerName });
            } else {
                alert('Please enter a room code');
            }
        });
    }
    
    // Refresh Rooms
    const refreshRoomsBtn = document.getElementById('refresh-rooms-btn');
    if (refreshRoomsBtn) {
        cleanup.addEventListener(refreshRoomsBtn, 'click', loadRooms);
    }
    
    // Leave Room
    const leaveRoomBtn = document.getElementById('leave-room-btn');
    if (leaveRoomBtn) {
        cleanup.addEventListener(leaveRoomBtn, 'click', () => {
            if (gameState.roomCode) {
                socket.emit('leave_trivia_room', { room_code: gameState.roomCode });
            }
            waitingRoom.classList.add('hidden');
            multiplayerLobby.classList.remove('hidden');
            loadRooms();
        });
    }
    
    // Start Multiplayer Game
    const startMultiplayerBtn = document.getElementById('start-multiplayer-btn');
    if (startMultiplayerBtn) {
        cleanup.addEventListener(startMultiplayerBtn, 'click', () => {
            const settings = {
                room_code: gameState.roomCode,
                topic: document.getElementById('waiting-topic').value,
                difficulty: document.getElementById('waiting-difficulty').value,
                question_count: parseInt(document.getElementById('waiting-questions').value)
            };
            
            console.log('Starting game with settings:', settings);
            socket.emit('start_trivia_game', settings);
        });
    }
    
    // Copy Room Code
    const copyCodeBtn = document.getElementById('copy-code-btn');
    if (copyCodeBtn) {
        cleanup.addEventListener(copyCodeBtn, 'click', () => {
            const code = document.getElementById('waiting-room-code').textContent;
            navigator.clipboard.writeText(code).then(() => {
                copyCodeBtn.textContent = 'Copied!';
                setTimeout(() => {
                    copyCodeBtn.textContent = 'Copy';
                }, 2000);
            });
        });
    }
    
    // Solo Mode Setup
    const topicDropdown = document.getElementById('topic-dropdown');
    const startGameBtn = document.getElementById('start-game-btn');
    const difficultyBtns = document.querySelectorAll('.difficulty-btn');
    const questionCountInput = document.getElementById('question-count');
    
    if (topicDropdown) {
        cleanup.addEventListener(topicDropdown, 'change', function() {
            startGameBtn.disabled = this.value === '';
        });
    }
    
    if (difficultyBtns.length > 0) {
        difficultyBtns.forEach(btn => {
            cleanup.addEventListener(btn, 'click', function() {
                difficultyBtns.forEach(b => b.classList.remove('active'));
                this.classList.add('active');
                gameState.difficulty = this.dataset.difficulty;
            });
        });
    }
    
    if (startGameBtn) {
        cleanup.addEventListener(startGameBtn, 'click', startSoloGame);
    }
    
    const skipQuestionBtn = document.getElementById('skip-question-btn');
    if (skipQuestionBtn) {
        cleanup.addEventListener(skipQuestionBtn, 'click', skipQuestion);
    }
    
    const playAgainBtn = document.getElementById('play-again-btn');
    if (playAgainBtn) {
        cleanup.addEventListener(playAgainBtn, 'click', playAgain);
    }
    
    const changeTopicBtn = document.getElementById('change-topic-btn');
    if (changeTopicBtn) {
        cleanup.addEventListener(changeTopicBtn, 'click', changeTopic);
    }
});

// Socket.IO Events
cleanup.addSocketListener(socket, 'connect', () => {
    console.log('Connected to server');
});

cleanup.addSocketListener(socket, 'room_created', (data) => {
    console.log('Room created:', data);
    gameState.roomCode = data.room_code;
    gameState.isHost = true;
    multiplayerLobby.classList.add('hidden');
    waitingRoom.classList.remove('hidden');
    document.getElementById('waiting-room-code').textContent = data.room_code;
    document.getElementById('host-controls').classList.remove('hidden');
    document.getElementById('start-multiplayer-btn').classList.remove('hidden');
    document.getElementById('waiting-status').textContent = 'You are the host. Configure settings and start when ready!';
    updatePlayersList(data.players);
});

cleanup.addSocketListener(socket, 'room_joined', (data) => {
    console.log('Room joined:', data);
    gameState.roomCode = data.room_code;
    gameState.isHost = false;
    multiplayerLobby.classList.add('hidden');
    waitingRoom.classList.remove('hidden');
    document.getElementById('waiting-room-code').textContent = data.room_code;
    document.getElementById('host-controls').classList.add('hidden');
    document.getElementById('start-multiplayer-btn').classList.add('hidden');
    document.getElementById('waiting-status').textContent = 'Waiting for host to start the game...';
    updatePlayersList(data.players);
});

cleanup.addSocketListener(socket, 'player_joined', (data) => {
    console.log('Player joined:', data);
    updatePlayersList(data.players);
});

cleanup.addSocketListener(socket, 'player_left', (data) => {
    console.log('Player left:', data);
    updatePlayersList(data.players);
});

cleanup.addSocketListener(socket, 'game_starting', (data) => {
    console.log('Game starting:', data);
    gameState.topic = data.topic;
    gameState.difficulty = data.difficulty;
    gameState.questionCount = data.question_count;
    gameState.questions = data.questions;
    gameState.currentQuestion = 0;
    gameState.score = 0;
    gameState.correctAnswers = 0;
    gameState.wrongAnswers = 0;
    gameState.skippedAnswers = 0;
    gameState.startTime = Date.now();
    
    waitingRoom.classList.add('hidden');
    gameScreen.classList.remove('hidden');
    const liveLeaderboard = document.getElementById('live-leaderboard');
    if (liveLeaderboard) {
        liveLeaderboard.classList.remove('hidden');
    }
    displayQuestion();
});

cleanup.addSocketListener(socket, 'score_update', (data) => {
    console.log('Score update:', data);
    updateLiveLeaderboard(data.scores);
});

cleanup.addSocketListener(socket, 'game_ended', (data) => {
    console.log('Game ended:', data);
    showMultiplayerResults(data.final_scores);
});

cleanup.addSocketListener(socket, 'rooms_list', (data) => {
    console.log('Rooms list:', data);
    displayRooms(data.rooms);
});

cleanup.addSocketListener(socket, 'error', (data) => {
    console.error('Socket error:', data);
    alert(data.message);
});

cleanup.addSocketListener(socket, 'disconnect', () => {
    console.log('Disconnected from server');
});

// Helper Functions
function getUserName() {
    // Try to get user from session
    const userDataElement = document.querySelector('[data-user]');
    if (userDataElement) {
        try {
            const user = JSON.parse(userDataElement.dataset.user);
            return user.first_name || user.name || 'Player';
        } catch (e) {
            console.error('Error parsing user data:', e);
        }
    }
    
    // Fallback to prompt
    let name = prompt('Enter your name:');
    return name || 'Player';
}

function loadRooms() {
    console.log('Loading rooms...');
    socket.emit('get_trivia_rooms');
}

function displayRooms(rooms) {
    const roomsList = document.getElementById('rooms-list');
    
    if (!roomsList) return;
    
    if (rooms.length === 0) {
        roomsList.innerHTML = '<div class="empty-rooms">No active rooms. Create one!</div>';
        return;
    }
    
    roomsList.innerHTML = rooms.map(room => `
        <div class="room-item" onclick="joinRoomFromList('${room.code}')">
            <div class="room-code">${room.code}</div>
            <div class="room-info">
                <span class="room-players">${room.player_count}/4</span>
                <span class="room-status">${room.status}</span>
            </div>
        </div>
    `).join('');
}

function joinRoomFromList(roomCode) {
    document.getElementById('room-code-input').value = roomCode;
    document.getElementById('join-room-btn').click();
}

function updatePlayersList(players) {
    gameState.players = players;
    const playersList = document.getElementById('players-list');
    const playerCount = document.getElementById('player-count');
    
    if (!playersList || !playerCount) return;
    
    playerCount.textContent = players.length;
    
    playersList.innerHTML = players.map((player, index) => `
        <div class="player-item ${player.is_host ? 'host' : ''}">
            <span class="player-number">${index + 1}</span>
            <span class="player-name">${player.name}</span>
            ${player.is_host ? '<span class="host-badge">Host</span>' : ''}
            <span class="player-status">Ready</span>
        </div>
    `).join('');
}

function updateLiveLeaderboard(scores) {
    const leaderboard = document.getElementById('leaderboard-list');
    if (!leaderboard) return;
    
    const sortedScores = Object.entries(scores).sort((a, b) => b[1] - a[1]);
    
    leaderboard.innerHTML = sortedScores.map(([name, score], index) => `
        <div class="leaderboard-item">
            <span class="rank">${index + 1}</span>
            <span class="player-name">${name}</span>
            <span class="score">${score}</span>
        </div>
    `).join('');
}

async function startSoloGame() {
    const topicDropdown = document.getElementById('topic-dropdown');
    const questionCountInput = document.getElementById('question-count');
    
    gameState.topic = topicDropdown.value;
    gameState.questionCount = parseInt(questionCountInput.value);
    gameState.currentQuestion = 0;
    gameState.score = 0;
    gameState.correctAnswers = 0;
    gameState.wrongAnswers = 0;
    gameState.skippedAnswers = 0;
    gameState.startTime = Date.now();
    
    topicSelection.classList.add('hidden');
    loadingScreen.classList.remove('hidden');
    
    try {
        const response = await fetch('/trivia/generate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                topic: gameState.topic,
                difficulty: gameState.difficulty,
                count: gameState.questionCount
            })
        });
        
        const data = await response.json();
        
        if (data.success) {
            gameState.questions = data.questions;
            setTimeout(() => {
                loadingScreen.classList.add('hidden');
                gameScreen.classList.remove('hidden');
                displayQuestion();
            }, 1500);
        } else {
            alert('Error generating questions: ' + data.error);
            loadingScreen.classList.add('hidden');
            topicSelection.classList.remove('hidden');
        }
    } catch (error) {
        console.error('Error:', error);
        alert('Failed to generate questions. Please try again.');
        loadingScreen.classList.add('hidden');
        topicSelection.classList.remove('hidden');
    }
}

function displayQuestion() {
    const question = gameState.questions[gameState.currentQuestion];
    
    document.getElementById('current-question').textContent = gameState.currentQuestion + 1;
    document.getElementById('total-questions').textContent = gameState.questionCount;
    document.getElementById('current-score').textContent = gameState.score;
    document.getElementById('question-topic').textContent = gameState.topic;
    document.getElementById('question-text').textContent = question.question;
    
    const progress = ((gameState.currentQuestion) / gameState.questionCount) * 100;
    document.getElementById('progress-fill').style.width = progress + '%';
    
    const answersGrid = document.getElementById('answers-grid');
    answersGrid.innerHTML = '';
    
    question.options.forEach((option, index) => {
        const answerBtn = document.createElement('button');
        answerBtn.className = 'answer-btn';
        answerBtn.textContent = option;
        cleanup.addEventListener(answerBtn, 'click', () => selectAnswer(index));
        answersGrid.appendChild(answerBtn);
    });
    
    startTimer();
}

function startTimer() {
    gameState.timeLeft = 30;
    updateTimerDisplay();
    
    gameState.timer = setInterval(() => {
        gameState.timeLeft--;
        updateTimerDisplay();
        
        if (gameState.timeLeft <= 0) {
            clearInterval(gameState.timer);
            skipQuestion();
        }
    }, 1000);
}

function updateTimerDisplay() {
    const timerEl = document.getElementById('timer');
    if (!timerEl) return;
    
    timerEl.textContent = gameState.timeLeft;
    timerEl.classList.toggle('warning', gameState.timeLeft <= 10);
}

function selectAnswer(selectedIndex) {
    clearInterval(gameState.timer);
    
    const question = gameState.questions[gameState.currentQuestion];
    const answerBtns = document.querySelectorAll('.answer-btn');
    
    answerBtns.forEach((btn, index) => {
        btn.disabled = true;
        if (index === question.correct_answer) {
            btn.classList.add('correct');
        } else if (index === selectedIndex) {
            btn.classList.add('wrong');
        }
    });
    
    if (selectedIndex === question.correct_answer) {
        gameState.score += 10;
        gameState.correctAnswers++;
    } else {
        gameState.wrongAnswers++;
    }
    
    if (gameState.mode === 'multiplayer') {
        socket.emit('answer_submitted', {
            room_code: gameState.roomCode,
            score: gameState.score
        });
    }
    
    setTimeout(nextQuestion, 2000);
}

function skipQuestion() {
    clearInterval(gameState.timer);
    gameState.skippedAnswers++;
    
    const question = gameState.questions[gameState.currentQuestion];
    const answerBtns = document.querySelectorAll('.answer-btn');
    
    answerBtns.forEach((btn, index) => {
        btn.disabled = true;
        if (index === question.correct_answer) {
            btn.classList.add('correct');
        }
    });
    
    setTimeout(nextQuestion, 1500);
}

function nextQuestion() {
    gameState.currentQuestion++;
    
    if (gameState.currentQuestion < gameState.questionCount) {
        displayQuestion();
    } else {
        if (gameState.mode === 'multiplayer') {
            socket.emit('game_finished', { room_code: gameState.roomCode });
        } else {
            showResults();
        }
    }
}

function showResults() {
    gameScreen.classList.add('hidden');
    resultsScreen.classList.remove('hidden');
    
    const timeTaken = Math.floor((Date.now() - gameState.startTime) / 1000);
    const percentage = (gameState.correctAnswers / gameState.questionCount) * 100;
    
    document.getElementById('final-score').textContent = gameState.score;
    document.getElementById('max-score').textContent = gameState.questionCount * 10;
    document.getElementById('correct-answers').textContent = gameState.correctAnswers;
    document.getElementById('wrong-answers').textContent = gameState.wrongAnswers;
    document.getElementById('skipped-answers').textContent = gameState.skippedAnswers;
    document.getElementById('time-taken').textContent = timeTaken + 's';
    
    let message = '';
    let icon = '';
    
    if (percentage >= 90) {
        message = 'Outstanding! You\'re a trivia master!';
        icon = '';
    } else if (percentage >= 70) {
        message = 'Great job! Very impressive performance!';
        icon = '';
    } else if (percentage >= 50) {
        message = 'Good effort! Keep practicing!';
        icon = '';
    } else {
        message = 'Keep learning! You\'ll do better next time!';
        icon = '';
    }
    
    document.getElementById('result-icon').textContent = icon;
    document.getElementById('performance-message').textContent = message;
}

function showMultiplayerResults(finalScores) {
    gameScreen.classList.add('hidden');
    resultsScreen.classList.remove('hidden');
    
    const finalLeaderboard = document.getElementById('final-leaderboard');
    if (finalLeaderboard) {
        finalLeaderboard.classList.remove('hidden');
    }
    
    const sortedScores = Object.entries(finalScores).sort((a, b) => b[1] - a[1]);
    const rankings = document.getElementById('final-rankings');
    
    if (rankings) {
        rankings.innerHTML = sortedScores.map(([name, score], index) => {
            let medal = '';
            if (index === 0) medal = '1st';
            else if (index === 1) medal = '2nd';
            else if (index === 2) medal = '3rd';
            
            return `
                <div class="ranking-item ${index === 0 ? 'winner' : ''}">
                    <span class="rank">${medal || (index + 1)}</span>
                    <span class="player-name">${name}</span>
                    <span class="final-score">${score} pts</span>
                </div>
            `;
        }).join('');
    }
    
    const playerName = getUserName();
    const playerScore = finalScores[playerName] || 0;
    document.getElementById('final-score').textContent = playerScore;
}

function playAgain() {
    resultsScreen.classList.add('hidden');
    if (gameState.mode === 'solo') {
        topicSelection.classList.remove('hidden');
    } else {
        modeSelection.classList.remove('hidden');
    }
}

function changeTopic() {
    resultsScreen.classList.add('hidden');
    modeSelection.classList.remove('hidden');
}

// Global function for clicking on room items

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    cleanup.cleanup();
    if (socket && socket.connected) {
        socket.disconnect();
    }
});
window.joinRoomFromList = joinRoomFromList;