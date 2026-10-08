/* Aurora Play web controller: the lobby (WaitingView) and teams.
 *
 * Ports of WaitingView, HostLobbyControls and TeamsViews.swift. Game Night
 * and the make-your-own quiz plug in through AP.lobbyExtras (onestop.js).
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, S = AP.S, A = AP.act;

  var TEAM_TINTS = {
    red: 'rgb(255,84,102)', blue: 'rgb(77,148,255)', green: 'rgb(71,219,133)',
    yellow: 'rgb(255,204,64)'
  };
  var TEAM_DEFAULT = 'rgb(178,140,255)';
  AP.teamTint = function (name) { return TEAM_TINTS[name] || TEAM_DEFAULT; };

  function teamOf(teams, id) {
    for (var i = 0; i < teams.teams.length; i++) {
      if (teams.teams[i].members.indexOf(id) >= 0) { return teams.teams[i]; }
    }
    return null;
  }
  AP.teamOf = teamOf;

  function inviteLink(room) { return window.location.origin + '/join/' + room.code; }

  function share(room) {
    var url = inviteLink(room);
    var text = 'Join my ' + AP.game(room.gameID).name + ' game on Aurora Play. Room code ' + room.code + '.';
    if (navigator.share) {
      navigator.share({ title: 'Join my Aurora Play game', text: text, url: url }).catch(function () { /* cancelled */ });
    } else if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(url).then(function () { ui.toast('Invite link copied'); },
        function () { ui.toast(url); });
    } else {
      ui.toast(url);
    }
  }

  function inviteButton(room) {
    return h('button', {
      class: 'btn-pill press',
      style: { background: AP.alpha(C.cyan, 0.12), color: C.cyan, fontWeight: 700 },
      onclick: function () { AP.haptic.tap(); share(room); }
    }, AP.icon('square.and.arrow.up', 15), 'Invite');
  }

  // ---- teams -------------------------------------------------------------

  function teamsCard(room, teams) {
    var mine = teamOf(teams, S.playerID);
    var rows = teams.teams.map(function (team) {
      var isMine = team.members.indexOf(S.playerID) >= 0;
      var tint = AP.teamTint(team.color);
      var names = team.members.map(function (id) {
        for (var i = 0; i < room.players.length; i++) { if (room.players[i].id === id) { return room.players[i].name; } }
        return null;
      }).filter(Boolean);
      return h('button', {
        class: 'press', key: 'team-' + team.id,
        style: { appearance: 'none', textAlign: 'left', width: '100%', padding: '12px', borderRadius: 'var(--r-chip)',
          background: AP.alpha(tint, isMine ? 0.22 : 0.08),
          border: (isMine ? 2 : 1) + 'px solid ' + AP.alpha(tint, isMine ? 0.9 : 0.3) },
        onclick: function () {
          if (isMine || room.state !== 'lobby') { return; }
          AP.haptic.tap();
          A.moveToTeam(team.id);
        }
      },
        h('div', { class: 'row', style: { alignItems: 'flex-start', gap: '12px' } },
          h('span', { style: { width: '14px', height: '14px', borderRadius: '50%', background: tint, marginTop: '4px', flex: '0 0 auto' } }),
          h('div', { class: 'col gap4 grow' },
            h('div', { class: 'row' },
              h('span', { class: 'grow', style: { fontSize: '15px', fontWeight: 800, color: '#fff' } }, team.name),
              team.points > 0 ? h('span', { style: { fontSize: '12px', fontWeight: 800, color: tint } }, team.points + ' pts') : null),
            h('div', { style: { fontSize: '12px', color: 'rgba(255,255,255,0.6)', fontWeight: 500 } },
              names.length ? names.join(', ') : 'Nobody yet'))));
    });
    return ui.card({ tint: C.yellow },
      h('div', { class: 'col gap12' },
        h('div', { class: 'row' },
          h('div', { class: 'row gap8 grow', style: { fontSize: '17px', fontWeight: 800 } }, AP.icon('person.3.fill', 18), 'Teams'),
          mine ? h('span', { style: { fontSize: '12px', fontWeight: 600, color: AP.teamTint(mine.color) } }, "You're on " + mine.name) : null),
        rows,
        room.state === 'lobby' ? h('div', { style: { fontSize: '12px', color: 'rgba(255,255,255,0.45)', fontWeight: 500 } }, 'Tap a team to switch') : null));
  }

  function hostTeamsControl(room) {
    if (room.players.length < 2) { return null; }
    var current = room.teams ? room.teams.teams.length : 0;
    var most = Math.min(4, room.players.length);
    function option(label, count) {
      var sel = current === count;
      return h('button', {
        class: 'press', key: 'tm-' + count,
        style: { appearance: 'none', border: 0, padding: '8px 12px', borderRadius: '999px', fontSize: '15px', fontWeight: 700,
          color: sel ? '#000' : 'rgba(255,255,255,0.7)', background: sel ? C.yellow : 'rgba(255,255,255,0.08)' },
        onclick: function () { if (!sel) { A.setTeams(count); } }
      }, label);
    }
    var opts = [option('Solo', 0)];
    for (var c = 2; c <= 4; c++) { if (c <= most) { opts.push(option(c + ' teams', c)); } }
    if (current > 0) {
      opts.push(h('button', {
        class: 'press', 'aria-label': 'Shuffle teams',
        style: { appearance: 'none', border: 0, padding: '8px', borderRadius: '50%', color: C.yellow,
          background: 'rgba(255,255,255,0.08)', display: 'inline-flex' },
        onclick: function () { AP.haptic.tap(); A.setTeams(current); }
      }, AP.icon('shuffle', 16)));
    }
    return h('div', { class: 'row gap8 wrap' },
      h('span', { style: { color: 'rgba(255,255,255,0.5)', display: 'inline-flex' } }, AP.icon('person.3.fill', 18)), opts);
  }

  // ---- host controls --------------------------------------------------------

  var CONTENT_PACKS = [['en', 'English'], ['te', 'Telugu'], ['hi', 'Hindi']];

  function hostControls(room) {
    var g = AP.game(room.gameID);
    var canAddBot = !!room.botsAllowed && room.players.length < g.max;
    var kids = [];
    if (!room.night && AP.lobbyExtras && AP.lobbyExtras.planner) { kids.push(AP.lobbyExtras.planner(room)); }
    if (AP.lobbyExtras && AP.lobbyExtras.quizMaker) { kids.push(AP.lobbyExtras.quizMaker(room)); }
    kids.push(hostTeamsControl(room));
    if (room.usesContentPack) {
      kids.push(ui.card({},
        h('div', { class: 'col gap10' },
          h('div', { class: 'row gap8', style: { fontSize: '15px', fontWeight: 800, color: 'rgba(255,255,255,0.85)' } },
            AP.icon('character.bubble.fill', 17), 'Question language'),
          h('div', { class: 'row gap8' }, CONTENT_PACKS.map(function (p) {
            return ui.chip({ title: p[1], selected: (room.contentPack || 'en') === p[0],
                             colors: [C.cyan, C.blue], onClick: function () { A.setContentPack(p[0]); } });
          })))));
    }
    if (room.botsAllowed) {
      kids.push(h('button', {
        class: 'press', disabled: !canAddBot,
        style: { appearance: 'none', width: '100%', padding: '14px', borderRadius: 'var(--r-button)', fontSize: '16px', fontWeight: 800,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px',
          color: canAddBot ? C.orange : 'rgba(255,255,255,0.3)',
          background: AP.alpha(C.orange, canAddBot ? 0.1 : 0.03),
          border: '1.5px solid ' + AP.alpha(C.orange, canAddBot ? 0.5 : 0.15) },
        onclick: canAddBot ? function () { AP.haptic.tap(); A.addBot(); } : null
      }, AP.icon('cpu', 18), 'Add a bot player'));
    }
    return h('div', { class: 'col gap12' }, kids);
  }

  // ---- lobby ---------------------------------------------------------------

  function playerRow(room, p) {
    var me = p.id === S.playerID;
    var host = AP.isHost();
    return h('div', { class: 'player-row' + (me ? ' me' : ''), key: 'p-' + p.id },
      ui.avatar(p.name, p.isReady),
      h('span', { style: { fontSize: '17px', fontWeight: me ? 800 : 700, color: me ? C.cyan : '#fff',
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' } }, p.name),
      p.isHost ? ui.tag('HOST') : null,
      p.isBot ? ui.tag('BOT', C.orange) : null,
      h('span', { class: 'spacer' }),
      (p.isBot && host) ? h('button', {
        class: 'press', 'aria-label': 'Remove ' + p.name,
        style: { appearance: 'none', border: 0, background: 'none', color: AP.alpha(C.red, 0.85), display: 'inline-flex', padding: 0 },
        onclick: function () { AP.haptic.tap(); A.removeBot(p.id); }
      }, AP.icon('minus.circle.fill', 22)) : null,
      p.isReady ? AP.icon('checkmark.circle.fill', 22, C.green) : AP.icon('circle', 22, 'rgba(255,255,255,0.2)'));
  }

  AP.screens.waiting = function () {
    var room = S.room;
    var g = AP.game(room.gameID);
    var ready = room.players.filter(function (p) { return p.isReady; }).length;

    var badge = h('div', { class: 'col center gap12 pop-in', style: { paddingTop: '6px' } },
      h('div', { class: 'badge-tile', style: { width: '96px', height: '96px' } },
        h('span', { class: 'idle', style: { '--dy': '3px', '--deg': '3deg', '--dur': '1.5s', display: 'inline-flex' } },
          AP.icon(g.icon, 44))),
      h('div', { class: 'txt-center', style: { fontSize: '30px', fontWeight: 900 } }, g.name),
      h('div', { class: 'c-text2', style: { fontSize: '15px' } }, 'Waiting for everyone to get ready'));

    var codeCard = ui.card({ tint: C.cyan },
      h('div', { class: 'row gap12' },
        h('div', { class: 'col gap4 grow' },
          ui.sectionLabel('Room'),
          h('div', { class: 'mono', style: { fontSize: '30px', fontWeight: 900, color: C.cyan, letterSpacing: '2px' } }, room.code)),
        inviteButton(room)));

    var kids = [badge, codeCard];
    if (room.night && AP.lobbyExtras && AP.lobbyExtras.nightStatus) { kids.push(AP.lobbyExtras.nightStatus(room)); }
    if (room.teams) { kids.push(teamsCard(room, room.teams)); }

    kids.push(h('div', { class: 'col gap10' },
      h('div', { class: 'row' },
        h('div', { class: 'grow' }, ui.sectionLabel('Players')),
        h('span', { style: { fontSize: '13px', fontWeight: 700, color: C.green, whiteSpace: 'nowrap' } },
          ready + ' / ' + room.players.length + ' ready')),
      room.players.map(function (p) { return playerRow(room, p); })));

    if (AP.isHost()) {
      kids.push(h('div', { style: { paddingTop: '4px' } }, ui.sectionLabel('Host controls')));
      kids.push(hostControls(room));
    }
    if (g.priv) {
      kids.push(h('div', { class: 'row gap10', style: { justifyContent: 'center', padding: '0 12px', fontSize: '13px',
          fontWeight: 600, color: AP.alpha(C.cyan, 0.85) } },
        AP.icon('eye.slash.fill', 15), 'Your private info will appear here when the game starts'));
    }

    var readyBtn = S.readyLocal
      ? h('div', { class: 'ready-banner' }, AP.icon('checkmark.circle.fill', 22), 'Ready! Waiting for the TV')
      : ui.bigButton({ title: "I'm Ready", icon: 'hand.thumbsup.fill', colors: [C.green, C.cyan],
                       onClick: function () { AP.haptic.success(); A.markReady(); } });

    return h('div', { class: 'screen' },
      ui.topBar({ title: '', backTitle: 'Leave', onBack: A.leaveRoom }),
      h('div', { class: 'scroll' },
        h('div', { class: 'col gap20', style: { padding: '0 20px 24px' } }, kids)),
      h('div', { class: 'footer-bar' }, readyBtn));
  };
})();
