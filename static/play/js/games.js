/* Aurora Play web controller: the TV games this controller can play.
 *
 * Same list, names, symbols and seat limits as GameID.meta in
 * ios/Shared/Models/Game.swift (retired games omitted: a room that still
 * carries one gets the same "retired" screen the app shows).
 */
(function () {
  'use strict';
  var AP = window.AP;

  // id: [displayName, icon, minPlayers, maxPlayers, hasPrivateInfo]
  var G = {
    trivia:            ['Trivia', 'brain.head.profile', 2, 10, false],
    poker:             ['Poker', 'suit.spade.fill', 2, 8, true],
    tambola:           ['Tambola', 'circle.grid.3x3.fill', 2, 20, true],
    mafia:             ['Mafia', 'eye.fill', 5, 15, true],
    heist:             ['Heist', 'banknote.fill', 3, 6, true],
    mind_meld:         ['Mind Meld', 'sparkles', 3, 8, false],
    speed_sculptor:    ['Speed Sculptor', 'paintpalette.fill', 3, 8, true],
    connect4:          ['Connect 4', 'square.grid.3x3.fill', 2, 4, false],
    snake_ladder:      ['Snake & Ladder', 'arrow.up.right', 2, 6, false],
    roulette:          ['Roulette', 'record.circle.fill', 1, 8, false],
    raja_mantri:       ['Raja Mantri', 'crown.fill', 4, 4, true],
    bluff_it:          ['Bluff It', 'eye.slash.fill', 3, 16, true],
    last_tap:          ['Last Tap Standing', 'bolt.fill', 2, 20, false],
    herd:              ['Herd', 'person.3.fill', 3, 20, false],
    emoji_movie:       ['Emoji Movie', 'clapperboard.fill', 3, 16, true],
    npat:              ['Name Place Animal Thing', 'a.circle.fill', 2, 20, false],
    antakshari:        ['Antakshari', 'music.note', 2, 20, false],
    atlas:             ['Atlas', 'globe', 2, 12, false],
    most_likely_to:    ['Most Likely To', 'hand.thumbsup.fill', 3, 20, false],
    brain_battle:      ['Brain Battle', 'brain', 2, 12, false],
    truth_or_dare:     ['Truth or Dare', 'bubble.left.and.bubble.right.fill', 1, 20, false],
    cipher_grid:       ['Cipher Grid', 'key.fill', 4, 12, true],
    odd_one_out:       ['Odd One Out', 'eyeglasses', 4, 10, true],
    sealed_auction:    ['Sealed Auction', 'hammer.fill', 2, 8, true],
    wavelength:        ['Wavelength', 'antenna.radiowaves.left.and.right', 3, 10, true],
    bollywood_charades:['Dumb Charades', 'figure.dance', 3, 16, true],
    defuse:            ['Defuse', 'timer.fill', 2, 6, true],
    battleship:        ['Battleship', 'sailboat.fill', 2, 2, true],
    heist_escape:      ['Heist Escape', 'door.left.hand.open', 2, 4, true],
    ludo:              ['Ludo', 'dice.fill', 2, 4, false],
    teen_patti:        ['Teen Patti', 'rectangle.stack.fill', 2, 8, true],
    hot_takes:         ['Hot Takes', 'flame.fill', 3, 8, true],
    twenty_questions:  ['20 Questions', 'questionmark.bubble.fill', 3, 8, true]
  };

  var RETIRED = {
    chess: 'Chess', pong: 'Pong', air_hockey: 'Air Hockey', carrom: 'Carrom',
    blast_runners: 'Blast Runners', neon_snake: 'Neon Snake', twenty48: '2048',
    brick_breaker: 'Brick Breaker', simon_says: 'Simon Says', memory: 'Memory',
    digit_guess: 'Digit Guess', hot_grid: 'Hot Grid', stock_panic: 'Stock Panic',
    kbc: 'KBC Hot Seat', story_chain: 'Story Chain'
  };

  AP.game = function (id) {
    var g = G[id];
    if (g) { return { id: id, name: g[0], icon: g[1], min: g[2], max: g[3], priv: g[4], retired: false }; }
    return { id: id, name: RETIRED[id] || String(id || 'Game').replace(/_/g, ' '), icon: 'gamecontroller.fill',
             min: 1, max: 20, priv: false, retired: true };
  };
  AP.controllers = {};   // gameID -> factory(ctx) -> render(privateData)
})();
