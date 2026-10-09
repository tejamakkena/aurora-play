/* Trivia showdown controller. Port of TriviaControllerView.swift.
 *
 * private_state (games/native_hub/engines/trivia_show.py): phase, secondsLeft,
 * round, questionNumber, totalQuestions, score, rank, categories, myVote,
 * chosenCategory, rivals, myPower, hitBy, shieldBlocked, questionID,
 * questionText, choices, category, showChoices, myAnswer, rung, towerHeight,
 * winnerName, youWon, placement, correctIndex, wasCorrect, pointsEarned,
 * rungMove.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, pd = AP.pd;

  var GOLD = '#FACC15';
  var INK = 'var(--bg)';
  var TILE = ['#FF3D7F', '#3D8BFF', '#FFB020', '#22C77A'];
  var SHAPE = ['triangle.fill', 'diamond.fill', 'circle.fill', 'square.fill'];
  var DOOR = ['#FF4D8D', '#3DA5FF', '#FFB020'];
  var AVATAR = ['#F43F5E', '#F97316', '#EAB308', '#22C55E', '#14B8A6', '#06B6D4', '#3B82F6', '#6366F1', '#A855F7', '#EC4899'];
  var ICE_TAPS = 5;

  function tile(i) { return TILE[((i % 4) + 4) % 4]; }
  function shape(i) { return SHAPE[((i % 4) + 4) % 4]; }
  function avatarColor(id) { return AVATAR[kit.fnv(id) % AVATAR.length]; }
  function initials(name) {
    var words = String(name).split(/[ _-]+/).filter(Boolean).slice(0, 2);
    var out = words.map(function (w) { return w.charAt(0); }).join('');
    return out ? out.toUpperCase() : '?';
  }
  var POWER = {
    freeze: { icon: 'snowflake', color: C.cyan, name: 'Freeze', verb: 'froze', detail: 'They tap 5 times to break the ice' },
    scramble: { icon: 'shuffle', color: C.pink, name: 'Scramble', verb: 'scrambled', detail: 'Their answers keep jumping' },
    fog: { icon: 'cloud.fog.fill', color: C.purple, name: 'Fog', verb: 'fogged', detail: 'Their answers start blurry' },
    shield: { icon: 'shield.fill', color: C.yellow, name: 'Shield', verb: 'zapped', detail: 'Block one power aimed at you' }
  };
  function power(p) { return POWER[p] || { icon: 'bolt.fill', color: C.cyan, name: 'Power', verb: 'zapped', detail: '' }; }

  function ordinal(n) {
    if (n <= 0) { return 'in the game'; }
    var t = n % 100, suffix;
    if (t >= 11 && t <= 13) { suffix = 'th'; } else { suffix = ({ 1: 'st', 2: 'nd', 3: 'rd' })[n % 10] || 'th'; }
    return n + suffix;
  }

  function msg(o) { o.tint = o.tint || GOLD; return kit.message(o); }

  AP.controllers.trivia = function (ctx) {
    var pendingAnswer = null, pendingAnswerID = '';
    var pendingVote = null, pendingVoteKey = '';
    var chosenPower = null, sentPowerKey = '', powerKey = '';
    var lastPhase = '';
    var panel = { qid: null, order: [], iceTaps: 0, iceGone: false, timer: null, powers: [] };
    var count = {};
    var warned = {};

    function send(action, data) { ctx.send(action, data); }

    function resetPanel(qid, choices, powers) {
      if (panel.timer) { ctx.clear(panel.timer); panel.timer = null; }
      panel.qid = qid; panel.iceTaps = 0; panel.iceGone = false; panel.powers = powers;
      panel.order = choices.map(function (_, i) { return i; });
      if (powers.indexOf('scramble') >= 0 && choices.length > 1) {
        panel.timer = ctx.every(1500, function () {
          var before = panel.order.join(',');
          var next = panel.order.slice();
          for (var tries = 0; tries < 8 && next.join(',') === before; tries++) {
            for (var i = next.length - 1; i > 0; i--) {
              var j = Math.floor(Math.random() * (i + 1));
              var t = next[i]; next[i] = next[j]; next[j] = t;
            }
          }
          panel.order = next;
          ctx.refresh();
        });
      }
    }

    return function render(d) {
      var phase = pd.str(d, 'phase');
      var seconds = pd.int(d, 'secondsLeft');
      var questionID = pd.str(d, 'questionID');
      var questionNumber = pd.int(d, 'questionNumber');
      var choices = pd.strings(d, 'choices');
      var score = pd.int(d, 'score');
      var voteKey = 'vote-' + pd.int(d, 'round');
      var currentPowerKey = 'power-' + questionNumber;
      var rivals = pd.dicts(d, 'rivals');

      if (phase !== lastPhase) {
        if (phase === 'power_pick' && powerKey !== currentPowerKey) { powerKey = currentPowerKey; chosenPower = null; }
        lastPhase = phase;
      }

      var myAnswer = typeof d.myAnswer === 'number' ? d.myAnswer
        : (pendingAnswerID === questionID && questionID ? pendingAnswer : null);
      var myVote = typeof d.myVote === 'number' ? d.myVote : (pendingVoteKey === voteKey ? pendingVote : null);
      var myPower = d.myPower && typeof d.myPower === 'object' ? d.myPower : null;
      var hasPicked = !!myPower || sentPowerKey === currentPowerKey;

      var subtitle;
      if (phase === 'finale_intro' || phase === 'finale_question' || phase === 'finale_reveal') {
        subtitle = 'Final Climb - rung ' + pd.int(d, 'rung') + ' of ' + pd.int(d, 'towerHeight', 7);
      } else if (phase === 'summary') { subtitle = "Show's over"; }
      else if (phase === 'intro') { subtitle = 'Get ready'; }
      else { subtitle = 'Question ' + Math.max(questionNumber, 1) + ' of ' + Math.max(pd.int(d, 'totalQuestions'), 1); }

      var showsTimer = ['category_vote', 'power_pick', 'question', 'finale_question'].indexOf(phase) >= 0 && seconds > 0;

      var header = h('div', { class: 'shell-head' },
        h('div', { class: 'col gap4 grow' },
          h('div', { style: { fontSize: '18px', fontWeight: 900, color: GOLD } }, 'TRIVIA SHOWDOWN'),
          h('div', { class: 'c-text2', style: { fontSize: '13px' } }, subtitle)),
        h('div', { class: 'col', style: { alignItems: 'flex-end' } },
          h('div', { class: 'num', style: { fontSize: '22px', fontWeight: 900 } }, String(score)),
          h('div', { style: { fontSize: '10px', fontWeight: 800, letterSpacing: '2px', color: C.text3 } }, 'POINTS')),
        showsTimer ? ui.timerChip(seconds) : null);

      var content;
      switch (phase) {
        case 'intro':
          content = msg({ key: 'intro', icon: 'sparkles', title: 'Welcome to the show!',
            detail: pd.bool(d, 'custom') ? "Tonight's quiz: " + pd.str(d, 'quizName', 'Your quiz')
              : 'Three rounds, sneaky powers and a Final Climb.' });
          break;
        case 'category_vote': content = categoryVote(); break;
        case 'category_reveal':
          content = msg({ key: 'catrev', icon: 'door.left.hand.open', title: pd.str(d, 'chosenCategory', 'Mystery'),
            detail: "That's the category. Eyes on the TV!" });
          break;
        case 'power_pick': content = powerPick(); break;
        case 'power_reveal': content = powerReveal(); break;
        case 'question': case 'finale_question': content = question(); break;
        case 'reveal': case 'finale_reveal': content = reveal(); break;
        case 'standings':
          content = msg({ key: 'stand', icon: 'chart.bar.fill', title: "You're " + ordinal(pd.int(d, 'rank')),
            detail: score + ' points. Watch the standings shuffle on the TV!' });
          break;
        case 'finale_intro':
          content = msg({ key: 'fin', icon: 'flag.checkered', title: 'The Final Climb!',
            detail: 'You start on rung ' + pd.int(d, 'rung') + ' of ' + pd.int(d, 'towerHeight', 7) +
              '. Right answers climb, wrong ones slip. First to the top wins!' });
          break;
        case 'summary': content = summary(); break;
        default: content = msg({ key: 'watch', icon: 'tv', title: 'Watch the TV' });
      }

      return kit.page(C.purple, 0.28, header, h('div', { class: 'shell-body', key: 'body-' + phase }, content));

      // ---- phases ---------------------------------------------------------

      function categoryVote() {
        var cats = pd.strings(d, 'categories');
        var voted = myVote;
        return h('div', { class: 'scroll' },
          h('div', { class: 'col gap16 center', style: { padding: '20px' } },
            h('div', { style: { fontSize: '30px', fontWeight: 900 } }, voted === null ? 'Pick a door!' : 'Vote locked in!'),
            h('div', { class: 'c-text2 txt-center', style: { fontSize: '15px' } },
              voted === null ? 'The most votes opens. Ties are a coin flip.' : 'Waiting for everyone else...'),
            cats.map(function (name, i) { return door(i, name, voted === i, voted !== null && voted !== i); })));
      }
      function door(i, name, picked, dimmed) {
        var color = DOOR[i % DOOR.length];
        return h('button', {
          class: 'press', key: 'door-' + i, disabled: picked || dimmed,
          style: { appearance: 'none', border: picked ? '4px solid #fff' : '0', width: '100%', minHeight: '104px',
            display: 'flex', alignItems: 'center', gap: '16px', padding: '0 18px', color: '#fff', textAlign: 'left',
            borderRadius: 'var(--r-card)', background: 'linear-gradient(180deg, ' + color + ', ' + AP.alpha(color, 0.8) + ')',
            boxShadow: '0 6px 0 ' + AP.alpha(color, 0.55), opacity: dimmed ? 0.35 : 1,
            transform: picked ? 'scale(1.03)' : 'none', transition: 'transform .38s var(--pop), opacity .2s' },
          onclick: function () {
            if (myVote !== null) { return; }
            pendingVote = i; pendingVoteKey = voteKey;
            AP.haptic.thump();
            send('vote_category', { index: i });
            ctx.refresh();
          }
        },
          h('span', { style: { width: '58px', height: '58px', borderRadius: '50%', background: '#fff', color: color,
              display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '34px', fontWeight: 900, flex: '0 0 auto' } }, String(i + 1)),
          h('span', { class: 'grow', style: { fontSize: '24px', fontWeight: 900, lineHeight: 1.1 } }, name),
          AP.icon(picked ? 'checkmark.circle.fill' : 'door.left.hand.closed', 30));
      }

      function powerPick() {
        if (hasPicked) { return powerLocked(); }
        if (chosenPower) { return targetPicker(chosenPower); }
        return powerGrid(rivals.length > 0);
      }
      function sendPower(p, target) {
        if (hasPicked) { return; }
        sentPowerKey = currentPowerKey;
        chosenPower = p;
        AP.haptic.success();
        var payload = { power: p };
        if (target) { payload.targetID = target; }
        send('pick_power', payload);
        ctx.refresh();
      }
      function powerGrid(hasRivals) {
        var cells = ['freeze', 'scramble', 'fog', 'shield'].map(function (p) {
          var usable = p === 'shield' || hasRivals;
          var pw = power(p);
          return h('button', {
            class: 'press', key: 'pw-' + p, disabled: !usable,
            style: { appearance: 'none', minHeight: '190px', padding: '14px', borderRadius: 'var(--r-card)', background: C.surface,
              border: '2px solid ' + AP.alpha(pw.color, 0.7), opacity: usable ? 1 : 0.35, color: '#fff',
              display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '10px', justifyContent: 'center' },
            onclick: function () {
              if (p === 'shield') { sendPower(p, null); }
              else { AP.haptic.tap(); chosenPower = p; ctx.refresh(); }
            }
          },
            kit.disc(pw.icon, 74, pw.color, { solid: true, glow: 10, iconSize: 38 }),
            h('div', { style: { fontSize: '21px', fontWeight: 900 } }, pw.name),
            h('div', { class: 'c-text2 txt-center', style: { fontSize: '13px' } }, pw.detail));
        });
        return h('div', { class: 'scroll' },
          h('div', { class: 'col gap14 center', style: { padding: '20px' } },
            h('div', { style: { fontSize: '30px', fontWeight: 900 } }, 'Power up!'),
            h('div', { class: 'c-text2', style: { fontSize: '15px' } }, 'Throw one at a rival, or shield yourself.'),
            h('div', { style: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px', width: '100%' } }, cells)));
      }
      function targetPicker(p) {
        var pw = power(p);
        return h('div', { class: 'scroll' },
          h('div', { class: 'col gap14 center', style: { padding: '20px' } },
            h('div', { class: 'row w100' },
              h('button', { class: 'btn-pill press', onclick: function () { AP.haptic.tap(); chosenPower = null; ctx.refresh(); } },
                AP.icon('chevron.left', 15), 'Back')),
            kit.disc(pw.icon, 70, pw.color, { solid: true, glow: 0, iconSize: 34 }),
            h('div', { class: 'txt-center', style: { fontSize: '26px', fontWeight: 900 } }, 'Who gets the ' + pw.name + '?'),
            rivals.filter(function (r) { return typeof r.id === 'string'; }).map(function (r) {
              var name = typeof r.name === 'string' ? r.name : 'Player';
              return h('button', {
                class: 'press w100', key: 'rv-' + r.id,
                style: { appearance: 'none', minHeight: '76px', padding: '14px', borderRadius: 'var(--r-button)', background: C.surface,
                  border: '1px solid ' + AP.alpha(pw.color, 0.35), display: 'flex', alignItems: 'center', gap: '14px', color: '#fff' },
                onclick: function () { sendPower(p, r.id); }
              },
                h('span', { style: { width: '52px', height: '52px', borderRadius: '50%', background: avatarColor(r.id),
                    display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '20px', fontWeight: 900, flex: '0 0 auto' } }, initials(name)),
                h('span', { class: 'grow', style: { fontSize: '22px', fontWeight: 800, textAlign: 'left', whiteSpace: 'nowrap',
                    overflow: 'hidden', textOverflow: 'ellipsis' } }, name),
                h('span', { style: { color: pw.color, display: 'inline-flex' } }, AP.icon('scope', 24)));
            })));
      }
      function powerLocked() {
        var p = (myPower && typeof myPower.power === 'string') ? myPower.power : (chosenPower || 'shield');
        var targetID = (myPower && typeof myPower.targetID === 'string') ? myPower.targetID : '';
        var match = rivals.filter(function (r) { return r.id === targetID; })[0];
        var targetName = match && typeof match.name === 'string' ? match.name : 'your rival';
        var line = p === 'shield' ? 'Shield up! The first power thrown at you bounces off.'
          : power(p).name + ' is heading for ' + targetName + '!';
        return msg({ key: 'plocked', icon: power(p).icon, title: 'Power locked in', detail: line, tint: power(p).color });
      }
      function powerReveal() {
        var hits = pd.dicts(d, 'hitBy');
        var blocked = pd.strings(d, 'shieldBlocked');
        if (hits.length) {
          var p = typeof hits[0].power === 'string' ? hits[0].power : '';
          var from = typeof hits[0].fromName === 'string' ? hits[0].fromName : 'Someone';
          if (!warned['hit-' + questionNumber]) { warned['hit-' + questionNumber] = 1; AP.haptic.warning(); }
          return msg({ key: 'hit', icon: power(p).icon, title: 'Uh oh!', tint: power(p).color,
            detail: hits.length > 1 ? 'You got hit by ' + hits.length + ' powers! Get ready...'
              : from + ' ' + power(p).verb + ' you! Get ready...' });
        }
        if (blocked.length) {
          return msg({ key: 'blocked', icon: 'shield.fill', title: 'Blocked!', tint: power('shield').color,
            detail: 'Your shield stopped ' + blocked[0] + '.' });
        }
        return msg({ key: 'flying', icon: 'bolt.fill', title: 'Powers flying!', detail: "You're safe this time. Watch the TV." });
      }

      function activePowers() {
        return phase === 'question' ? pd.dicts(d, 'hitBy').map(function (x) { return x.power; }).filter(function (x) { return typeof x === 'string'; }) : [];
      }

      function question() {
        var category = pd.str(d, 'category');
        var head = h('div', { class: 'col center gap8', style: { padding: '14px 20px 0' } },
          category ? kit.capsule(category.toUpperCase(), GOLD, INK) : null,
          h('div', { class: 'txt-center', style: { fontSize: '21px', fontWeight: 900, lineHeight: 1.2 } }, pd.str(d, 'questionText')));
        var body;
        if (myAnswer !== null) {
          var idx = myAnswer;
          body = h('div', { class: 'col gap16 center pop-in', key: 'locked', style: { padding: '20px 20px 0' } },
            h('div', { style: { width: '84px', height: '84px', borderRadius: '50%', background: GOLD, color: INK,
                display: 'flex', alignItems: 'center', justifyContent: 'center' } }, AP.icon('lock.fill', 40)),
            h('div', { style: { fontSize: '30px', fontWeight: 900 } }, 'Locked in!'),
            h('div', { class: 'row gap12 w100', style: { padding: '14px', borderRadius: 'var(--r-button)', background: AP.alpha(tile(idx), 0.85) } },
              h('span', { style: { width: '36px', height: '36px', borderRadius: '50%', background: '#fff', color: tile(idx),
                  display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' } }, AP.icon(shape(idx), 18)),
              h('span', { style: { fontSize: '19px', fontWeight: 800 } }, idx >= 0 && idx < choices.length ? choices[idx] : '')),
            h('div', { class: 'c-text2', style: { fontSize: '15px' } }, 'Fingers crossed. Watch the TV!'));
        } else if (pd.bool(d, 'showChoices') && choices.length) {
          body = answerPanel();
        } else {
          body = msg({ key: 'read', icon: 'eye.fill', title: 'Read the question...',
            detail: activePowers().length ? "Watch out, you've been hit by a power!" : 'Answers are coming!' });
        }
        return h('div', { class: 'col gap14', style: { flex: '1 1 auto', minHeight: 0 } }, head, body);
      }

      function answerPanel() {
        var powers = activePowers();
        if (panel.qid !== questionID) { resetPanel(questionID, choices, powers); }
        var frozen = powers.indexOf('freeze') >= 0 && !panel.iceGone;
        var fogged = powers.indexOf('fog') >= 0;
        var order = panel.order.length === choices.length ? panel.order : choices.map(function (_, i) { return i; });
        var buttons = h('div', { class: 'col gap12' + (fogged ? ' fog' : ''), key: 'ans-' + questionID,
            style: { pointerEvents: frozen ? 'none' : 'auto' } },
          order.map(function (i) {
            return kit.tile({ key: 'a-' + i, color: tile(i), minHeight: 78, children: [
              h('span', { style: { width: '46px', height: '46px', borderRadius: '50%', background: '#fff', color: tile(i),
                  display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' } }, AP.icon(shape(i), 22)),
              h('span', { class: 'grow', style: { fontSize: '20px', fontWeight: 800, lineHeight: 1.15 } }, choices[i])
            ], onClick: function () { submit(i); } });
          }));
        var ice = (powers.indexOf('freeze') >= 0 && !panel.iceGone) ? iceCard() : null;
        return h('div', { class: 'scroll', style: { padding: '0 20px 16px', position: 'relative' } },
          h('div', { style: { position: 'relative' } }, buttons, ice));
      }
      function iceCard() {
        var taps = panel.iceTaps;
        return h('div', {
          class: 'press', key: 'ice',
          style: { position: 'absolute', inset: 0, borderRadius: 'var(--r-card)', display: 'flex', flexDirection: 'column',
            alignItems: 'center', justifyContent: 'center', gap: '10px', padding: '20px', textAlign: 'center', cursor: 'pointer',
            background: 'linear-gradient(135deg, #E0F7FF, #93D8F7, #5BB8E8)', opacity: 0.96,
            transform: 'scale(' + (1 + taps * 0.012) + ') rotate(' + (taps % 2 === 0 ? 0 : 1.2) + 'deg)',
            transition: 'transform .15s var(--pop)' },
          onclick: function () {
            if (panel.iceGone) { return; }
            panel.iceTaps++;
            if (panel.iceTaps >= ICE_TAPS) { panel.iceGone = true; AP.haptic.success(); } else { AP.haptic.rigid(); }
            ctx.refresh();
          }
        },
          h('span', { style: { color: '#fff', filter: 'drop-shadow(0 0 4px rgba(3,105,161,.6))' } }, AP.icon('snowflake', 54)),
          h('div', { style: { fontSize: '32px', fontWeight: 900, color: '#0C4A6E' } }, 'FROZEN!'),
          h('div', { style: { fontSize: '18px', fontWeight: 700, color: '#075985' } },
            'Tap ' + Math.max(ICE_TAPS - taps, 0) + ' more times to break the ice'));
      }
      function submit(i) {
        if (myAnswer !== null || !questionID) { return; }
        pendingAnswer = i; pendingAnswerID = questionID;
        AP.haptic.tap();
        send('answer', { choiceIndex: i, questionID: questionID });
        ctx.refresh();
      }

      function reveal() {
        var isFinale = phase === 'finale_reveal';
        var answered = typeof d.myAnswer === 'number';
        var was = pd.bool(d, 'wasCorrect');
        var points = pd.int(d, 'pointsEarned');
        var rungMove = pd.int(d, 'rungMove');
        var correctIndex = typeof d.correctIndex === 'number' ? d.correctIndex : 0;
        var correctText = (typeof d.correctIndex === 'number' && d.correctIndex >= 0 && d.correctIndex < choices.length) ? choices[d.correctIndex] : '';
        var tint = was ? C.green : (answered ? C.red : C.purple);
        var title = was ? (isFinale ? 'You climbed!' : 'Correct!') : (!answered ? 'Too slow!'
          : (isFinale && rungMove < 0 ? 'You slipped!' : 'Not quite!'));
        var key = 'reveal-' + questionID;
        var shown = points > 0 ? kit.countUp(ctx, count, key, points) : 0;
        if (!warned[key]) { warned[key] = 1; if (was) { AP.haptic.success(); } else { AP.haptic.error(); } }
        return h('div', { class: 'col center gap16 pop-in', key: key, style: { padding: '24px', flex: '1 1 auto', justifyContent: 'center' } },
          kit.disc(was ? (isFinale ? 'arrow.up' : 'checkmark') : (answered ? 'xmark' : 'hourglass'), 120, tint,
            { solid: true, glow: 20, iconSize: 54 }),
          h('div', { style: { fontSize: '36px', fontWeight: 900 } }, title),
          points > 0 ? h('div', { class: 'num', style: { fontSize: '46px', fontWeight: 900, color: GOLD } }, '+' + shown) : null,
          (!was && correctText) ? h('div', { class: 'col center gap8' },
            h('div', { class: 'c-text2', style: { fontSize: '15px' } }, 'The answer was'),
            h('div', { class: 'row gap10', style: { padding: '12px', borderRadius: 'var(--r-button)', background: AP.alpha(tile(correctIndex), 0.8) } },
              h('span', { style: { width: '32px', height: '32px', borderRadius: '50%', background: '#fff', color: tile(correctIndex),
                  display: 'flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' } }, AP.icon(shape(correctIndex), 16)),
              h('span', { style: { fontSize: '19px', fontWeight: 800 } }, correctText))) : null);
      }

      function summary() {
        var win = pd.bool(d, 'youWon');
        var winnerName = pd.str(d, 'winnerName');
        var rank = pd.int(d, 'placement');
        if (!warned.sum) { warned.sum = 1; if (win) { AP.haptic.success(); } else { AP.haptic.warning(); } }
        return h('div', { class: 'col center gap16 pop-in', key: 'summary', style: { padding: '28px', flex: '1 1 auto', justifyContent: 'center' } },
          h('div', { class: 'idle', style: { '--dy': '4px', '--deg': win ? '4deg' : '0deg', '--sc': '0.03', '--dur': '1.4s' } },
            h('div', { style: { width: '140px', height: '140px', borderRadius: '50%', background: win ? GOLD : C.purple,
                color: win ? INK : '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
                boxShadow: '0 0 24px ' + AP.alpha(GOLD, win ? 0.8 : 0.2) } }, AP.icon(win ? 'crown.fill' : 'star.fill', 64))),
          h('div', { class: 'txt-center', style: { fontSize: '32px', fontWeight: 900 } },
            win ? 'You win the show!' : (winnerName ? winnerName + ' wins!' : 'What a show!')),
          rank > 0 ? h('div', { class: 'c-text2', style: { fontSize: '18px' } }, 'You finished #' + rank + ' with ' + score + ' points') : null);
      }
    };
  };
})();
