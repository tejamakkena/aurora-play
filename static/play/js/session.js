/* Aurora Play web controller: the session state machine.
 *
 * A port of ControllerRootViewModel (ios/GameLabController/App/
 * RootControllerView.swift): same screens, same transitions, same events.
 *
 *   join -> loading -> waiting -> rules -> playing -> results -> (waiting|playing)
 *
 * The seat id the server hands back in room_joined replaces the device id for
 * everything this browser sends afterwards (two tabs on one browser share a
 * device id; the server seats the second one separately as "<id>-2").
 */
(function () {
  'use strict';
  var AP = window.AP;

  var NAME_KEY = 'aurora_player_name';
  var LAST_ROOM_KEY = 'aurora_last_room_code';
  var LAST_ROOM_AT_KEY = 'aurora_last_room_at';
  var RESUME_WINDOW_MS = 3 * 60 * 60 * 1000;
  var JOIN_TIMEOUT_MS = 8000;

  var S = AP.S = {
    screen: 'join',          // join | loading | error | waiting | rules | playing | results
    errorMessage: '',
    room: null,
    rules: null,
    privateData: {},
    playerID: '',
    pendingJoinCode: '',
    resumableRoomCode: null,
    readyLocal: false,
    serverUp: false
  };

  var joinTimer = null;
  var renderQueued = false;
  var renderFn = function () {};

  function changed() {
    if (renderQueued) { return; }
    renderQueued = true;
    window.requestAnimationFrame(function () {
      renderQueued = false;
      renderFn();
    });
  }
  AP.changed = changed;
  AP.setRenderer = function (fn) { renderFn = fn; };

  function setScreen(next) {
    if (S.screen !== next) {
      if (next === 'waiting') { S.readyLocal = false; }
      S.screen = next;
    }
  }

  function playerName() { return AP.store(NAME_KEY) || ''; }

  function loadResumable() {
    var code = AP.store(LAST_ROOM_KEY);
    var at = parseFloat(AP.store(LAST_ROOM_AT_KEY) || '0');
    if (code && code.length === 6 && at > 0 && Date.now() - at < RESUME_WINDOW_MS) { return code; }
    return null;
  }
  function rememberRoom(code) {
    AP.store(LAST_ROOM_KEY, code);
    AP.store(LAST_ROOM_AT_KEY, String(Date.now()));
    S.resumableRoomCode = null;
  }
  function forgetResumable(ifCode) {
    if (ifCode && AP.store(LAST_ROOM_KEY) !== ifCode) { return; }
    AP.store(LAST_ROOM_KEY, null);
    AP.store(LAST_ROOM_AT_KEY, null);
    S.resumableRoomCode = null;
  }

  function currentRoom() {
    return (S.screen === 'waiting' || S.screen === 'rules' || S.screen === 'playing' || S.screen === 'results')
      ? S.room : null;
  }
  AP.currentRoom = currentRoom;

  AP.isHost = function () {
    var r = currentRoom();
    if (!r) { return false; }
    for (var i = 0; i < r.players.length; i++) {
      if (r.players[i].id === S.playerID) { return !!r.players[i].isHost; }
    }
    return false;
  };

  function cancelJoinTimer() { if (joinTimer) { clearTimeout(joinTimer); joinTimer = null; } }

  var A = AP.act = {};

  A.joinRoom = function (code, name) {
    var upper = String(code).toUpperCase();
    AP.store(NAME_KEY, name);
    S.rules = null;
    S.playerID = AP.deviceID();
    S.pendingJoinCode = upper;
    setScreen('loading');
    AP.net.emit('join_room', { roomCode: upper, playerName: name, playerID: S.playerID, isTV: false });
    cancelJoinTimer();
    joinTimer = setTimeout(function () {
      if (S.screen === 'loading') {
        forgetResumable(upper);
        S.errorMessage = "Couldn't join. Check the room code and try again.";
        setScreen('error');
        AP.haptic.error();
        changed();
      }
    }, JOIN_TIMEOUT_MS);
    changed();
  };

  A.markReady = function () {
    if (S.screen !== 'waiting') { return; }
    S.readyLocal = true;
    AP.net.emit('player_ready', { roomCode: S.room.code, playerID: S.playerID });
    changed();
  };

  A.beginGame = function () {
    var r = currentRoom();
    if (!r) { return; }
    AP.net.emit('begin_game', { roomCode: r.code, playerID: S.playerID });
  };

  A.playAgain = function () {
    if (S.screen !== 'results') { return; }
    S.rules = null;
    AP.net.emit('start_game', { roomCode: S.room.code });
  };

  A.sendAction = function (action, data) {
    if (S.screen !== 'playing') { return; }
    AP.net.emit('game_action', {
      roomCode: S.room.code, playerID: S.playerID, action: action, data: data || {}
    });
  };

  A.leaveRoom = function () {
    var r = currentRoom();
    if (r) {
      if (S.screen !== 'results') {
        AP.net.emit('leave_room', { roomCode: r.code, playerID: S.playerID });
      }
      forgetResumable(r.code);
    }
    S.rules = null;
    S.room = null;
    S.privateData = {};
    setScreen('join');
    changed();
  };

  A.returnToJoin = function () {
    S.rules = null;
    setScreen('join');
    changed();
  };
  A.returnHome = function () {
    cancelJoinTimer();
    S.rules = null;
    S.pendingJoinCode = '';
    setScreen('join');
    changed();
  };

  A.resumeTVGame = function () {
    var code = S.resumableRoomCode;
    if (!code) { return; }
    var name = playerName().trim();
    if (!name) { S.pendingJoinCode = code; changed(); return; }
    A.joinRoom(code, name);
  };

  // ---- lobby controls ------------------------------------------------
  A.addBot = function () { var r = currentRoom(); if (r) { AP.net.emit('add_bot', { roomCode: r.code }); } };
  A.removeBot = function (id) { var r = currentRoom(); if (r) { AP.net.emit('remove_bot', { roomCode: r.code, botID: id }); } };
  A.setContentPack = function (p) { var r = currentRoom(); if (r) { AP.net.emit('set_content_pack', { roomCode: r.code, contentPack: p }); } };
  A.setTeams = function (count) {
    var r = currentRoom(); if (!r) { return; }
    if (count < 2) { AP.net.emit('clear_teams', { roomCode: r.code }); }
    else { AP.net.emit('set_teams', { roomCode: r.code, count: count }); }
  };
  A.moveToTeam = function (teamID) {
    var r = currentRoom(); if (!r) { return; }
    AP.net.emit('move_to_team', { roomCode: r.code, playerID: S.playerID, teamID: teamID });
  };

  // ---- wiring --------------------------------------------------------
  AP.session = {
    start: function (prefillCode) {
      S.playerID = AP.deviceID();
      S.resumableRoomCode = loadResumable();
      if (prefillCode) { S.pendingJoinCode = String(prefillCode).toUpperCase().slice(0, 6); }
      AP.net.connect();
      AP.net.onStatus(function (up) { S.serverUp = up; changed(); });
      AP.net.onConnected(function () {
        // A reconnect gets a fresh socket id that is in no room: re-seat.
        var r = currentRoom();
        if (r) {
          AP.net.emit('join_room', {
            roomCode: r.code, playerName: playerName() || 'Player',
            playerID: S.playerID, isTV: false
          });
        }
      });

      AP.net.on('room_joined', function (resp) {
        cancelJoinTimer();
        S.pendingJoinCode = '';
        var room = resp.room;
        if (resp.playerID) { S.playerID = resp.playerID; }
        rememberRoom(room.code);
        S.room = room;
        if (room.state === 'playing' && S.screen === 'playing') {
          // reconnect mid-game: stay on the controller
        } else if (room.state === 'results') {
          setScreen('results');
        } else {
          setScreen('waiting');
        }
        changed();
      });

      AP.net.on('room_updated', function (room) {
        if (!room || (S.room && room.code !== S.room.code)) { return; }
        if (room.state === 'lobby') {
          if (S.screen === 'waiting' || S.screen === 'results') { S.room = room; setScreen('waiting'); }
        } else if (room.state === 'results') {
          if (S.screen === 'waiting' || S.screen === 'rules' || S.screen === 'playing' || S.screen === 'results') {
            S.room = room; setScreen('results');
          }
        } else if (currentRoom()) {
          S.room = room;
        }
        changed();
      });

      AP.net.on('game_started', function (resp) {
        S.rules = resp.rules;
        if (S.screen === 'waiting' || S.screen === 'results') { setScreen('rules'); }
        changed();
      });

      AP.net.on('game_begun', function () {
        S.rules = null;
        if (S.screen === 'rules') { setScreen('waiting'); }
        changed();
      });

      AP.net.on('private_state', function (r) {
        if (!r || r.playerID !== S.playerID) { return; }
        if (S.screen === 'waiting' || S.screen === 'playing' || S.screen === 'results') {
          S.privateData = r.privateData || {};
          setScreen('playing');
          if (AP.onPrivateState) { AP.onPrivateState(); }
          changed();
        }
      });

      AP.net.on('error', function (r) {
        cancelJoinTimer();
        if (S.screen === 'loading') {
          if (S.pendingJoinCode) { forgetResumable(S.pendingJoinCode); }
          S.errorMessage = (r && r.message) || 'Something went wrong.';
          setScreen('error');
          AP.haptic.error();
          changed();
        }
      });
    }
  };
})();
