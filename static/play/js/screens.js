/* Aurora Play web controller: join, loading, error, rules and results.
 *
 * Ports of JoinRoomView, LoadingJoinView, ErrorJoinView, RulesInterstitialView
 * (.card layout) and ResultsControllerView from the iOS app.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, S = AP.S, A = AP.act;

  var TV_COLORS = [C.cyan, C.indigo];
  var join = { code: '', name: '', shake: false, seeded: false, focusDone: false };

  // ---- Join ---------------------------------------------------------------

  function canJoin() { return join.code.length === 6 && join.name.trim().length > 0; }

  function attemptJoin() {
    if (!canJoin()) {
      AP.haptic.warning();
      join.shake = true;
      AP.changed();
      setTimeout(function () { join.shake = false; AP.changed(); }, 500);
      return;
    }
    if (document.activeElement && document.activeElement.blur) { document.activeElement.blur(); }
    AP.haptic.success();
    A.joinRoom(join.code, join.name.trim());
  }

  AP.screens = {};

  AP.screens.join = function () {
    if (!join.seeded) {
      join.seeded = true;
      join.name = AP.store('aurora_player_name') || '';
    }
    if (S.pendingJoinCode && S.pendingJoinCode !== join.lastPending) {
      join.code = S.pendingJoinCode;
      join.lastPending = S.pendingJoinCode;
    }

    var resume = S.resumableRoomCode;

    var top = h('div', { class: 'topbar', style: { justifyContent: 'flex-end' } },
      h('div', { class: 'status-pill' },
        h('span', { class: 'dot' + (S.serverUp ? '' : ' bad') }),
        S.serverUp ? 'Server connected' : 'Reconnecting...'));

    var header = h('div', { class: 'col center gap10 pop-in' },
      h('div', { class: 'badge-tile', style: { width: '92px', height: '92px' } },
        h('span', { class: 'idle', style: { '--dy': '3px', '--deg': '3deg', '--dur': '1.3s', display: 'inline-flex' } },
          AP.icon('tv.fill', 44))),
      h('div', { class: 't-hero gradient-text' }, 'Play on TV'),
      h('div', { class: 'c-text2', style: { fontSize: '16px' } }, 'Your phone becomes the controller'));

    var codeCard = ui.card({},
      h('div', { class: 'col gap10' },
        ui.sectionLabel('Room code'),
        h('input', {
          class: 'field code' + (join.shake ? ' bad shake' : ''),
          key: 'join-code',
          type: 'text',
          placeholder: 'ABC123',
          value: join.code,
          maxlength: 6,
          autocomplete: 'off', autocorrect: 'off', autocapitalize: 'characters', spellcheck: 'false',
          inputmode: 'text',
          oninput: function (ev) {
            var clean = ev.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6);
            join.code = clean;
            if (clean.length === 6) { AP.haptic.tap(); }
            if (ev.target.value !== clean) { ev.target.value = clean; }
            AP.changed();
          },
          onkeydown: function (ev) {
            if (ev.key === 'Enter') { var n = document.querySelector('[data-key-name]'); if (n) { n.focus(); } }
          }
        }),
        h('div', { class: 'c-text3', style: { fontSize: '13px' } }, 'It is on the TV screen, under the QR code')));

    var nameCard = ui.card({},
      h('div', { class: 'col gap10' },
        ui.sectionLabel('Your name'),
        h('input', {
          class: 'field name', key: 'join-name', 'data-key-name': '1',
          type: 'text', placeholder: 'Enter name', value: join.name, maxlength: 20,
          autocomplete: 'off', autocapitalize: 'words',
          oninput: function (ev) { join.name = ev.target.value.slice(0, 20); AP.changed(); },
          onkeydown: function (ev) { if (ev.key === 'Enter') { attemptJoin(); } }
        })));

    var joinBtn = h('div', { onclick: function () { if (!canJoin()) { attemptJoin(); } } },
      ui.bigButton({ title: 'Join Game', icon: 'arrow.right.circle.fill', colors: TV_COLORS,
                     enabled: canJoin(), onClick: attemptJoin }));

    var qr = ui.card({},
      h('div', { class: 'row gap14' },
        h('div', { class: 'row center idle', style: { width: '52px', height: '52px', borderRadius: 'var(--r-button)',
                   background: AP.grad([C.purple, C.pink]), '--sc': '0.05', '--dur': '1.2s', flex: '0 0 auto',
                   justifyContent: 'center' } },
          AP.icon('qrcode.viewfinder', 28)),
        h('div', { class: 'col gap4 grow' },
          h('div', { style: { fontSize: '17px', fontWeight: 800 } }, 'Scan the QR instead'),
          h('div', { class: 'c-text2', style: { fontSize: '13px' } },
            'Point your camera at the QR code on the TV. It opens this page with the code filled in.'))));

    var resumeCard = resume ? ui.card({ tint: C.green },
      h('div', { class: 'col gap10' },
        h('div', { style: { fontSize: '17px', fontWeight: 800 } }, 'Back to your TV game'),
        h('div', { class: 'c-text2', style: { fontSize: '13px' } }, 'Room ' + resume + ' is still open for you.'),
        ui.bigButton({ title: 'Rejoin ' + resume, icon: 'arrow.counterclockwise',
                       colors: [C.green, C.cyan], onClick: A.resumeTVGame }))) : null;

    return h('div', { class: 'screen' }, top,
      h('div', { class: 'scroll' },
        h('div', { class: 'col gap20', style: { padding: '6px 20px 28px' } },
          header, resumeCard, codeCard, nameCard, joinBtn, qr,
          h('div', { class: 'txt-center c-text3', style: { fontSize: '11px' } },
            'Aurora Play web controller. Some trivia questions come from Open Trivia DB (opentdb.com), CC BY-SA 4.0.'))));
  };

  // ---- Loading ------------------------------------------------------------

  var dots = { n: 0, timer: null };
  AP.screens.loading = function () {
    if (!dots.timer) {
      dots.timer = setInterval(function () {
        dots.n = (dots.n + 1) % 4;
        if (S.screen === 'loading') { AP.changed(); } else { clearInterval(dots.timer); dots.timer = null; }
      }, 450);
    }
    return h('div', { class: 'screen center', style: { gap: '28px' } },
      h('div', { class: 'col center', style: { gap: '28px' } },
        h('div', { class: 'pop-in', style: { width: '120px', height: '120px', borderRadius: '50%',
          background: AP.grad([C.cyan, C.indigo]), display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 8px 24px ' + AP.alpha(C.cyan, 0.45) } },
          h('span', { class: 'idle', style: { '--dy': '4px', '--sc': '0.05', '--dur': '0.9s', display: 'inline-flex' } },
            AP.icon('tv.fill', 50))),
        h('div', { class: 'col center gap8' },
          h('div', { style: { fontSize: '26px', fontWeight: 900 } }, 'Joining room' + new Array(dots.n + 1).join('.')),
          h('div', { class: 'c-text2', style: { fontSize: '15px' } }, 'Finding your seat at the TV')),
        ui.spinner()),
      h('div', { class: 'w100', style: { padding: '0 32px', position: 'absolute', bottom: '24px' } },
        ui.ghostButton({ title: 'Cancel', icon: 'xmark', onClick: A.returnHome })));
  };

  // ---- Error --------------------------------------------------------------

  AP.screens.error = function () {
    return h('div', { class: 'screen center' },
      h('div', { class: 'col center', style: { gap: '24px', flex: 1, justifyContent: 'center' } },
        h('div', { class: 'pop-in', style: { width: '112px', height: '112px', borderRadius: '50%',
          background: AP.grad([C.red, C.orange]), display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 8px 22px ' + AP.alpha(C.red, 0.45) } },
          h('span', { class: 'idle', style: { '--deg': '5deg', '--dur': '0.8s', display: 'inline-flex' } },
            AP.icon('exclamationmark.triangle.fill', 48))),
        h('div', { class: 'col center gap8' },
          h('div', { style: { fontSize: '28px', fontWeight: 900 } }, 'Could not join'),
          h('div', { class: 'c-text2 txt-center', style: { fontSize: '17px', padding: '0 32px' } }, S.errorMessage))),
      h('div', { class: 'col gap12 w100', style: { padding: '0 32px 24px' } },
        ui.bigButton({ title: 'Try Again', icon: 'arrow.counterclockwise', colors: TV_COLORS, onClick: A.returnToJoin }),
        ui.ghostButton({ title: 'Back to home', icon: 'house.fill', onClick: A.returnHome })));
  };

  // ---- Rules --------------------------------------------------------------

  function leaveFab(size) {
    return h('div', { class: 'leave-fab' },
      h('button', {
        class: 'btn-round press' + (size === 'sm' ? ' sm' : ''), 'aria-label': 'Leave game',
        onclick: function () {
          AP.haptic.tap();
          ui.confirm({ title: 'Leave this game?', confirmTitle: 'Leave Game', onConfirm: A.leaveRoom });
        }
      }, AP.icon('xmark', size === 'sm' ? 13 : 15)));
  }
  AP.leaveFab = leaveFab;

  AP.screens.rules = function () {
    var rules = S.rules || { title: AP.game(S.room.gameID).name, objective: '', rules: [], controls: '' };
    var host = AP.isHost();
    var rows = (rules.rules || []).map(function (rule, i) {
      return h('div', { class: 'row slide-in', style: { alignItems: 'flex-start', gap: '12px', animationDelay: (0.1 + i * 0.06) + 's' } },
        h('div', { class: 'rule-num' }, String(i + 1)),
        h('div', { style: { fontSize: '15px', fontWeight: 600, color: 'rgba(255,255,255,0.92)', paddingTop: '4px' } }, rule));
    });
    var action = host
      ? h('div', { style: { paddingTop: '4px' } },
          h('button', { class: 'btn-big press', style: { '--c1': C.green, '--c2': C.cyan },
            onclick: function () { AP.haptic.tap(); A.beginGame(); } }, AP.icon('play.fill', 20), 'Begin Game'))
      : h('div', { class: 'row pulse', style: { justifyContent: 'center', gap: '10px', padding: '16px',
          borderRadius: 'var(--r-button)', background: C.surface2 } },
          ui.spinner(), h('span', { class: 'c-text2', style: { fontSize: '15px', fontWeight: 800 } }, 'Waiting for host to begin...'));

    return h('div', { class: 'screen', style: { background: 'rgba(11,11,18,0.92)' } },
      leaveFab(),
      h('div', { class: 'scroll col' },
        h('div', { class: 'rules-card col gap16' },
          h('div', { class: 'row gap14' },
            h('div', { class: 'row', style: { width: '56px', height: '56px', borderRadius: 'var(--r-button)',
                 background: AP.grad([C.cyan, C.indigo]), justifyContent: 'center',
                 boxShadow: '0 4px 10px ' + AP.alpha(C.cyan, 0.4), flex: '0 0 auto' } }, AP.icon('gamecontroller.fill', 28)),
            h('div', { class: 'col gap4' },
              h('div', { class: 'label', style: { fontSize: '12px' } }, 'How to play'),
              h('div', { style: { fontSize: '28px', fontWeight: 900, lineHeight: 1.1 } }, rules.title))),
          h('div', { style: { fontSize: '16px', fontWeight: 700, color: C.cyan } }, rules.objective),
          h('div', { class: 'col gap10' }, rows),
          h('div', { class: 'row gap10', style: { padding: '12px 14px', borderRadius: 'var(--r-chip)', background: C.surface2 } },
            h('span', { style: { color: C.pink, display: 'inline-flex' } }, AP.icon('hand.tap.fill', 15)),
            h('div', { class: 'c-text2', style: { fontSize: '14px' } }, rules.controls)),
          action)));
  };

  // ---- Results ------------------------------------------------------------

  var RANK_COLORS = {
    1: [C.yellow, C.orange], 2: [C.cyan, C.indigo], 3: [C.orange, C.pink]
  };
  function rankColor(rank) {
    return rank === 1 ? C.yellow : rank === 2 ? '#cccccc' : rank === 3 ? C.orange : 'rgba(255,255,255,0.1)';
  }
  AP.rankColor = rankColor;

  AP.screens.results = function () {
    var room = S.room;
    var sorted = room.players.slice().sort(function (a, b) { return b.score - a.score; });
    var idx = -1;
    sorted.forEach(function (p, i) { if (p.id === S.playerID) { idx = i; } });
    var myRank = (idx < 0 ? 0 : idx) + 1;
    var me = idx >= 0 ? sorted[idx] : null;
    var colors = RANK_COLORS[myRank] || [C.purple, C.blue];

    var header = h('div', { class: 'col center gap6 pop-in', style: { padding: '36px 0 20px' } },
      h('div', { style: { fontSize: '40px', fontWeight: 900, background: AP.grad([C.orange, C.pink, C.purple], '90deg'),
        WebkitBackgroundClip: 'text', backgroundClip: 'text', color: 'transparent' } }, 'Game Over'),
      h('div', { class: 'c-text2', style: { fontSize: '16px' } }, AP.game(room.gameID).name));

    var callout = h('div', { class: 'row gap14 pop-in', style: { margin: '0 20px', padding: '18px',
        borderRadius: 'var(--r-card)', background: AP.grad(colors), border: '1px solid rgba(255,255,255,0.18)',
        boxShadow: '0 8px 14px ' + AP.alpha(colors[0], 0.35), animationDelay: '0.08s' } },
      h('span', { class: 'idle', style: { '--dy': '3px', '--deg': '5deg', '--dur': '1.2s', display: 'inline-flex' } },
        AP.icon(myRank === 1 ? 'trophy.fill' : (myRank <= 3 ? 'medal.fill' : 'star.fill'), 34)),
      h('div', { class: 'col gap4' },
        h('div', { style: { fontSize: '24px', fontWeight: 900 } }, 'You finished ' + AP.ordinal(myRank)),
        me ? h('div', { style: { fontSize: '15px', fontWeight: 700, color: 'rgba(255,255,255,0.85)' } }, me.score + ' points') : null));

    var board = h('div', { class: 'col gap8', style: { padding: '18px 20px 0' } },
      ui.sectionLabel('Leaderboard'),
      sorted.map(function (p, rank) {
        var mine = p.id === S.playerID;
        return h('div', { class: 'row gap12 rise-in', style: { padding: '10px 14px', borderRadius: 'var(--r-button)',
            background: mine ? AP.alpha(C.cyan, 0.12) : C.surface, animationDelay: (0.15 + Math.min(rank, 8) * 0.05) + 's' } },
          h('div', { class: 'row', style: { width: '30px', height: '30px', borderRadius: '50%', justifyContent: 'center',
              fontSize: '14px', fontWeight: 800, color: rank < 3 ? '#000' : 'rgba(255,255,255,0.75)',
              background: rank < 3 ? rankColor(rank + 1) : C.surface2, flex: '0 0 auto' } }, String(rank + 1)),
          h('div', { class: 'grow', style: { fontSize: '17px', fontWeight: mine ? 800 : 600, color: mine ? C.cyan : '#fff',
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' } }, p.name),
          mine ? ui.tag('YOU') : null,
          h('div', { class: 'num', style: { fontSize: '18px', fontWeight: 900 } }, String(p.score)));
      }));

    var host = AP.isHost();
    var footer;
    if (room.night && AP.nightResultsPanel) {
      footer = h('div', { style: { padding: '0 20px 12px' } }, AP.nightResultsPanel(room));
    } else if (host) {
      footer = h('div', { style: { padding: '0 20px 12px' } },
        ui.bigButton({ title: 'Play Again', icon: 'arrow.clockwise', colors: [C.purple, C.pink], onClick: A.playAgain }));
    } else {
      footer = h('div', { class: 'row', style: { padding: '0 20px 12px', justifyContent: 'center', gap: '8px' } },
        ui.spinner(), h('span', { class: 'c-text2', style: { fontSize: '15px' } }, 'Waiting for the host to start a rematch'));
    }

    return h('div', { class: 'screen' },
      h('div', { class: 'scroll' }, header, callout, board),
      footer,
      h('div', { style: { padding: '0 20px calc(28px + var(--safe-bottom))' } },
        ui.ghostButton({ title: 'Leave Room', icon: 'arrow.left.circle', onClick: A.leaveRoom })));
  };

  // ---- Playing: the controller + chrome ---------------------------------

  AP.screens.retired = function (game) {
    return ui.waitingState(game.icon, game.name, 'This game has been retired. Pick another game on the TV.');
  };
})();
