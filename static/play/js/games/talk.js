/* Talk games: Hot Takes and 20 Questions. Port of TalkGameControllers.swift
 * (server: games/native_hub/engines/talk.py). The talking happens out loud in
 * the room; the phone carries what one player needs.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, pd = AP.pd;

  var FOR = [C.orange, C.red], AGAINST = [C.cyan, C.blue];
  var YES = [C.green, '#0FA968'], NO = [C.red, '#C81E4A'], SOMETIMES = [C.yellow, C.orange];
  function verdictColor(a) { return a === 'yes' ? C.green : a === 'no' ? C.red : a === 'sometimes' ? C.yellow : C.purple; }

  function statusCard(icon, title, detail, tint) {
    tint = tint || C.cyan;
    return h('div', { class: 'card tinted col center gap12 txt-center pop-in', key: 'st-' + icon + title, style: { '--tint': tint, padding: '24px 18px' } },
      h('div', { class: 'idle', style: { '--dy': '3px', '--sc': '0.03', '--dur': '1.4s', display: 'inline-flex',
          color: tint } }, AP.icon(icon, 42)),
      h('div', { style: { fontSize: '22px', fontWeight: 800 } }, title),
      detail ? h('div', { class: 'c-text2', style: { fontSize: '15px' } }, detail) : null);
  }
  function scrollPage(key, kids) {
    return h('div', { class: 'scroll', key: key }, h('div', { class: 'col gap16', style: { padding: '14px 20px' } }, kids));
  }

  // ---- Hot Takes ---------------------------------------------------------------
  AP.controllers.hot_takes = function (ctx) {
    var lastSpeaking = false, lastPhase = '';
    return function (d) {
      var phase = pd.str(d, 'phase', 'intro'), role = pd.str(d, 'role', 'voter');
      var prompt = pd.str(d, 'prompt'), stance = pd.str(d, 'stance'), hints = pd.strings(d, 'hints');
      var speaking = pd.bool(d, 'isSpeaking'), canVote = pd.bool(d, 'canVote'), hasVoted = pd.bool(d, 'hasVoted');
      var myVote = typeof d.myVote === 'string' ? d.myVote : null;
      var forName = pd.str(d, 'forName', 'FOR'), againstName = pd.str(d, 'againstName', 'AGAINST');
      var forLabel = pd.str(d, 'forLabel', 'YES'), againstLabel = pd.str(d, 'againstLabel', 'NO');
      var result = d.roundResult && typeof d.roundResult === 'object' ? d.roundResult : null;
      var isDebater = role === 'for' || role === 'against';
      var sideColors = role === 'for' ? FOR : AGAINST;
      if (speaking && !lastSpeaking) { AP.haptic.thump(); }
      if (phase !== lastPhase && phase === 'vote' && canVote) { AP.haptic.success(); }
      lastSpeaking = speaking; lastPhase = phase;

      var subtitle = role === 'for' ? 'You argue FOR' : role === 'against' ? 'You argue AGAINST'
        : (phase === 'vote' ? 'Vote for the better argument' : 'Get ready to vote');

      function revealCard() {
        var winnerSide = result && typeof result.winnerSide === 'string' ? result.winnerSide : null;
        var landslide = !!(result && result.landslide);
        if (winnerSide) {
          if (isDebater) {
            var won = winnerSide === role;
            var pts = result && typeof (role === 'for' ? result.forPoints : result.againstPoints) === 'number' ? Math.trunc(role === 'for' ? result.forPoints : result.againstPoints) : 0;
            return statusCard(won ? 'trophy.fill' : 'hand.thumbsup.fill', won ? (landslide ? 'Landslide win!' : 'You won the debate!') : 'Tough crowd',
              pts > 0 ? '+' + pts + ' points' : 'Better luck next time', won ? C.yellow : sideColors[0]);
          }
          var agreed = myVote === winnerSide;
          return statusCard(agreed ? 'checkmark.seal.fill' : 'tv', agreed ? 'Your pick won!' : 'The room disagreed', 'Check the TV for the votes', agreed ? C.green : C.purple);
        }
        return statusCard('equal.circle.fill', 'Dead heat', 'Check the TV for the votes', C.yellow);
      }

      function sideCard() {
        return h('div', { class: 'col center gap10', key: 'side', style: { padding: '22px', borderRadius: 'var(--r-card)', background: AP.grad(sideColors),
            boxShadow: '0 8px 18px ' + AP.alpha(sideColors[0], 0.4) } },
          h('div', { style: { fontSize: '13px', fontWeight: 800, letterSpacing: '3px', color: 'rgba(255,255,255,0.8)' } }, 'YOU ARGUE'),
          h('div', { style: { fontSize: '52px', fontWeight: 900, lineHeight: 1, textShadow: '0 2px 3px rgba(0,0,0,0.25)' } }, role === 'for' ? 'FOR' : 'AGAINST'),
          stance ? h('div', { style: { padding: '5px 14px', borderRadius: '999px', background: '#fff', color: sideColors[0], fontSize: '16px', fontWeight: 800, letterSpacing: '2px' } }, stance) : null,
          h('div', { class: 'txt-center', style: { fontSize: '20px', fontWeight: 700, paddingTop: '4px' } }, prompt));
      }

      var kids = [];
      if (phase === 'final') {
        kids.push(statusCard('trophy.fill', 'That is a wrap!', 'Final scores are on the TV', C.yellow));
      } else if (isDebater) {
        kids.push(sideCard());
        if (phase === 'intro') {
          kids.push(statusCard(role === 'for' ? '1.circle.fill' : '2.circle.fill', role === 'for' ? 'You go first' : 'You go second',
            'Argue out loud for 30 seconds. Use a starter below if you get stuck.', sideColors[0]));
        } else if (phase === 'for' || phase === 'against') {
          if (speaking) {
            kids.push(h('div', { class: 'card tinted col center gap10 txt-center', key: 'speaking', style: { '--tint': sideColors[0], padding: '22px 16px' } },
              h('span', { class: 'idle', style: { '--dy': '0px', '--sc': '0.1', '--dur': '0.6s', color: sideColors[0], display: 'inline-flex' } }, AP.icon('waveform', 48)),
              h('div', { style: { fontSize: '24px', fontWeight: 900 } }, 'You are on! Talk out loud'),
              h('div', { class: 'c-text2', style: { fontSize: '15px' } }, 'Look at the room, not the phone.')));
            kids.push(ui.bigButton({ title: 'I am done', icon: 'checkmark.circle.fill', colors: sideColors, onClick: function () { ctx.send('done_speaking', {}); } }));
          } else if (phase === 'for') {
            kids.push(statusCard('ear.fill', 'Listen closely', 'Your turn is next. Get your comeback ready.', sideColors[0]));
          } else {
            kids.push(statusCard('ear.fill', 'Nice work', 'Now listen to ' + againstName + '.', sideColors[0]));
          }
        } else if (phase === 'switch') {
          kids.push(statusCard('arrow.left.arrow.right', role === 'against' ? 'Your turn now!' : 'Switch!',
            role === 'against' ? 'Get ready to fight back.' : 'Over to ' + againstName + '.', sideColors[0]));
        } else if (phase === 'vote') {
          kids.push(statusCard('hourglass', 'The room is voting', 'Fingers crossed.', sideColors[0]));
        } else if (phase === 'reveal') { kids.push(revealCard()); }
        if (hints.length && ['intro', 'for', 'switch', 'against'].indexOf(phase) >= 0) {
          kids.push(h('div', { class: 'col gap10', key: 'hints' }, ui.sectionLabel('Argument starters'),
            hints.map(function (t, i) {
              return h('div', { class: 'row', key: 'hint' + i, style: { alignItems: 'flex-start', gap: '10px', padding: '14px', borderRadius: 'var(--r-chip)', background: C.surface } },
                h('span', { style: { color: sideColors[0], display: 'inline-flex', paddingTop: '2px' } }, AP.icon('quote.opening', 14)),
                h('span', { style: { fontSize: '16px', fontWeight: 600 } }, t));
            })));
        }
      } else {
        if (phase === 'vote') {
          if (prompt) { kids.push(takeCard(prompt)); }
          kids.push(h('div', { class: 'txt-center', style: { fontSize: '17px', fontWeight: 800, color: hasVoted ? C.green : '#fff' } },
            hasVoted ? 'Vote counted. Tap the other side to change it.' : 'Who argued better?'));
          kids.push(voteButton('FOR', forName, forLabel, FOR, myVote === 'for', canVote, 'for'));
          kids.push(voteButton('AGAINST', againstName, againstLabel, AGAINST, myVote === 'against', canVote, 'against'));
        } else if (phase === 'reveal') { kids.push(revealCard()); }
        else {
          kids.push(statusCard('hand.raised.fill', 'Get ready to vote', 'Listen to both sides. You will pick the better argument.', C.purple));
          if (prompt) { kids.push(takeCard(prompt)); }
          kids.push(versus(forName, againstName, forLabel, againstLabel, phase === 'for' ? 'for' : (phase === 'against' ? 'against' : '')));
        }
      }

      function takeCard(text) {
        return h('div', { class: 'card tinted col center gap6 txt-center', key: 'take', style: { '--tint': C.orange } },
          h('div', { style: { fontSize: '12px', fontWeight: 800, letterSpacing: '2px', color: C.orange } }, 'THE HOT TAKE'),
          h('div', { style: { fontSize: '20px', fontWeight: 800 } }, text));
      }
      function versus(fn, an, fl, al, sp) {
        function col(side, name, label, colors, active) {
          return h('div', { class: 'grow col center gap4', style: { padding: '14px 0', borderRadius: 'var(--r-button)',
              background: active ? AP.alpha(colors[0], 0.25) : C.surface, border: (active ? 2 : 1) + 'px solid ' + AP.alpha(colors[0], active ? 0.9 : 0.2),
              transform: active ? 'scale(1.04)' : 'none', transition: 'transform .38s var(--pop)', minWidth: 0 } },
            h('div', { style: { fontSize: '12px', fontWeight: 800, letterSpacing: '2px', color: colors[0] } }, side),
            h('div', { style: { fontSize: '18px', fontWeight: 800, maxWidth: '100%', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', padding: '0 6px' } }, name),
            h('div', { style: { fontSize: '12px', fontWeight: 700, color: C.text3 } }, label));
        }
        return h('div', { class: 'row gap10', key: 'vs' }, col('FOR', fn, fl, FOR, sp === 'for'),
          h('span', { style: { fontSize: '18px', fontWeight: 900, color: C.text3 } }, 'VS'), col('AGAINST', an, al, AGAINST, sp === 'against'));
      }
      function voteButton(side, name, stanceText, colors, selected, enabled, value) {
        return h('button', { class: 'press', key: 'vote-' + value, disabled: !enabled,
          style: { appearance: 'none', width: '100%', padding: '22px 20px', borderRadius: 'var(--r-button)', color: '#fff',
            background: AP.grad(colors), opacity: selected ? 1 : 0.55, border: '3px solid ' + (selected ? 'rgba(255,255,255,0.9)' : 'transparent'),
            boxShadow: '0 6px 16px ' + AP.alpha(colors[0], selected ? 0.5 : 0.15), transform: selected ? 'scale(1.02)' : 'none',
            transition: 'transform .38s var(--pop), opacity .2s', display: 'flex', alignItems: 'center', gap: '14px', textAlign: 'left' },
          onclick: enabled ? function () { AP.haptic.rigid(); ctx.send('vote', { side: value }); } : null },
          h('span', { class: 'grow col gap4', style: { minWidth: 0 } },
            h('span', { style: { fontSize: '13px', fontWeight: 800, letterSpacing: '1.5px', color: 'rgba(255,255,255,0.85)' } }, side + ' - ' + stanceText),
            h('span', { style: { fontSize: '28px', fontWeight: 900, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' } }, name)),
          AP.icon(selected ? 'checkmark.circle.fill' : 'circle', 30));
      }

      return ui.shell({ title: 'Hot Takes', subtitle: subtitle, secondsLeft: pd.int(d, 'secondsLeft') }, scrollPage('ht-' + phase, kids));
    };
  };

  // ---- 20 Questions ------------------------------------------------------------------
  AP.controllers.twenty_questions = function (ctx) {
    var guessing = false, guessText = '', locked = false, hidden = false, wrongFlash = false;
    var lastPhase = '', lastWrong = -1;
    return function (d) {
      var phase = pd.str(d, 'phase', 'intro'), isAnswerer = pd.bool(d, 'isAnswerer');
      var secret = pd.str(d, 'secret'), category = pd.str(d, 'category');
      var answererName = pd.str(d, 'answererName', 'The Answerer');
      var used = pd.int(d, 'questionsUsed'), left = pd.int(d, 'questionsLeft', 20), maxQ = Math.max(1, pd.int(d, 'maxQuestions', 20));
      var tally = d.tally && typeof d.tally === 'object' ? d.tally : {};
      var lastAnswer = typeof d.lastAnswer === 'string' ? d.lastAnswer : null;
      var canGuess = pd.bool(d, 'canGuess'), wrong = pd.int(d, 'wrongGuesses'), penalty = pd.int(d, 'penalty', 50);
      var result = d.roundResult && typeof d.roundResult === 'object' ? d.roundResult : null;
      var myID = pd.str(d, 'myPlayerID');

      if (phase !== lastPhase) {
        if (phase !== 'ask') { guessing = false; guessText = ''; }
        if (phase === 'intro') { hidden = false; if (isAnswerer) { AP.haptic.thump(); } }
        if (phase === 'reveal') { AP.haptic.success(); }
        lastPhase = phase;
      }
      if (lastWrong >= 0 && wrong > lastWrong) {
        AP.haptic.error(); wrongFlash = true;
        ctx.after(2400, function () { wrongFlash = false; ctx.refresh(); });
      }
      lastWrong = wrong;

      var subtitle = phase === 'final' ? 'Game over' : (isAnswerer ? 'You are the Answerer' : (category ? 'Category: ' + category : 'Ask out loud'));

      function answerButton(title, icon, colors, value) {
        return h('button', { class: 'press', key: 'ans-' + value, disabled: locked,
          style: { appearance: 'none', border: 0, width: '100%', padding: '24px 0', borderRadius: 'var(--r-button)', color: '#fff', background: AP.grad(colors),
            boxShadow: '0 6px 14px ' + AP.alpha(colors[0], 0.35), opacity: locked ? 0.5 : 1, fontSize: '30px', fontWeight: 900, textShadow: '0 1px 2px rgba(0,0,0,0.25)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '12px' },
          onclick: function () {
            if (locked || phase !== 'ask') { return; }
            locked = true; AP.haptic.rigid();
            ctx.send('answer', { value: value });
            ctx.after(700, function () { locked = false; ctx.refresh(); });
            ctx.refresh();
          } }, AP.icon(icon, 26), title);
      }
      function tallyRow() {
        function chip(label, n, color) {
          return h('div', { class: 'grow col center gap4', style: { padding: '10px 0', borderRadius: 'var(--r-chip)', background: AP.alpha(color, 0.12) } },
            h('div', { class: 'num', style: { fontSize: '24px', fontWeight: 900, color: color, lineHeight: 1 } }, String(n)),
            h('div', { style: { fontSize: '10px', fontWeight: 800, letterSpacing: '1px', color: C.text2 } }, label));
        }
        return h('div', { class: 'col gap10', key: 'tally' },
          h('div', { class: 'row gap8' }, chip('YES', typeof tally.yes === 'number' ? tally.yes : 0, C.green), chip('NO', typeof tally.no === 'number' ? tally.no : 0, C.red),
            chip('SOMETIMES', typeof tally.sometimes === 'number' ? tally.sometimes : 0, C.yellow)),
          lastAnswer ? h('div', { class: 'row center', style: { display: 'flex', justifyContent: 'center', gap: '8px' } },
            h('span', { class: 'c-text2', style: { fontSize: '14px' } }, 'Last answer'),
            h('span', { style: { padding: '3px 10px', borderRadius: '999px', background: verdictColor(lastAnswer), color: '#000', fontSize: '14px', fontWeight: 900 } }, lastAnswer.toUpperCase())) : null);
      }
      function submitGuess() {
        var t = guessText.trim();
        if (!canGuess || !t) { return; }
        ctx.send('guess', { text: t });
        guessText = ''; guessing = false; ctx.refresh();
      }

      var kids = [];
      if (phase === 'final') {
        kids.push(statusCard('trophy.fill', 'That is a wrap!', 'Final scores are on the TV', C.yellow));
      } else if (phase === 'reveal') {
        var solved = !!(result && result.solved);
        var solverID = result && typeof result.solverID === 'string' ? result.solverID : '';
        var solverName = result && typeof result.solverName === 'string' ? result.solverName : '';
        var sp = result && typeof result.solverPoints === 'number' ? Math.trunc(result.solverPoints) : 0;
        var ap = result && typeof result.answererPoints === 'number' ? Math.trunc(result.answererPoints) : 0;
        var secretText = secret || (result && typeof result.secret === 'string' ? result.secret : '');
        kids.push(h('div', { class: 'col center gap8', key: 'it-was', style: { padding: '24px', borderRadius: 'var(--r-card)', background: AP.grad([C.purple, C.indigo]) } },
          h('div', { style: { fontSize: '13px', fontWeight: 800, letterSpacing: '3px', color: 'rgba(255,255,255,0.8)' } }, 'IT WAS'),
          h('div', { class: 'txt-center', style: { fontSize: '38px', fontWeight: 900, lineHeight: 1.1 } }, secretText)));
        if (solved && solverID === myID) { kids.push(statusCard('star.fill', 'You got it!', '+' + sp + ' points', C.yellow)); }
        else if (isAnswerer) { kids.push(statusCard(ap > 0 ? 'hand.thumbsup.fill' : 'person.fill.questionmark', ap > 0 ? 'Good game!' : (solved ? 'Solved' : 'Nobody got it'),
          ap > 0 ? '+' + ap + ' Answerer bonus' : 'Check the TV', C.green)); }
        else { kids.push(statusCard('tv', solved ? solverName + ' got it' : 'Nobody got it', 'Check the TV', C.cyan)); }
      } else if (isAnswerer) {
        kids.push(h('div', { class: 'col center gap10', key: 'secret', style: { padding: '20px', borderRadius: 'var(--r-card)', background: AP.grad([C.purple, C.indigo]),
            boxShadow: '0 8px 18px ' + AP.alpha(C.purple, 0.4) } },
          h('div', { class: 'row w100' }, h('span', { class: 'grow', style: { fontSize: '13px', fontWeight: 800, letterSpacing: '3px', color: 'rgba(255,255,255,0.85)' } }, 'YOUR SECRET'),
            h('button', { class: 'press', 'aria-label': 'Toggle secret', style: { appearance: 'none', border: 0, padding: '8px', borderRadius: '50%', background: 'rgba(255,255,255,0.18)', color: '#fff', display: 'inline-flex' },
              onclick: function () { AP.haptic.tap(); hidden = !hidden; ctx.refresh(); } }, AP.icon(hidden ? 'eye.fill' : 'eye.slash.fill', 16))),
          h('div', { style: { fontSize: '14px', fontWeight: 800, letterSpacing: '2px', color: 'rgba(255,255,255,0.75)' } }, category.toUpperCase()),
          h('div', { class: 'txt-center', style: { fontSize: '40px', fontWeight: 900, lineHeight: 1.1, filter: hidden ? 'blur(14px)' : 'none', transition: 'filter .5s var(--smooth)' } }, secret || '...'),
          h('div', { style: { fontSize: '13px', fontWeight: 600, color: 'rgba(255,255,255,0.7)' } }, hidden ? 'Tap the eye to peek' : 'Do not let anyone see this')));
        if (phase === 'intro') {
          kids.push(statusCard('lock.fill', 'Keep it secret', 'Everyone will ask you yes or no questions out loud. Answer each one with a tap.', C.purple));
        } else {
          kids.push(h('div', { class: 'txt-center c-text2', style: { fontSize: '17px', fontWeight: 800 } }, left > 0 ? 'Question ' + Math.min(used + 1, maxQ) + ' of ' + maxQ : 'Out of questions'));
          kids.push(answerButton('YES', 'checkmark', YES, 'yes'), answerButton('NO', 'xmark', NO, 'no'), answerButton('SOMETIMES', 'arrow.left.arrow.right', SOMETIMES, 'sometimes'), tallyRow());
        }
      } else {
        var bars = [];
        for (var i = 0; i < maxQ; i++) { bars.push(h('span', { key: 'qb' + i, style: { flex: '1 1 0', height: '8px', borderRadius: '999px', background: i < used ? C.cyan : 'rgba(255,255,255,0.1)', transition: 'background .3s' } })); }
        kids.push(h('div', { class: 'card tinted col center gap12 txt-center', key: 'cat', style: { '--tint': C.cyan } },
          h('div', { style: { fontSize: '12px', fontWeight: 800, letterSpacing: '3px', color: C.cyan } }, 'CATEGORY'),
          h('div', { style: { fontSize: '36px', fontWeight: 900, lineHeight: 1.1 } }, category || '?'),
          h('div', { class: 'c-text2', style: { fontSize: '14px' } }, answererName + ' knows the answer'),
          phase !== 'intro' ? [h('div', { class: 'row w100', style: { gap: '3px' } }, bars),
            h('div', { class: 'num', style: { fontSize: '15px', fontWeight: 800, color: left <= 5 ? C.red : '#fff' } }, left === 1 ? '1 question left' : left + ' questions left')] : null));
        if (phase === 'ask') {
          kids.push(tallyRow());
          if (wrongFlash) { kids.push(statusCard('xmark.octagon.fill', 'Not it!', '-' + penalty + ' points and one question used', C.red)); }
          if (guessing) {
            kids.push(h('div', { class: 'card tinted col gap12 pop-in', key: 'guessbox', style: { '--tint': C.purple } },
              ui.sectionLabel('Your guess'),
              h('input', { id: 'tq-guess', class: 'answer-field', key: 'tq-guess', type: 'text', placeholder: 'Type it here', value: guessText, maxlength: 60,
                autocomplete: 'off', autocorrect: 'off', enterkeyhint: 'go', style: { fontSize: '22px', fontWeight: 700, borderColor: AP.alpha(C.purple, 0.6) },
                oninput: function (ev) { guessText = ev.target.value.slice(0, 60); ctx.refresh(); },
                onkeydown: function (ev) { if (ev.key === 'Enter') { submitGuess(); } } }),
              ui.bigButton({ title: 'Guess', icon: 'paperplane.fill', colors: [C.purple, C.pink], enabled: canGuess && guessText.trim().length > 0, onClick: submitGuess }),
              ui.ghostButton({ title: 'Cancel', icon: 'xmark', onClick: function () { guessing = false; guessText = ''; ctx.send('cancel_buzz', {}); ctx.refresh(); } })));
          } else {
            kids.push(ui.bigButton({ title: 'I know it!', icon: 'lightbulb.fill', colors: [C.purple, C.pink], enabled: canGuess, onClick: function () {
              guessing = true; ctx.send('buzz', {}); ctx.refresh();
              ctx.after(350, function () { var el = document.getElementById('tq-guess'); if (el) { el.focus(); } });
            } }));
            kids.push(h('div', { class: 'txt-center c-text3', style: { fontSize: '13px' } }, 'A wrong guess costs ' + penalty + ' points and a question.'));
          }
        } else {
          kids.push(statusCard('bubble.left.and.bubble.right.fill', 'Get your questions ready',
            answererName + ' is reading the secret. Ask yes or no questions out loud.', C.cyan));
        }
      }
      return ui.shell({ title: '20 Questions', subtitle: subtitle, secondsLeft: phase === 'ask' ? null : pd.int(d, 'secondsLeft') }, scrollPage('tq-' + phase, kids));
    };
  };
})();
