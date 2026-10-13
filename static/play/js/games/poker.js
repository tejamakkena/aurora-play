/* Poker controller: private hole cards (hold to peek) plus the betting panel.
 * Port of PokerControllerView.swift. Action payloads are unchanged: "fold",
 * "check"/"call" with no data, and "bet" with {amount} as the raise-to total.
 */
(function () {
  'use strict';
  var AP = window.AP;
  var h = AP.h, C = AP.C, ui = AP.ui, kit = AP.kit, pd = AP.pd;

  var GOLD = C.yellow;
  var SUIT_ICON = { '♥': 'suit.heart.fill', '♦': 'suit.diamond.fill', '♣': 'suit.club.fill' };
  function chips(v) { return Math.trunc(v).toLocaleString('en-US'); }
  function parse(card) { return { rank: card.slice(0, -1), suit: card.slice(-1) }; }
  function isRed(s) { return s === '♥' || s === '♦'; }

  function face(card) {
    var p = parse(card), ink = isRed(p.suit) ? '#d61f2c' : '#121826', icon = SUIT_ICON[p.suit] || 'suit.spade.fill';
    return h('div', { class: 'pk-face front', style: { borderRadius: '11%', background: 'linear-gradient(to bottom, #fff, #eef0f4)', border: '1px solid rgba(0,0,0,0.14)', color: ink } },
      h('div', { class: 'col', style: { position: 'absolute', left: '9%', top: '6%', alignItems: 'center' } },
        h('span', { style: { fontSize: (p.rank.length > 1 ? 34 : 40) + 'px', fontWeight: 800, lineHeight: 1 } }, p.rank),
        h('span', { style: { display: 'inline-flex' } }, AP.icon(icon, 28))),
      h('span', { style: { position: 'absolute', right: '10%', bottom: '10%', display: 'inline-flex' } }, AP.icon(icon, 66)));
  }
  function back(extra) {
    return h('div', { class: 'pk-face' + (extra || ''), style: { borderRadius: '11%', background: '#fff' } },
      h('div', { style: { position: 'absolute', inset: '7%', borderRadius: '7%', background: AP.grad(['#1e3a8a', '#0b1640']),
          border: '2px solid ' + AP.alpha(GOLD, 0.75), display: 'flex', alignItems: 'center', justifyContent: 'center', color: GOLD } }, AP.icon('suit.spade.fill', 40)));
  }

  var RANKS = [
    ['Royal Flush', 'A♠ K♠ Q♠ J♠ 10♠', 'Ace to ten, one suit'],
    ['Straight Flush', '9♥ 8♥ 7♥ 6♥ 5♥', 'Five in a row, one suit'],
    ['Four of a Kind', 'Q♠ Q♥ Q♦ Q♣ 4♠', 'Four cards of one rank'],
    ['Full House', 'K♠ K♥ K♦ 8♣ 8♠', 'Three of a kind plus a pair'],
    ['Flush', 'A♦ J♦ 8♦ 6♦ 2♦', 'Five cards of one suit'],
    ['Straight', '10♠ 9♥ 8♦ 7♣ 6♠', 'Five in a row, any suits'],
    ['Three of a Kind', '7♠ 7♥ 7♦ K♣ 2♠', 'Three cards of one rank'],
    ['Two Pair', 'J♠ J♥ 4♦ 4♣ A♠', 'Two different pairs'],
    ['One Pair', '10♠ 10♥ A♦ 7♣ 3♠', 'Two cards of one rank'],
    ['High Card', 'A♠ J♥ 8♦ 5♣ 2♠', 'None of the above: highest card plays']
  ];
  function showRankings() {
    ui.infoSheet('Hand rankings', h('div', { class: 'col gap8' },
      h('div', { class: 'txt-center c-text2', style: { fontSize: '14px', fontWeight: 600 } }, 'Best hand wins. Strongest at the top.'),
      RANKS.map(function (r, i) {
        return h('div', { key: 'rk' + i, class: 'row gap12', style: { padding: '10px 12px', borderRadius: 'var(--r-chip)', background: C.surface } },
          h('span', { style: { width: '24px', fontSize: '18px', fontWeight: 900, color: GOLD } }, String(i + 1)),
          h('div', { class: 'col', style: { gap: '2px' } },
            h('span', { style: { fontSize: '17px', fontWeight: 800, color: '#fff' } }, r[0]),
            h('span', { style: { fontSize: '17px', fontWeight: 700, color: GOLD, fontFamily: 'ui-monospace, Menlo, monospace' } }, r[1]),
            h('span', { class: 'c-text3', style: { fontSize: '13px' } }, r[2])));
      }),
      h('div', { class: 'txt-center c-text3', style: { fontSize: '13px' } },
        'Each player makes the best five cards from their two cards plus the five on the table.')));
  }

  AP.controllers.poker = function (ctx) {
    var raiseTo = 0, peeking = false, lastCanAct = false, lastMin = -1, lastHand = -1;
    function stat(label, value, tint) {
      return h('div', { class: 'col', style: { padding: '7px 14px', borderRadius: 'var(--r-chip)', background: C.surface } },
        h('span', { style: { fontSize: '11px', fontWeight: 800, letterSpacing: '2px', color: C.text3 } }, label),
        h('span', { class: 'num', style: { fontSize: '22px', fontWeight: 900, color: tint, lineHeight: 1.15 } }, value));
    }
    function actionButton(title, sub, fill, ink, onClick) {
      return h('button', { class: 'press grow', key: 'ab-' + title,
        style: { appearance: 'none', minHeight: '58px', padding: '0 6px', borderRadius: 'var(--r-button)', color: ink,
          background: AP.grad([fill, AP.alpha(fill, 0.75)]), border: '1px solid rgba(255,255,255,0.14)', boxShadow: '0 4px 10px ' + AP.alpha(fill, 0.3),
          display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '1px' },
        onclick: function () { AP.haptic.tap(); onClick(); } },
        h('span', { style: { fontSize: '17px', fontWeight: 900 } }, title),
        sub ? h('span', { class: 'num', style: { fontSize: '14px', fontWeight: 700, opacity: 0.85 } }, sub) : null);
    }
    function quick(title, onClick) {
      return h('button', { class: 'press grow', key: 'q-' + title,
        style: { appearance: 'none', padding: '10px 0', borderRadius: '999px', background: C.surface2, border: '1px solid rgba(255,255,255,0.12)',
          color: 'rgba(255,255,255,0.85)', fontSize: '14px', fontWeight: 700 },
        onclick: function () { AP.haptic.tap(); onClick(); } }, title);
    }

    return function (d) {
      function num(k) { var v = d[k]; return typeof v === 'number' ? Math.trunc(v) : null; }
      var hand = pd.strings(d, 'hand');
      var stack = num('chips') || 0, canAct = pd.bool(d, 'isMyTurn');
      var minBet = num('minBet') || 0, toCall = num('toCall') || 0, myBet = num('myBet') || 0;
      var tableBet = num('currentBet') !== null ? num('currentBet') : (myBet + toCall);
      var pot = num('pot');
      var folded = pd.bool(d, 'folded'), allIn = pd.bool(d, 'allIn');
      var handNumber = num('handNumber') || 0, maxHands = num('maxHands') || 0;
      var unlimited = pd.bool(d, 'unlimited'), rebuysOn = pd.bool(d, 'rebuys');
      var canRebuy = pd.bool(d, 'canRebuy'), isBroke = pd.bool(d, 'isBroke'), votedEnd = pd.bool(d, 'votedEnd');
      var buyIns = num('buyIns') || 1, net = num('net') || 0, tableStack = num('stack') || 1000;
      var endVotes = num('endVotes') || 0, endNeeded = num('endVotesNeeded') || 0;

      var maxTotal = stack + myBet;
      var minRaise = Math.max(Math.min(minBet, maxTotal), tableBet + 1);
      var raiseAllowed = d.canRaise !== false;   // the table caps raises per street
      var canRaise = raiseAllowed && maxTotal > tableBet && minRaise <= maxTotal;
      if ((canAct && !lastCanAct) || minRaise !== lastMin) { raiseTo = minRaise; }
      lastCanAct = canAct; lastMin = minRaise;
      if (handNumber !== lastHand) { peeking = false; lastHand = handNumber; }
      var raw = Math.round(raiseTo), raiseAmount;
      if (raw >= maxTotal) { raiseAmount = maxTotal; } else { raiseAmount = Math.min(maxTotal, Math.max(minRaise, Math.floor(raw / 10) * 10)); }

      var lastHandText = null;
      if (pd.str(d, 'phase') === 'showdown' && d.lastHand && Array.isArray(d.lastHand.winnerNames)) {
        var who = d.lastHand.winnerNames.filter(function (x) { return typeof x === 'string'; }).join(' & ');
        if (who) {
          var amount = typeof d.lastHand.amount === 'number' ? Math.trunc(d.lastHand.amount) : 0;
          lastHandText = (typeof d.lastHand.handName === 'string' && d.lastHand.handName)
            ? who + ' won ' + chips(amount) + ' with ' + d.lastHand.handName : who + ' won ' + chips(amount);
        }
      }

      var infoBtn = h('button', { class: 'press', key: 'info', 'aria-label': 'Poker hand rankings',
        style: { appearance: 'none', background: 'none', border: '0', color: C.text2, width: '44px', height: '44px', display: 'inline-flex',
          alignItems: 'center', justifyContent: 'center' },
        onclick: function () { AP.haptic.tap(); showRankings(); } }, AP.icon('info.circle.fill', 26));
      var head = h('div', { class: 'row gap10 px20', style: { paddingTop: '14px' } },
        infoBtn, stat('STACK', chips(stack), GOLD), pot !== null ? stat('POT', chips(pot), '#fff') : null, h('span', { class: 'spacer' }),
        ((maxHands > 0 || unlimited) && handNumber > 0) ? h('span', { style: { padding: '7px 12px', borderRadius: '999px', background: C.surface, color: C.text2,
            fontSize: '13px', fontWeight: 800, letterSpacing: '1.5px', whiteSpace: 'nowrap' } }, unlimited ? 'HAND ' + handNumber : 'HAND ' + handNumber + '/' + maxHands) : null);

      var peekHint = !hand.length ? 'Waiting for the deal' : (peeking ? 'Let go to hide' : (folded ? 'You folded. Hold to peek at your cards' : 'Hold to peek at your cards'));
      function peekOn(ev) {
        if (peeking || !hand.length) { return; }
        try { ev.currentTarget.setPointerCapture(ev.pointerId); } catch (e) { /* ignore */ }
        peeking = true; AP.haptic.rigid(); ctx.refresh();
      }
      function peekOff() { if (peeking) { peeking = false; ctx.refresh(); } }
      var cards = hand.length
        ? hand.slice(0, 2).map(function (card, i) {
            return h('div', { class: 'pk-card', key: 'hc' + handNumber + '-' + i, style: { transform: 'rotate(' + (i === 0 ? -4 : 4) + 'deg) translateY(' + (peeking ? -8 : 0) + 'px)',
                transition: 'transform .35s var(--pop) ' + (i * 0.05) + 's' } },
              h('div', { class: 'pk-inner' + (peeking ? ' up' : '') }, back(), face(card)));
          })
        : [0, 1].map(function (i) { return h('div', { class: 'pk-card', key: 'ph' + i, style: { opacity: 0.25 } }, h('div', { class: 'pk-inner' }, back())); });
      var holeCards = h('div', { class: 'row', key: 'hole',
        style: { justifyContent: 'center', gap: '18px', padding: '20px 24px', opacity: folded ? (peeking ? 0.85 : 0.5) : 1, filter: (folded && !peeking) ? 'saturate(0.2)' : 'none', touchAction: 'none', userSelect: 'none' },
        onpointerdown: peekOn, onpointerup: peekOff, onpointercancel: peekOff, onlostpointercapture: peekOff, oncontextmenu: function (e) { e.preventDefault(); } }, cards);

      var bottom;
      if (canAct) {
        var lo = minRaise, hi = maxTotal;
        function pot_(f) { return tableBet + ((pot || 0) + toCall) * f; }
        function clamp(v) { return Math.min(hi, Math.max(lo, v)); }
        var callTitle = toCall <= 0 ? 'Check' : (toCall >= stack ? 'Call all in' : 'Call');
        var raiseTitle = raiseAmount >= maxTotal ? 'All in' : (tableBet > 0 ? 'Raise to' : 'Bet');
        var raiseControls = canRaise ? h('div', { class: 'col gap10', key: 'rc' },
          h('div', { class: 'row', style: { alignItems: 'baseline' } },
            h('span', { class: 'grow', style: { fontSize: '13px', fontWeight: 800, letterSpacing: '2px', color: C.text3 } },
              raiseAmount >= maxTotal ? 'ALL IN' : (tableBet > 0 ? 'RAISE TO' : 'BET')),
            h('span', { class: 'num', style: { fontSize: '34px', fontWeight: 900, color: raiseAmount >= maxTotal ? C.red : GOLD } }, chips(raiseAmount))),
          hi > lo ? kit.slider({ key: 'raise', min: lo, max: hi, value: Math.min(hi, Math.max(lo, raiseTo)), tint: GOLD,
            onInput: function (v) { raiseTo = v; ctx.refresh(); } }) : null,
          h('div', { class: 'row gap8' }, quick('Min', function () { raiseTo = lo; ctx.refresh(); }),
            quick('1/2 Pot', function () { raiseTo = clamp(pot_(0.5)); ctx.refresh(); }),
            quick('Pot', function () { raiseTo = clamp(pot_(1)); ctx.refresh(); }),
            quick('All in', function () { raiseTo = hi; ctx.refresh(); }))) : null;
        bottom = h('div', { class: 'slide-in', key: 'panel', style: { margin: '0 16px 20px', padding: '16px', borderRadius: 'var(--r-card)', background: C.surface,
            border: '1.5px solid ' + AP.alpha(GOLD, 0.35) } },
          h('div', { class: 'col gap14' },
            h('div', { class: 'row' }, h('span', { class: 'grow', style: { fontSize: '15px', fontWeight: 900, letterSpacing: '3px', color: GOLD } }, 'YOUR TURN'),
              h('span', { class: 'c-text2', style: { fontSize: '15px', fontWeight: 700 } }, toCall > 0 ? 'To call: ' + chips(toCall) : 'Nothing to call')),
            raiseControls,
            (!raiseAllowed && tableBet > 0) ? h('div', { class: 'c-text2', key: 'cap', style: { fontSize: '14px', fontWeight: 600 } }, 'Raise limit reached this street') : null,
            h('div', { class: 'row gap10' },
              actionButton('Fold', null, C.red, '#fff', function () { ctx.send('fold', {}); }),
              actionButton(callTitle, toCall > 0 ? chips(toCall) : null, C.surface2, '#fff', function () { ctx.send(toCall > 0 ? 'call' : 'check', {}); }),
              canRaise ? actionButton(raiseTitle, chips(raiseAmount), GOLD, 'var(--bg)', function () { ctx.send('bet', { amount: raiseAmount }); }) : null)));
      } else {
        var text, tint = C.text2;
        if (lastHandText) { text = lastHandText; tint = GOLD; }
        else if (folded) { text = 'Folded -- sit tight for the next hand'; }
        else if (allIn) { text = "You're all in!"; tint = C.red; }
        else { text = 'Waiting for your turn'; }
        var controls = [];
        if (rebuysOn && (buyIns > 1 || net !== 0)) {
          controls.push(h('div', { key: 'net', class: 'txt-center', style: { fontSize: '14px', fontWeight: 700, color: net >= 0 ? GOLD : C.text2 } },
            'Bought in ' + buyIns + 'x  |  Net ' + (net >= 0 ? '+' : '-') + chips(Math.abs(net))));
        }
        if (canRebuy) {
          controls.push(actionButton('Buy back in', '+' + chips(tableStack), GOLD, 'var(--bg)', function () { ctx.send('rebuy', {}); }));
          if (isBroke) {
            controls.push(h('button', { key: 'sit', class: 'press', style: { appearance: 'none', background: 'none', border: '0', color: C.text2,
                fontSize: '15px', fontWeight: 700, padding: '8px' }, onclick: function () { AP.haptic.tap(); ctx.send('sit_out', {}); } }, 'Sit this hand out'));
          }
        }
        if (unlimited) {
          controls.push(h('button', { key: 'end', class: 'press', style: { appearance: 'none', width: '100%', padding: '12px', borderRadius: 'var(--r-button)',
              background: C.surface, border: '0', fontSize: '15px', fontWeight: 800, color: votedEnd ? C.red : C.text2 },
            onclick: function () { AP.haptic.tap(); ctx.send('vote_end', {}); } },
            votedEnd ? 'You want to end (' + endVotes + '/' + endNeeded + '). Tap to undo' : 'End the game (' + endVotes + '/' + endNeeded + ' agree)'));
        }
        bottom = h('div', { key: 'status', class: 'col gap12', style: { margin: '0 20px 32px' } }, controls,
          h('div', { style: { padding: '16px 12px', borderRadius: 'var(--r-card)', background: C.surface, textAlign: 'center',
            fontSize: '18px', fontWeight: 700, color: tint } }, text));
      }

      return h('div', { class: 'shell', style: { background: 'radial-gradient(circle 420px at 50% 35%, ' + AP.alpha(C.green, 0.16) + ', transparent), var(--bg)' } },
        head, h('div', { class: 'spacer', style: { minHeight: '8px' } }), holeCards,
        h('div', { class: 'txt-center c-text2', style: { fontSize: '15px', paddingTop: '14px' } }, peekHint),
        h('div', { class: 'spacer', style: { minHeight: '8px' } }), bottom);
    };
  };
})();
