/* Instant feedback for a tap (port of OptimisticEcho.swift -- keep in step).
 *
 * A vote or answer used to wait for the round trip to the server before the
 * controller reacted. For these actions the reply is known in advance (each
 * patch is exactly the private-state change the engine makes, pinned by
 * tests/test_optimistic_echo.py), so it is shown at once. The server still
 * wins: a rejected tap is corrected by the next private_state, at most
 * HOLD_MS later.
 */
(function () {
  'use strict';
  var AP = window.AP;

  var HOLD_MS = 1500;

  function str(v) { return typeof v === 'string' && v !== '' ? v : null; }

  function patch(game, action, data) {
    data = data || {};
    var key = game + ':' + action;
    switch (key) {
      case 'would_rather:vote': case 'host_lies:vote': case 'hot_takes:vote':
        return str(data.side) ? { myVote: data.side, hasVoted: true, hasSubmitted: true } : null;
      case 'most_likely_to:vote':
        return str(data.targetID) ? { myVoteTargetID: data.targetID, hasVoted: true, hasSubmitted: true } : null;
      case 'odd_one_out:vote':
        return str(data.targetID) ? { myVote: data.targetID, canVote: false } : null;
      case 'bluff_it:submit_lie':
        return str(data.text) ? { myLie: data.text, hasSubmitted: true } : null;
      case 'bluff_it:pick':
        return typeof data.index === 'number' ? { myPick: data.index, hasSubmitted: true } : null;
      case 'herd:answer':
        return str(data.text) ? { myAnswer: data.text, hasSubmitted: true } : null;
      case 'emoji_movie:submit_emoji':
        return str(data.emoji) ? { myEmoji: data.emoji, hasSubmitted: true } : null;
      case 'npat:submit':
        return { myEntry: data, hasSubmitted: true };
      case 'atlas:judge':
        return str(data.verdict) ? { myVote: data.verdict } : null;
      default:
        return null;
    }
  }

  var pending = null;   // { patch, round, phase, until }

  function merge(into, extra) {
    var out = {};
    Object.keys(into || {}).forEach(function (k) { out[k] = into[k]; });
    Object.keys(extra).forEach(function (k) { out[k] = extra[k]; });
    return out;
  }

  AP.optimistic = {
    /** After sending: returns privateData with the predicted change, or null. */
    sent: function (game, action, data, current) {
      var p = patch(game, action, data);
      if (!p) { return null; }
      current = current || {};
      pending = { patch: p, round: current.round, phase: current.phase, until: Date.now() + HOLD_MS };
      return merge(current, p);
    },
    /** A private_state from the server, with any still-pending prediction on top. */
    received: function (incoming) {
      incoming = incoming || {};
      if (!pending) { return incoming; }
      if (Date.now() >= pending.until || incoming.round !== pending.round || incoming.phase !== pending.phase) {
        pending = null;
        return incoming;
      }
      return merge(incoming, pending.patch);
    },
    patch: patch
  };
})();
