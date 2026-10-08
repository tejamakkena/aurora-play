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

      var maxTotal = stack + myBet;
      var minRaise = Math.max(Math.min(minBet, maxTotal), tableBet + 1);
      var canRaise = maxTotal > tableBet && minRaise <= maxTotal;
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

      var head = h('div', { class: 'row gap10 px20', style: { paddingTop: '14px' } },
        stat('STACK', chips(stack), GOLD), pot !== null ? stat('POT', chips(pot), '#fff') : null, h('span', { class: 'spacer' }),
        (maxHands > 0 && handNumber > 0) ? h('span', { style: { padding: '7px 12px', borderRadius: '999px', background: C.surface, color: C.text2,
            fontSize: '13px', fontWeight: 800, letterSpacing: '1.5px', whiteSpace: 'nowrap' } }, 'HAND ' + handNumber + '/' + maxHands) : null);

      var peekHint = !hand.length ? 'Waiting for the deal' : (folded ? 'You folded this hand' : (peeking ? 'Let go to hide' : 'Hold to peek at your cards'));
      function peekOn(ev) {
        if (peeking || !hand.length || folded) { return; }
        try { ev.currentTarget.setPointerCapture(ev.pointerId); } catch (e) { /* ignore */ }
        peeking = true; AP.haptic.rigid(); ctx.refresh();
      }
      function peekOff() { if (peeking) { peeking = false; ctx.refresh(); } }
      var cards = hand.length
        ? hand.slice(0, 2).map(function (card, i) {
            return h('div', { class: 'pk-card', key: 'hc' + handNumber + '-' + i, style: { transform: 'rotate(' + (i === 0 ? -4 : 4) + 'deg) translateY(' + (peeking ? -8 : 0) + 'px)',
                transition: 'transform .35s var(--pop) ' + (i * 0.05) + 's' } },
              h('div', { class: 'pk-inner' + ((peeking && !folded) ? ' up' : '') }, back(), face(card)));
          })
        : [0, 1].map(function (i) { return h('div', { class: 'pk-card', key: 'ph' + i, style: { opacity: 0.25 } }, h('div', { class: 'pk-inner' }, back())); });
      var holeCards = h('div', { class: 'row', key: 'hole',
        style: { justifyContent: 'center', gap: '18px', padding: '20px 24px', opacity: folded ? 0.35 : 1, filter: folded ? 'saturate(0)' : 'none', touchAction: 'none', userSelect: 'none' },
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
        bottom = h('div', { key: 'status', style: { margin: '0 20px 32px', padding: '16px 12px', borderRadius: 'var(--r-card)', background: C.surface, textAlign: 'center',
            fontSize: '18px', fontWeight: 700, color: tint } }, text);
      }

      return h('div', { class: 'shell', style: { background: 'radial-gradient(circle 420px at 50% 35%, ' + AP.alpha(C.green, 0.16) + ', transparent), var(--bg)' } },
        head, h('div', { class: 'spacer', style: { minHeight: '8px' } }), holeCards,
        h('div', { class: 'txt-center c-text2', style: { fontSize: '15px', paddingTop: '14px' } }, peekHint),
        h('div', { class: 'spacer', style: { minHeight: '8px' } }), bottom);
    };
  };
})();
