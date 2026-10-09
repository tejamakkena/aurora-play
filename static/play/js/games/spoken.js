/* Spoken games: Atlas and Antakshari. Port of SpokenGameControllers.swift.
 *
 * Nobody types: the player talks or sings out loud and the phone only ever
 * makes one quick tap (Next, Valid / Out!, Sang it / Missed, or a letter).
 * Server: games/native_hub/engines/spoken.py; privateData.role picks the screen.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, pd = AP.pd;
  var waiting = AP.waiting;

  var VALID = C.green, OUT = C.red;
  var ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');

  function teamColor(name, index) {
    switch (String(name).toLowerCase()) {
      case 'red': return C.red;
      case 'blue': return C.blue;
      case 'green': return C.green;
      case 'yellow': case 'gold': return C.yellow;
      default: return index === 1 ? C.pink : C.cyan;
    }
  }

  function eyebrow(text, tint) {
    return h('div', { style: { fontSize: '13px', fontWeight: 800, letterSpacing: '2px', color: tint || C.text3,
      whiteSpace: 'nowrap', textAlign: 'center' } }, String(text).toUpperCase());
  }

  function letterBadge(letter, tint, size) {
    return h('div', { class: 'idle', key: 'badge-' + letter, style: { '--dy': '3px', '--sc': '0.03', '--dur': '1.6s', flex: '0 0 auto' } },
      h('div', { class: 'pop-in', style: { width: size + 'px', height: size + 'px', borderRadius: '50%', display: 'flex',
          alignItems: 'center', justifyContent: 'center', fontSize: Math.round(size * 0.56) + 'px', fontWeight: 900, lineHeight: 1,
          background: AP.grad([AP.alpha(tint, 0.3), AP.alpha(C.indigo, 0.18)]), border: '2px solid ' + AP.alpha(tint, 0.55),
          boxShadow: '0 0 18px ' + AP.alpha(tint, 0.35) } },
        h('span', { style: { background: AP.grad(['#fff', tint]), WebkitBackgroundClip: 'text', backgroundClip: 'text', color: 'transparent' } },
          letter || '?')));
  }

  function giantButton(o) {
    var height = o.height || 120;
    return h('div', { class: 'px20', key: o.key },
      h('button', { class: 'press',
        style: { appearance: 'none', width: '100%', height: height + 'px', borderRadius: 'var(--r-card)', color: '#fff', position: 'relative',
          border: o.selected ? '4px solid rgba(255,255,255,0.95)' : '4px solid transparent',
          background: AP.grad([o.tint, AP.alpha(o.tint, 0.65)]), opacity: o.dimmed ? 0.4 : 1,
          boxShadow: o.dimmed ? 'none' : '0 8px 16px ' + AP.alpha(o.tint, 0.4),
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '14px', fontSize: '34px', fontWeight: 900,
          textShadow: '0 1px 2px rgba(0,0,0,0.25)', transform: o.selected ? 'scale(1.02)' : 'none',
          transition: 'transform .38s var(--pop), opacity .2s' },
        onclick: function () { AP.haptic.thump(); o.onClick(); } },
        AP.icon(o.icon, 32), o.title,
        o.selected ? h('span', { style: { position: 'absolute', top: '8px', right: '8px', display: 'inline-flex' } }, AP.icon('checkmark.circle.fill', 26)) : null));
  }

  function letterGrid(o) {
    var suggested = o.suggested || [], hard = o.hard || [];
    return h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(6, 1fr)', gap: '8px', padding: '0 16px' } },
      ALPHABET.map(function (letter) {
        var isPicked = o.state.picked === letter;
        var isHi = o.highlighted === letter;
        var isSug = suggested.indexOf(letter) >= 0;
        var isHard = hard.indexOf(letter) >= 0;
        var fill = isPicked ? o.tint : (isHi ? AP.alpha(o.tint, 0.45) : (isSug ? AP.alpha(o.tint, 0.16) : C.surface));
        var border = (isPicked || isHi) ? 'rgba(255,255,255,0.8)' : (isSug ? AP.alpha(o.tint, 0.45) : 'rgba(255,255,255,0.06)');
        return h('button', { class: 'press', key: 'L' + letter, disabled: !!o.state.picked && !isPicked,
          style: { appearance: 'none', height: '56px', borderRadius: 'var(--r-chip)', background: fill, color: (isHard && !isPicked) ? C.text2 : '#fff',
            border: ((isPicked || isHi) ? 2 : 1) + 'px solid ' + border, transform: isPicked ? 'scale(1.08)' : 'none',
            display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 0,
            transition: 'transform .38s var(--pop)' },
          onclick: function () {
            if (o.state.picked) { return; }
            AP.haptic.thump();
            o.state.picked = letter;
            o.onPick(letter);
          } },
          h('span', { style: { fontSize: '27px', fontWeight: 900, lineHeight: 1 } }, letter),
          isHard ? h('span', { style: { fontSize: '9px', fontWeight: 800, letterSpacing: '1px', color: C.yellow } }, 'SKIP') : null);
      }));
  }

  function note(text, icon, tint) {
    tint = tint || C.text2;
    return h('div', { class: 'px20 center', style: { display: 'flex' } },
      h('div', { class: 'row gap8', style: { padding: '10px 16px', borderRadius: '999px', background: AP.alpha(tint, 0.14), color: tint,
          fontSize: '15px', fontWeight: 700, textAlign: 'center' } }, AP.icon(icon || 'info.circle.fill', 14), text));
  }

  function pane(key, kids) {
    return h('div', { class: 'col gap14 pop-in', key: key, style: { flex: '1 1 auto', minHeight: 0, overflowY: 'auto', padding: '0 0 8px' } }, kids);
  }
  function spacer(min) { return h('div', { style: { flex: '1 1 auto', minHeight: (min || 8) + 'px' } }); }
  function title(text, size) { return h('div', { class: 'txt-center px20', style: { fontSize: (size || 24) + 'px', fontWeight: 800, lineHeight: 1.15 } }, text); }
  function sub(text) { return h('div', { class: 'c-text2 txt-center px20', style: { fontSize: '15px', fontWeight: 600 } }, text); }
  function hint(text) { return h('div', { class: 'c-text3 txt-center', style: { fontSize: '14px', fontWeight: 600, paddingBottom: '8px' } }, text); }

  // ---- Atlas -------------------------------------------------------------------
  AP.controllers.atlas = function (ctx) {
    var spelled = '', trackedRound = -1;
    var grid = { picked: '' };
    var tint = C.cyan;
    return function (d) {
      var role = pd.str(d, 'role', 'wait'), phase = pd.str(d, 'phase');
      var round = pd.int(d, 'round'), letter = pd.str(d, 'letter');
      var speakerName = pd.str(d, 'speakerName', 'Someone');
      var myVote = pd.str(d, 'myVote');
      var lives = pd.int(d, 'lives'), maxLives = pd.int(d, 'maxLives', 3);
      var isPlaying = pd.bool(d, 'isPlaying'), isOut = pd.bool(d, 'isOut');
      var spelling = pd.bool(d, 'spelling'), isHost = pd.bool(d, 'isHost'), finished = pd.bool(d, 'finished');
      var hard = pd.strings(d, 'hardLetters');
      if (round !== trackedRound) { trackedRound = round; spelled = ''; grid = { picked: '' }; }

      var subtitle = isOut ? "You're out -- still judging" : (!isPlaying ? 'Judging' : (lives === 1 ? '1 life left' : lives + ' lives left'));
      var lastLetter = '';
      var ls = spelled.toUpperCase().split('').filter(function (c) { return ALPHABET.indexOf(c) >= 0; });
      if (ls.length) { lastLetter = ls[ls.length - 1]; }

      var content;
      if (finished) {
        content = waiting('fin', 'flag.checkered', 'Game over', 'The winner is on the TV');
      } else if (role === 'speak') {
        content = pane('speak', [
          h('div', { style: { height: '2px' } }),
          eyebrow('Your turn', tint), h('div', { class: 'center', style: { display: 'flex' } }, letterBadge(letter, tint, 150)),
          title('Say a place starting with ' + letter),
          sub('Out loud, to the room. They judge it.'), spacer(8),
          giantButton({ key: 'next', title: 'Next', icon: 'checkmark', tint: VALID, height: 130, onClick: function () { ctx.send('said', {}); } }),
          hint("Tap once you've said it")]);
      } else if (role === 'judge') {
        content = pane('judge', [
          eyebrow(speakerName + ' is speaking'),
          h('div', { class: 'row px20', style: { gap: '16px' } }, letterBadge(letter, tint, 92),
            h('div', { style: { fontSize: '19px', fontWeight: 800, lineHeight: 1.2 } }, 'Did they say a real place starting with ' + letter + '?')),
          spacer(8),
          giantButton({ key: 'valid', title: 'Valid', icon: 'checkmark', tint: VALID, selected: myVote === 'valid', dimmed: myVote === 'out',
            onClick: function () { ctx.send('judge', { verdict: 'valid' }); } }),
          giantButton({ key: 'out', title: 'Out!', icon: 'xmark', tint: OUT, selected: myVote === 'out', dimmed: myVote === 'valid',
            onClick: function () { ctx.send('judge', { verdict: 'out' }); } }),
          hint(myVote ? 'Tap the other one to change your mind' : 'A majority decides')]);
      } else if (role === 'pick') {
        content = pane('pick', [
          h('div', { style: { height: '8px' } }), eyebrow('Valid!', VALID),
          title('Your place ended with...'),
          spelling ? ui.answerField({ key: 'spell', placeholder: 'Spell it (optional)', value: spelled,
            onInput: function (v) { spelled = v; ctx.refresh(); } }) : null,
          letterGrid({ tint: tint, hard: hard, highlighted: lastLetter, state: grid, onPick: function (picked) {
            var payload = { letter: picked };
            var place = spelled.trim();
            if (spelling && place) { payload.place = place; }
            ctx.send('pick_letter', payload);
            spelled = '';
          } }),
          note('Q, X and Z skip to a new letter', 'forward.fill')]);
      } else if (phase === 'letter') {
        content = waiting('w-letter', 'hand.tap.fill', speakerName + ' is picking the next letter', 'Get ready -- it could be you next');
      } else {
        content = waiting('w-next', 'hourglass', 'Next player coming up', 'Watch the TV');
      }

      var lifeRow = (isPlaying && !isOut) ? h('div', { class: 'row center', style: { display: 'flex', justifyContent: 'center', gap: '6px', paddingTop: '10px' } },
        Array.apply(null, Array(Math.max(maxLives, 0))).map(function (_, i) {
          return h('span', { key: 'hp' + i, style: { display: 'inline-flex', color: i < lives ? C.red : 'rgba(255,255,255,0.2)' } },
            AP.icon(i < lives ? 'heart.fill' : 'heart', 20));
        })) : null;
      var toggle = (isHost && role !== 'pick' && !finished) ? h('div', { class: 'center', style: { display: 'flex', paddingBottom: '10px' } },
        h('button', { class: 'press', style: { appearance: 'none', display: 'inline-flex', alignItems: 'center', gap: '8px', padding: '10px 16px',
            borderRadius: '999px', background: C.surface, border: '1px solid rgba(255,255,255,0.08)', fontSize: '14px', fontWeight: 700,
            color: spelling ? C.yellow : C.text2 },
          onclick: function () { AP.haptic.tap(); ctx.send('toggle_spelling', { on: !spelling }); } },
          AP.icon(spelling ? 'textformat.abc' : 'textformat', 14),
          spelling ? 'Spelling mode: on' : 'Spelling mode for kids: off')) : null;

      return ui.shell({ title: 'Atlas', subtitle: subtitle, secondsLeft: (role === 'wait' || finished) ? null : pd.int(d, 'secondsLeft') },
        h('div', { class: 'col gap16', style: { flex: '1 1 auto', minHeight: 0 } }, lifeRow, content, toggle));
    };
  };

  // ---- Antakshari ----------------------------------------------------------------
  AP.controllers.antakshari = function (ctx) {
    var trackedRound = -1, grid = { picked: '' };
    return function (d) {
      var role = pd.str(d, 'role', 'wait'), phase = pd.str(d, 'phase');
      var round = pd.int(d, 'round'), letter = pd.str(d, 'letter');
      var myTeam = pd.int(d, 'myTeam', -1);
      var myTeamName = pd.str(d, 'myTeamName'), myTeamColor = pd.str(d, 'myTeamColor');
      var singing = pd.str(d, 'singingTeamName', 'The other team');
      var target = pd.int(d, 'target', 8);
      var finished = pd.bool(d, 'finished');
      var suggested = pd.strings(d, 'suggestedLetters'), hard = pd.strings(d, 'hardLetters');
      var scores = pd.arr(d, 'teamScores').filter(function (x) { return typeof x === 'number'; });
      var tint = teamColor(myTeamColor, myTeam);
      if (round !== trackedRound) { trackedRound = round; grid = { picked: '' }; }

      var subtitle = null;
      if (myTeam >= 0 && myTeamName) {
        if (scores.length === 2) {
          subtitle = myTeamName + '  ' + scores[myTeam === 1 ? 1 : 0] + ' - ' + scores[myTeam === 1 ? 0 : 1] + '  (first to ' + target + ')';
        } else { subtitle = myTeamName; }
      }

      var content;
      if (finished) {
        content = waiting('fin', 'music.note', 'Game over', 'The winners are on the TV');
      } else if (role === 'sing') {
        content = pane('sing', [
          spacer(8), eyebrow('Your team is singing', tint),
          h('div', { class: 'center', style: { display: 'flex' } }, letterBadge(letter, tint, 170)),
          title('Sing a song starting with ' + letter, 25),
          h('div', { class: 'idle center', style: { display: 'flex', '--dy': '0px', '--sc': '0.12', '--dur': '0.5s', color: tint, paddingTop: '6px', justifyContent: 'center' } }, AP.icon('music.mic', 44)),
          sub('Out loud, together. The other team judges.'), spacer(8)]);
      } else if (role === 'judge') {
        content = pane('judge', [
          h('div', { style: { height: '12px' } }), eyebrow(singing + ' is singing'),
          h('div', { class: 'row px20', style: { gap: '16px' } }, letterBadge(letter, C.yellow, 92),
            h('div', { style: { fontSize: '19px', fontWeight: 800, lineHeight: 1.2 } }, 'Did they sing a song starting with ' + letter + '?')),
          spacer(8),
          giantButton({ key: 'sang', title: 'Sang it', icon: 'music.note', tint: VALID, onClick: function () { ctx.send('judge', { verdict: 'sang' }); } }),
          giantButton({ key: 'missed', title: 'Missed', icon: 'xmark', tint: OUT, onClick: function () { ctx.send('judge', { verdict: 'missed' }); } }),
          hint('Any player on your team can call it')]);
      } else if (role === 'pick') {
        content = pane('pick', [
          h('div', { style: { height: '8px' } }), eyebrow('Sang it! +1', VALID), title('Your song ended with...'),
          letterGrid({ tint: tint, suggested: suggested, hard: hard, state: grid, onPick: function (p) { ctx.send('pick_letter', { letter: p }); } }),
          note('Highlighted letters have lots of songs. Q, X and Z skip to a new letter.', 'music.note.list')]);
      } else if (phase === 'letter') {
        content = waiting('w-letter', 'hand.tap.fill', singing + ' is picking the next letter', 'Start thinking of songs!');
      } else if (phase === 'beat') {
        content = waiting('w-beat', 'music.quarternote.3', 'Get ready', singing + ' sings next. Letter ' + letter + '.');
      } else {
        content = waiting('w-tv', 'hourglass', 'Watch the TV');
      }
      return ui.shell({ title: 'Antakshari', subtitle: subtitle, secondsLeft: (role === 'wait' || finished) ? null : pd.int(d, 'secondsLeft') }, content);
    };
  };
})();
