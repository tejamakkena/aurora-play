/* Mid-group games: Cipher Grid, Odd One Out, Sealed Auction, Spectrum,
 * Bollywood (Dumb) Charades. Port of MidGroupControllers.swift.
 *
 * These carry the most sensitive private state (a spymaster's key, a spy's
 * ignorance, a hidden dial target): each renders only what the server sent
 * to this phone.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, pd = AP.pd;
  var waiting = AP.waiting, centered = AP.centered;

  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }
  function scrollBody(key, kids) {
    return h('div', { class: 'scroll', key: key }, h('div', { class: 'col gap16', style: { padding: '0 0 24px' } }, kids));
  }

  // ---- Cipher Grid ----------------------------------------------------------
  AP.controllers.cipher_grid = function (ctx) {
    var clue = '', count = 1;
    return function (d) {
      var team = pd.str(d, 'team', 'red');
      var isSpy = pd.bool(d, 'isSpymaster');
      var canGuess = pd.bool(d, 'canGuess');
      var canClue = pd.bool(d, 'canClue');
      var words = pd.strings(d, 'words');
      var revealed = pd.arr(d, 'revealed').filter(function (x) { return typeof x === 'boolean'; });
      var key = pd.strings(d, 'key');
      var clueWord = d.clue && typeof d.clue.word === 'string' ? d.clue.word : '';
      var guessesLeft = pd.int(d, 'guessesLeft');
      var teamColor = team === 'red' ? C.red : C.blue;

      function isRev(i) { return i < revealed.length && revealed[i]; }
      function tint(i) {
        if (isRev(i)) { return 'rgba(255,255,255,0.04)'; }
        if (!isSpy || i >= key.length) { return C.surface2; }
        switch (key[i]) {
          case 'red': return AP.alpha(C.red, 0.8);
          case 'blue': return AP.alpha(C.blue, 0.8);
          case 'assassin': return '#000';
          default: return 'rgba(141,127,109,0.6)';
        }
      }
      function isAssassin(i) { return isSpy && !isRev(i) && i < key.length && key[i] === 'assassin'; }

      var top = null;
      if (canClue) {
        top = h('div', { class: 'col gap10 pop-in', key: 'clue', style: { paddingTop: '12px' } },
          ui.answerField({ key: 'clue', placeholder: 'One-word clue', value: clue, autocapitalize: false,
            onInput: function (v) { clue = v; ctx.refresh(); } }),
          h('div', { class: 'px20' },
            kit.card(null, { radius: 'var(--r-button)', style: { padding: '10px 16px', display: 'flex', alignItems: 'center', gap: '14px' } },
              h('span', { class: 'grow c-text2', style: { fontSize: '17px', fontWeight: 700 } }, 'Number'),
              kit.stepButton('minus', count > 1, teamColor, function () { count = Math.max(1, count - 1); ctx.refresh(); }),
              h('span', { class: 'num', style: { fontSize: '26px', fontWeight: 900, minWidth: '30px', textAlign: 'center' } }, String(count)),
              kit.stepButton('plus', count < 9, teamColor, function () { count = Math.min(9, count + 1); ctx.refresh(); }))),
          ui.ctlButton({ title: 'Give Clue', icon: 'paperplane.fill', tint: teamColor, enabled: clue.trim().length > 0,
            onClick: function () { ctx.send('give_clue', { word: clue, count: count }); clue = ''; ctx.refresh(); } }));
      } else if (clueWord) {
        top = h('div', { class: 'center pop-in', key: 'clueword', style: { display: 'flex', paddingTop: '12px' } },
          kit.pill('“' + clueWord + '” · ' + guessesLeft + ' left', 'key.fill', C.yellow));
      }

      var grid = h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: '6px', padding: '0 14px' } },
        words.map(function (w, i) {
          var dis = !canGuess || isRev(i);
          return h('button', { class: 'press', key: 'w-' + i, disabled: dis,
            style: { appearance: 'none', height: '56px', padding: '0 3px', borderRadius: '12px', background: tint(i),
              border: (isAssassin(i) ? '1.5px solid rgba(255,255,255,0.45)' : '1px solid rgba(255,255,255,0.05)'),
              color: isRev(i) ? 'rgba(255,255,255,0.3)' : '#fff', textDecoration: isRev(i) ? 'line-through' : 'none',
              fontSize: '11px', fontWeight: 800, lineHeight: 1.1, overflow: 'hidden', overflowWrap: 'anywhere' },
            onclick: dis ? null : function () { AP.haptic.tap(); ctx.send('guess', { index: i }); } }, w);
        }));

      var foot = isSpy ? h('div', { class: 'center', style: { display: 'flex' } }, kit.pill("Don't let anyone see this screen", 'eye.slash.fill', C.orange))
        : (!canGuess ? h('div', { class: 'txt-center c-text3', style: { fontSize: '14px', fontWeight: 600 } }, 'Waiting for the other team...') : null);

      return ui.shell({ title: 'Cipher Grid',
        subtitle: isSpy ? cap(team) + ' spymaster — keep it secret' : cap(team) + ' team' },
        h('div', { class: 'scroll' }, h('div', { class: 'col gap12', style: { paddingBottom: '16px' } }, top, grid, foot)));
    };
  };

  // ---- Odd One Out ------------------------------------------------------------
  AP.controllers.odd_one_out = function (ctx) {
    var showGuess = false;
    return function (d) {
      var isSpy = pd.bool(d, 'isSpy');
      var location = typeof d.location === 'string' ? d.location : null;
      var phase = pd.str(d, 'phase', 'question');
      var canVote = pd.bool(d, 'canVote');
      var myVote = typeof d.myVote === 'string' ? d.myVote : null;
      var others = pd.dicts(d, 'players').map(function (p) { return { id: typeof p.id === 'string' ? p.id : '', name: typeof p.name === 'string' ? p.name : '' }; });
      var all = pd.strings(d, 'allLocations');

      var role = isSpy
        ? kit.card(C.red, { style: { padding: '22px', textAlign: 'center' }, cls: 'col center gap8' },
            h('span', { class: 'idle', style: { '--deg': '4deg', '--dur': '1.2s', display: 'inline-flex', color: C.pink } }, AP.icon('eyeglasses', 52)),
            h('div', { style: { fontSize: '24px', fontWeight: 900, letterSpacing: '2px', color: C.red } }, 'YOU ARE THE SPY'),
            h('div', { class: 'c-text2', style: { fontSize: '15px' } }, "You don't know the location. Blend in."))
        : kit.card(C.cyan, { style: { padding: '22px', textAlign: 'center' }, cls: 'col center gap6' },
            kit.label('The location'),
            h('div', { style: { fontSize: '32px', fontWeight: 900, color: C.cyan, lineHeight: 1.1 } }, location || '...'),
            h('div', { style: { fontSize: '14px', fontWeight: 700, color: C.orange } }, "Don't say it out loud"));

      var action;
      if (phase === 'reveal') {
        action = h('div', { class: 'center', style: { display: 'flex' }, key: 'rev' }, kit.pill('Round over - look at the TV', 'tv', C.text2));
      } else if (phase === 'question') {
        action = h('div', { key: 'q' }, ui.ctlButton({ title: 'Call a Vote', icon: 'hand.raised.fill', tint: C.orange,
          onClick: function () { ctx.send('call_vote', {}); } }));
      } else {
        action = h('div', { class: 'col gap10 px20', key: 'v' }, ui.sectionLabel('Who is the spy?'),
          others.map(function (p) {
            return ui.choiceRow({ text: p.name, selected: myVote === p.id, disabled: !canVote,
              onClick: function () { ctx.send('vote', { targetID: p.id }); } });
          }));
      }

      var guess = null;
      if (isSpy && phase !== 'reveal') {
        guess = [
          h('div', { class: 'px20' }, ui.ghostButton({ title: showGuess ? 'Hide locations' : 'Guess the location',
            icon: showGuess ? 'chevron.up' : 'mappin.and.ellipse', onClick: function () { showGuess = !showGuess; ctx.refresh(); } })),
          showGuess ? h('div', { class: 'px20', key: 'locs', style: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' } },
            all.map(function (loc) {
              return h('button', { class: 'press', key: 'l-' + loc,
                style: { appearance: 'none', minHeight: '48px', padding: '0 8px', borderRadius: '14px', background: C.surface,
                  border: '1px solid ' + AP.alpha(C.yellow, 0.4), color: '#fff', fontSize: '15px', fontWeight: 700, lineHeight: 1.1 },
                onclick: function () { AP.haptic.thump(); ctx.send('spy_guess', { location: loc }); } }, loc);
            })) : null
        ];
      }

      return ui.shell({ title: 'Odd One Out', subtitle: phase === 'vote' ? 'Vote for the spy' : 'Ask questions',
          secondsLeft: pd.int(d, 'secondsLeft') },
        scrollBody('odd', [h('div', { class: 'px20', style: { paddingTop: '14px' } }, role), action, guess]));
    };
  };

  // ---- Sealed Auction -------------------------------------------------------------
  AP.controllers.sealed_auction = function (ctx) {
    var bid = 0, trackedRound = -1;
    return function (d) {
      var lotName = pd.str(d, 'lotName');
      var lotValue = pd.int(d, 'lotValue');
      var budget = pd.int(d, 'budget');
      var phase = pd.str(d, 'phase', 'bid');
      var myBid = typeof d.myBid === 'number' ? Math.trunc(d.myBid) : null;
      var round = pd.int(d, 'round');
      if (round !== trackedRound) { trackedRound = round; bid = 0; }

      var lot = h('div', { class: 'px20', style: { paddingTop: '14px' } },
        kit.card(C.yellow, { cls: 'col center gap6 txt-center', style: { padding: '20px' } },
          kit.label('On the block'),
          h('div', { style: { fontSize: '24px', fontWeight: 800, lineHeight: 1.2 } }, lotName),
          h('div', { style: { fontSize: '15px', fontWeight: 700, color: C.yellow } }, 'worth ' + (lotValue * 10) + ' points')));

      var content;
      if (phase !== 'bid') {
        content = waiting('rev', 'hammer.fill', 'Bids revealed on the TV', myBid !== null ? 'You bid ' + myBid : null);
      } else if (myBid !== null) {
        content = waiting('sealed', 'lock.fill', 'Bid sealed', 'You bid ' + myBid + ' — nobody can see it yet');
      } else {
        var maxBid = Math.max(budget, 1);
        content = h('div', { class: 'col gap16 pop-in', key: 'bid' },
          h('div', { class: 'px20' },
            kit.card(null, { cls: 'col center gap10', style: { padding: '20px' } },
              h('div', { class: 'num', style: { fontSize: '64px', fontWeight: 900, lineHeight: 1, background: AP.grad([C.cyan, C.indigo]),
                  WebkitBackgroundClip: 'text', backgroundClip: 'text', color: 'transparent' } }, String(bid)),
              h('div', { class: 'w100' }, kit.slider({ key: 'bidslider', min: 0, max: maxBid, value: Math.min(bid, maxBid), tint: C.cyan,
                onInput: function (v) { bid = v; ctx.refresh(); } })),
              h('div', { class: 'c-text3', style: { fontSize: '13px' } }, 'of ' + budget + ' remaining'))),
          ui.ctlButton({ title: 'Place Sealed Bid', icon: 'lock.fill', onClick: function () { ctx.send('bid', { amount: Math.trunc(bid) }); } }));
      }
      return ui.shell({ title: 'Sealed Auction', subtitle: 'Budget ' + budget, secondsLeft: pd.int(d, 'secondsLeft') },
        h('div', { class: 'col gap16', style: { flex: '1 1 auto', minHeight: 0 } }, lot, content));
    };
  };

  // ---- Spectrum -------------------------------------------------------------------
  AP.controllers.wavelength = function (ctx) {
    var clueText = '', dial = 50, lastSent = 0, pending = null;
    function sendDial(v) {
      var now = Date.now();
      if (now - lastSent > 60) { lastSent = now; ctx.send('set_dial', { value: Math.trunc(v) }); pending = null; }
      else { pending = v; ctx.after(80, function () { if (pending !== null) { lastSent = Date.now(); ctx.send('set_dial', { value: Math.trunc(pending) }); pending = null; } }); }
    }
    return function (d) {
      var isPsychic = pd.bool(d, 'isPsychic');
      var target = typeof d.target === 'number' ? Math.trunc(d.target) : null;
      var left = pd.str(d, 'leftLabel'), right = pd.str(d, 'rightLabel');
      var clue = pd.str(d, 'clue');
      var canClue = pd.bool(d, 'canClue'), canDial = pd.bool(d, 'canDial');

      function endLabel(text, tint) {
        return h('span', { style: { padding: '8px 12px', borderRadius: '999px', background: AP.alpha(tint, 0.14), color: tint,
          fontSize: '15px', fontWeight: 800, lineHeight: 1.1, maxWidth: '46%' } }, text);
      }
      var ends = h('div', { class: 'row px20', style: { justifyContent: 'space-between', paddingTop: '14px', gap: '10px' } },
        endLabel(left, C.blue), endLabel(right, C.red));

      var targetCard = null;
      if (isPsychic && target !== null) {
        targetCard = h('div', { class: 'px20' },
          kit.card(C.purple, { cls: 'col center gap10', style: { padding: '18px 0' } },
            kit.label('Your secret target'),
            h('div', { style: { position: 'relative', width: '280px', height: '42px' } },
              h('div', { style: { position: 'absolute', left: 0, right: 0, top: '8px', height: '26px', borderRadius: '999px',
                  background: AP.grad([C.blue, C.purple, C.red], '90deg') } }),
              h('div', { style: { position: 'absolute', top: 0, width: '8px', height: '42px', borderRadius: '999px', background: '#fff',
                  left: (target / 100 * 280 - 4) + 'px', boxShadow: '0 0 4px rgba(0,0,0,0.4)' } })),
            h('div', { style: { fontSize: '30px', fontWeight: 900 } }, String(target))));
      }

      var main;
      if (canClue) {
        main = h('div', { class: 'col gap14 pop-in', key: 'clue' },
          ui.answerField({ key: 'wclue', placeholder: 'Your clue', value: clueText, autocapitalize: false,
            onInput: function (v) { clueText = v; ctx.refresh(); } }),
          ui.ctlButton({ title: 'Give Clue', icon: 'paperplane.fill', tint: C.purple, enabled: clueText.length > 0,
            onClick: function () { ctx.send('give_clue', { clue: clueText }); clueText = ''; ctx.refresh(); } }));
      } else if (canDial) {
        main = h('div', { class: 'px20 pop-in', key: 'dial' },
          kit.card(C.cyan, { cls: 'col center gap14', style: { padding: '20px' } },
            h('div', { class: 'txt-center', style: { fontSize: '24px', fontWeight: 800, color: C.yellow } }, '“' + clue + '”'),
            h('div', { class: 'w100' }, kit.slider({ key: 'dialslider', min: 0, max: 100, value: dial, tint: C.cyan,
              onInput: function (v) { dial = v; sendDial(v); ctx.refresh(); } })),
            h('div', { class: 'num', style: { fontSize: '34px', fontWeight: 900, color: C.cyan } }, String(Math.trunc(dial)))));
      } else {
        main = waiting('wait', 'antenna.radiowaves.left.and.right', clue ? '“' + clue + '”' : 'Waiting for the clue...',
          isPsychic ? 'The team is turning the dial' : 'Watch the TV');
      }
      return ui.shell({ title: 'Spectrum', subtitle: isPsychic ? "You're the psychic" : 'Read the clue',
          secondsLeft: pd.int(d, 'secondsLeft') },
        h('div', { class: 'col gap16', style: { flex: '1 1 auto', minHeight: 0, overflowY: 'auto' } }, ends, targetCard, main));
    };
  };

  // ---- Dumb (Bollywood) Charades ------------------------------------------------------
  AP.controllers.bollywood_charades = function (ctx) {
    var guess = '';
    return function (d) {
      var isActor = pd.bool(d, 'isActor');
      var title = typeof d.title === 'string' ? d.title : null;
      var gotIt = pd.bool(d, 'gotIt');
      var canGuess = pd.bool(d, 'canGuess');
      var content;
      if (isActor) {
        content = h('div', { class: 'px20 pop-in', key: 'actor', style: { paddingTop: '20px' } },
          kit.card(C.orange, { cls: 'col center gap12 txt-center', style: { padding: '24px' } },
            h('span', { class: 'idle', style: { '--deg': '5deg', '--sc': '0.04', '--dur': '1.2s', display: 'inline-flex', color: C.pink } },
              AP.icon('theatermasks.fill', 58)),
            kit.label('Act this out'),
            h('div', { style: { fontSize: '32px', fontWeight: 900, color: C.yellow, lineHeight: 1.1 } }, title || '...'),
            kit.pill('No words, no sounds!', 'speaker.slash.fill', C.orange)));
      } else if (gotIt) {
        content = waiting('got', 'checkmark.circle.fill', 'You got it!', 'Waiting for the round to end');
      } else if (canGuess) {
        content = centered('guess',
          ui.answerField({ key: 'cg', placeholder: 'Film name', value: guess, onInput: function (v) { guess = v; ctx.refresh(); } }),
          ui.ctlButton({ title: 'Guess', icon: 'paperplane.fill', tint: C.orange, enabled: guess.trim().length > 0,
            onClick: function () { ctx.send('guess', { text: guess }); guess = ''; ctx.refresh(); } }));
      } else {
        content = waiting('rev', 'film.fill', 'Reveal is on the TV');
      }
      return ui.shell({ title: 'Bollywood Charades', subtitle: isActor ? "You're acting" : 'Guess the film',
        secondsLeft: pd.int(d, 'secondsLeft') }, content);
    };
  };
})();
