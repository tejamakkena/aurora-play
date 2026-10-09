"""How-to-play data for every game in the native hub.

This is the single source of truth for the rules interstitial: the
``game_started`` broadcast carries ``rules_for(room.game_id)`` to the TV
and to every phone, and both clients render the same payload. Nothing here
is user-generated, so the text must stay emoji-free (the repo's no-emoji CI
gate scans the clients, and parity keeps this file honest too).

Payload shape per game id::

    {
        "gameID": "trivia",
        "title": "Trivia",
        "objective": "one or two lines",
        "rules": ["3 to 6 bullets"],
        "controls": "how the player drives it",
    }

``rules_for`` falls back to a generic entry for ids with no entry (for
example an id the Swift app knows about that still runs on
``PlaceholderEngine``), so the payload is never missing.
"""

RULES: dict[str, dict] = {
    # ---- Originals -----------------------------------------------------
    "trivia": {
        "title": "Trivia",
        "objective": "Win the quiz show: score big, then reach the top of the Final Climb.",
        "rules": [
            "Vote for a category door on your phone before each round.",
            "Every second question, throw a power at a rival (Freeze, Scramble or Fog) or raise a Shield.",
            "Right answers score 500 points plus up to 500 more for speed.",
            "In the Final Climb, right answers climb a rung and wrong ones slip one.",
            "First to the top of the tower wins the show.",
        ],
        "controls": "Tap doors, powers and answers on your phone.",
    },
    "poker": {
        "title": "Poker",
        "objective": "Win the most chips across the dealt hands.",
        "rules": [
            "Your hole cards stay secret on your phone; the table is on the TV.",
            "Bet, call, raise, or fold on each betting round.",
            "The best five-card hand at showdown takes the pot.",
            "The most chips after the final hand wins.",
        ],
        "controls": "Swipe to size your bet, tap to fold, call, or raise.",
    },
    "tambola": {
        "title": "Tambola",
        "objective": "Claim prizes before anyone else.",
        "rules": [
            "Your ticket is on your phone; numbers are called on the TV.",
            "Tap a number on your ticket the moment it is called.",
            "Early Five, the three lines, and the full house each pay a prize.",
            "Call your claim quickly -- ties go to the first claim.",
        ],
        "controls": "Tap numbers on your ticket.",
    },
    "mafia": {
        "title": "Mafia",
        "objective": "Mafia: eliminate everyone. Villagers: find the Mafia.",
        "rules": [
            "Roles are secret on your phone -- never show the TV.",
            "At night the Mafia picks a target, the Doctor saves, the Detective checks.",
            "By day everyone discusses and votes one player out.",
            "Mafia wins when they match the villagers; villagers win by voting every Mafia out.",
        ],
        "controls": "Tap players on your phone to target or vote.",
    },
    "heist": {
        "title": "Heist",
        "objective": "Pull off the heist without getting caught.",
        "rules": [
            "Crew roles are secret on your phone.",
            "Vote on each heist plan and decide who to trust.",
            "Complete the required missions to grab the loot.",
            "Too many failed missions and the heist collapses.",
        ],
        "controls": "Tap to vote and make your choices.",
    },
    "stock_panic": {
        "title": "Stock Panic",
        "objective": "Finish with the richest portfolio when the market closes.",
        "rules": [
            "Everyone starts with the same portfolio.",
            "Buy and sell on your phone as prices swing on the TV.",
            "Prices move every round -- panic selling locks in losses.",
            "The richest portfolio when the market closes wins.",
        ],
        "controls": "Swipe to buy and sell on your phone.",
    },
    "mind_meld": {
        "title": "Mind Meld",
        "objective": "Match someone else's answer as often as possible.",
        "rules": [
            "Everyone types an answer to the same prompt on their phone.",
            "You score for every answer that matches another player.",
            "Thinking alike beats being original.",
            "The most mind-melds after all rounds wins.",
        ],
        "controls": "Type your answer on your phone.",
    },
    "hot_grid": {
        "title": "Hot Grid",
        "objective": "Grab coins, dodge traps, and finish with the most points.",
        "rules": [
            "Take turns flipping tiles on the shared grid.",
            "Coins score points, traps burn points, teleports award bonus points.",
            "Revealed tiles stay revealed until the grid is cleared.",
            "The most points when the grid is cleared wins.",
        ],
        "controls": "Tap grid cells on your phone.",
    },
    "speed_sculptor": {
        "title": "Speed Sculptor",
        "objective": "Draw fast, guess faster.",
        "rules": [
            "One player draws the secret word on their phone each round.",
            "The drawing appears live on the TV for everyone.",
            "Type your guess on your phone -- faster correct guesses score more.",
            "The best guesser and the best artist share the glory.",
        ],
        "controls": "Draw or type your guess on your phone.",
    },
    "pong": {
        "title": "Pong",
        "objective": "Outscore your opponent.",
        "rules": [
            "Move your paddle up and down to return the ball.",
            "First to the target score wins the match.",
            "Every bounce speeds the ball up -- watch the angle.",
        ],
        "controls": "Tilt your phone to move the paddle.",
    },
    "connect4": {
        "title": "Four in a Row",
        "objective": "Line up four of your discs before anyone else does.",
        "rules": [
            "2 to 4 players, each with their own disc colour.",
            "Drop your discs into the grid on your turn.",
            "The first line of four -- across, down, or diagonal -- wins.",
            "More players means a bigger board: 7 x 9 for three, 8 x 10 for four.",
            "Block your rivals' runs while building your own.",
        ],
        "controls": "Tap a column on your phone.",
    },
    "chess": {
        "title": "Chess",
        "objective": "Capture the opponent's king.",
        "rules": [
            "Simplified chess on the shared board -- no castling or en passant.",
            "Tap a piece, then tap its destination square.",
            "Capturing the king wins; pawns auto-promote to queen.",
            "If a side has no legal moves, the game is a draw.",
        ],
        "controls": "Tap pieces and squares on your phone.",
    },
    "snake_ladder": {
        "title": "Snake & Ladder",
        "objective": "Reach square 100 first.",
        "rules": [
            "Roll the dice on your turn to move forward.",
            "Climb ladders to jump ahead; snakes slide you back down.",
            "Roll a 6 and you roll again (up to three times in a row).",
            "You need the exact roll to land on square 100.",
            "The first token home wins.",
        ],
        "controls": "Tap to roll the dice on your phone.",
    },
    "roulette": {
        "title": "Roulette",
        "objective": "Beat the wheel.",
        "rules": [
            "Place your chips on numbers, colors, or sections.",
            "Watch the wheel spin on the TV.",
            "Winning bets pay out at the odds shown.",
            "The biggest stack when the table closes wins.",
        ],
        "controls": "Swipe and tap to place your bets.",
    },
    "raja_mantri": {
        "title": "Raja Mantri",
        "objective": "Find the Chor -- or be the Chor and get away with it.",
        "rules": [
            "Four roles: Raja, Mantri, Sipahi, and Chor.",
            "The Chor tries to steal the pot without being named.",
            "The Sipahi accuses who the Chor is each round.",
            "Catch the Chor to win; escape with the pot to win as the Chor.",
        ],
        "controls": "Tap on your phone to accuse or act.",
    },
    "memory": {
        "title": "Memory",
        "objective": "Collect the most matching pairs.",
        "rules": [
            "Tiles start face down on the TV.",
            "Flip two tiles on your turn; keep them if they match.",
            "Remember where cards are -- mismatches flip back over.",
            "The most pairs when the board is cleared wins.",
        ],
        "controls": "Tap tiles on your phone.",
    },
    "digit_guess": {
        "title": "Digit Guess",
        "objective": "Crack the secret code in the fewest guesses.",
        "rules": [
            "One player sets a secret multi-digit code.",
            "After each guess you learn how each digit compares.",
            "Use the hints to narrow the code down.",
            "The fewest guesses to crack it wins.",
        ],
        "controls": "Tap digits on your phone.",
    },
    # ---- Party ---------------------------------------------------------
    "bluff_it": {
        "title": "Bluff It",
        "objective": "Write the most convincing fake answer.",
        "rules": [
            "Everyone writes a fake answer to the same question.",
            "All answers -- plus the real one -- appear on the TV.",
            "Vote for the answer you think is true.",
            "You score for spotting the truth and for fooling others.",
        ],
        "controls": "Type and tap on your phone.",
    },
    "last_tap": {
        "title": "Last Tap Standing",
        "objective": "Survive to the last round.",
        "rules": [
            "Wait for the random countdown on the TV.",
            "When GO appears, tap as fast as you can.",
            "The slowest player each round is eliminated.",
            "The last player standing wins.",
        ],
        "controls": "Tap as fast as you can.",
    },
    "herd": {
        "title": "Herd",
        "objective": "Match the majority answer.",
        "rules": [
            "Answer each prompt on your phone.",
            "You score for matching the most popular answer.",
            "Thinking like the crowd beats being clever.",
            "The best herd-matcher after all rounds wins.",
        ],
        "controls": "Type your answer on your phone.",
    },
    "emoji_movie": {
        "title": "Emoji Charades",
        "objective": "Describe and guess movie titles.",
        "rules": [
            "One player describes a movie title using only emoji.",
            "Everyone else guesses the title on their phone.",
            "Faster correct guesses score more for both sides.",
            "The best describers and guessers top the board.",
        ],
        "controls": "Type emoji and tap guesses on your phone.",
    },
    "npat": {
        "title": "Name Place Animal Thing",
        "objective": "Fill all four categories with unique answers.",
        "rules": [
            "A letter is drawn for each round.",
            "Type a Name, Place, Animal, and Thing starting with it.",
            "Unique answers score; answers anyone else also wrote cancel out.",
            "The most points after all rounds wins.",
        ],
        "controls": "Type your answers on your phone.",
    },
    "antakshari": {
        "title": "Antakshari",
        "objective": "Out-sing the other team: first to 8 points, or ahead after 15 minutes.",
        "rules": [
            "Two teams take turns. The TV shows the letter and a 30 second timer.",
            "The team on turn SINGS a song starting with that letter, out loud.",
            "The other team judges on their phones: Sang it scores a point, Missed does not.",
            "After Sang it, the singers tap the last letter of their song to set the next letter.",
            "A miss or the buzzer hands the same letter to the other team. Q, X and Z skip to a new letter.",
        ],
        "controls": "No typing: sing out loud, then tap Sang it, Missed or a letter on your phone.",
    },
    "most_likely_to": {
        "title": "Most Likely To",
        "objective": "Vote honestly, laugh loudly.",
        "rules": [
            "A prompt appears on the TV each round.",
            "Secretly vote for the player it fits best.",
            "Votes are revealed all at once -- defend yourself.",
            "The most-voted players take the round's crown.",
        ],
        "controls": "Tap a player on your phone to vote.",
    },
    "would_rather": {
        "title": "Would You Rather",
        "objective": "Pick a side, then defend it.",
        "rules": [
            "The TV shows a dilemma: would you rather A or B?",
            "Everyone secretly picks a side on their phone.",
            "The reveal shows how the room split, and who chose what.",
            "Going with the crowd scores 100. Standing alone on your side scores 150.",
        ],
        "controls": "Tap A or B on your phone.",
    },
    "truth_or_dare": {
        "title": "Truth or Dare",
        "objective": "Tell the truth or take the dare. Lie and the punishment is worse.",
        "rules": [
            "The host adds everyone's name on their phone, picks a level and starts. Nobody else needs the app.",
            "The TV picks a player at random and asks: truth or dare?",
            "The TV reads the card out loud. Answer honestly, or perform the dare.",
            "You may switch once per turn, from truth to dare or back.",
            "If the room thinks you lied, the host taps Caught lying and you get a bigger punishment.",
            "Truth +1, dare +2, lying -1, skipping a card -1, skipping a punishment -2.",
        ],
        "controls": "Host phone: pick the player's choice, then tap Done, Skip or Caught lying.",
    },
    "brain_battle": {
        "title": "Brain Battle",
        "objective": "Out-think the room across twelve brain puzzles.",
        "rules": [
            "Each round the TV shows a puzzle: patterns, maths, memory, logic, words or shapes.",
            "Memory rounds flash digits on the TV first -- watch closely before they vanish.",
            "Lock in one of four answers on your phone; your first tap is final.",
            "Correct answers score 500 plus up to 500 more for speed.",
            "Puzzles get harder as the game goes on; the top brain wins a title.",
        ],
        "controls": "Tap A, B, C or D on your phone.",
    },
    # ---- Travel Mode (voice-first, one phone, car speakers) ------------
    "story_chain": {
        "title": "Story Chain",
        "objective": "Build the funniest story one sentence at a time.",
        "rules": [
            "Players take turns adding one spoken sentence to the story.",
            "The story so far is read aloud before every turn.",
            "Each player adds two sentences, then the story ends.",
            "Everyone votes for the funniest contributor; the top pick wins bonus points.",
        ],
        "controls": "Type each spoken sentence on the host phone; tap to vote.",
    },
    # ---- Talk games (argue and ask out loud) ---------------------------
    "hot_takes": {
        "title": "Hot Takes",
        "objective": "Win the room's vote by arguing your side out loud.",
        "rules": [
            "Each round two players debate a prompt on the TV: one FOR, one AGAINST.",
            "Your phone shows your side and a few argument starters if you need them.",
            "FOR argues first for 30 seconds, then switch: AGAINST gets 30 seconds.",
            "Everyone else votes on their phone for who argued better.",
            "The winner scores big, with a bonus for a landslide; everyone gets a turn to debate.",
        ],
        "controls": "Talk out loud; tap Done to end your turn early, tap a side to vote.",
    },
    "twenty_questions": {
        "title": "20 Questions",
        "objective": "Work out the secret thing by asking yes or no questions out loud.",
        "rules": [
            "Each round one player is the Answerer and sees the secret on their phone.",
            "The TV shows only the category. Ask yes or no questions out loud.",
            "The Answerer taps Yes, No or Sometimes; every tap uses one of 20 questions.",
            "Tap I know it! to type a guess. Right scores more with questions left; wrong costs points and a question.",
            "The Answerer earns a bonus if the room solves it between questions 10 and 20.",
        ],
        "controls": "Ask out loud; the Answerer taps answers, everyone else taps I know it! to guess.",
    },
    # ---- Mid group -----------------------------------------------------
    "cipher_grid": {
        "title": "Cipher Grid",
        "objective": "Find all of your team's words first.",
        "rules": [
            "Two teams share one 5x5 word grid on the TV.",
            "Only the two spymasters see the color key.",
            "Spymasters give one-word clues; teammates guess the words.",
            "Avoid the assassin -- picking it ends the game instantly.",
        ],
        "controls": "Tap words on your phone.",
    },
    "odd_one_out": {
        "title": "Odd One Out",
        "objective": "Find the Spy -- or bluff as one.",
        "rules": [
            "Everyone gets the same secret location -- except the Spy.",
            "Describe it in one word each round without giving it away.",
            "Vote out who you think the Spy is.",
            "Villagers win by catching the Spy; the Spy wins by naming the location.",
        ],
        "controls": "Type clues and tap to vote on your phone.",
    },
    "sealed_auction": {
        "title": "Sealed Auction",
        "objective": "Win the most valuable items without going broke.",
        "rules": [
            "An item goes up for auction each round.",
            "Everyone bids blind from a private budget on their phone.",
            "The highest bid wins and pays -- the budget never refills.",
            "Overspend early and you are broke for the finale.",
        ],
        "controls": "Enter your bid on your phone.",
    },
    "wavelength": {
        "title": "Spectrum",
        "objective": "Read the psychic's mind.",
        "rules": [
            "One player (the psychic) sees a hidden target on a dial.",
            "They give a spoken clue about where the target sits.",
            "The team places a marker where they think it is.",
            "You score by how close the marker lands to the target.",
        ],
        "controls": "Tap or swipe on your phone to place the marker.",
    },
    "kbc": {
        "title": "KBC Hot Seat",
        "objective": "Climb the prize ladder to the top.",
        "rules": [
            "One player takes the hot seat; the rest form the audience.",
            "Answer questions up a rising prize ladder.",
            "Lifelines: 50:50, Phone-a-Friend, and Audience Poll -- the poll asks the actual room.",
            "Walk away with your winnings or risk it all on the next question.",
        ],
        "controls": "Tap your answer on your phone.",
    },
    "bollywood_charades": {
        "title": "Dumb Charades",
        "objective": "Act it out, guess it fast.",
        "rules": [
            "One player acts out a Bollywood movie -- no speaking.",
            "The room types guesses on their phones.",
            "Faster correct guesses score more for both sides.",
            "The best actors and guessers top the board.",
        ],
        "controls": "Type your guesses on your phone.",
    },
    # ---- Duel and co-op ------------------------------------------------
    "defuse": {
        "title": "Defuse",
        "objective": "Defuse the bomb before the timer hits zero.",
        "rules": [
            "The bomb is on the TV; only your phone has the manual.",
            "Read the instructions out loud to your teammates.",
            "Cut the right wires in the right order.",
            "One wrong snip can end the round.",
        ],
        "controls": "Tap wires and modules on your phone.",
    },
    "battleship": {
        "title": "Sea Battle",
        "objective": "Sink the entire enemy fleet first.",
        "rules": [
            "Place your fleet on your phone's private grid.",
            "Take turns firing at the shared grid on the TV.",
            "Hits and misses are marked for everyone to see.",
            "Sink every enemy ship to win.",
        ],
        "controls": "Tap grid cells on your phone.",
    },
    "air_hockey": {
        "title": "Air Hockey",
        "objective": "Outscore your opponent.",
        "rules": [
            "A real-time puck match plays out on the TV.",
            "Move your paddle to block shots and strike back.",
            "First to the target score wins.",
        ],
        "controls": "Tilt your phone to move the paddle.",
    },
    "heist_escape": {
        "title": "Heist Escape",
        "objective": "Escape the vault together before time runs out.",
        "rules": [
            "The vault map is split across everyone's phones.",
            "Share what you see -- no one has the full picture.",
            "Solve each lock together to reach the next room.",
            "Beat the clock or stay locked in.",
        ],
        "controls": "Tap to solve your piece on your phone.",
    },
    "ludo": {
        "title": "Ludo",
        "objective": "Bring all four of your tokens home first.",
        "rules": [
            "Roll the dice on your turn to move.",
            "A six gets a token out of base and earns another roll.",
            "Land on an opponent to send their token back home.",
            "Start squares and star squares are safe: tokens there can never be captured.",
            "First to bring all four tokens home wins.",
        ],
        "controls": "Shake to roll, tap a token to move.",
    },
    "carrom": {
        "title": "Carrom",
        "objective": "Pocket all of your coins first.",
        "rules": [
            "Flick the striker to pocket your coins.",
            "Aim and power come from a drag on your phone.",
            "Pocket the queen, then cover it with another coin.",
            "Clear all your coins first to win.",
        ],
        "controls": "Drag on your phone to aim and flick.",
    },
    "teen_patti": {
        "title": "Teen Patti",
        "objective": "Take the pot with the best hand.",
        "rules": [
            "Three-card Indian poker on the TV table.",
            "Your cards stay secret on your phone.",
            "Play blind for half the stake, or seen for full.",
            "The best hand at showdown takes the pot.",
        ],
        "controls": "Tap to bet, blind or seen.",
    },
    # ---- Solo ----------------------------------------------------------
    "neon_snake": {
        "title": "Neon Snake",
        "objective": "Grow the longest snake without crashing.",
        "rules": [
            "Steer the snake around the arena.",
            "Eat pellets to grow longer.",
            "Avoid the walls and your own tail.",
            "The snake gets faster the longer you survive.",
        ],
        "controls": "Steer with the Siri Remote D-pad.",
    },
    "twenty48": {
        "title": "2048",
        "objective": "Reach the 2048 tile.",
        "rules": [
            "Slide the tiles; matching numbers merge into one.",
            "Every move spawns a new tile on the board.",
            "The board fills up fast -- plan ahead.",
            "Reach 2048 to win; a full board with no moves ends the run.",
        ],
        "controls": "Swipe on the Siri Remote touch surface.",
    },
    "brick_breaker": {
        "title": "Brick Breaker",
        "objective": "Clear every brick.",
        "rules": [
            "Bounce the ball with your paddle to smash bricks.",
            "Slide to move the paddle -- do not drop the ball.",
            "Some bricks take more than one hit.",
            "Clear all the bricks to advance.",
        ],
        "controls": "Slide on the Siri Remote, or tilt your phone.",
    },
    "simon_says": {
        "title": "Simon Says",
        "objective": "Repeat the longest sequence.",
        "rules": [
            "Watch the four-color sequence light up.",
            "Repeat it back exactly, in order.",
            "The sequence grows by one each round.",
            "One wrong press ends the run.",
        ],
        "controls": "Press with the Siri Remote D-pad.",
    },
    "atlas": {
        "title": "Atlas",
        "objective": "Keep the place-name chain alive and be the last player standing.",
        "rules": [
            "On your turn, SAY a place out loud that starts with the letter on the TV.",
            "Everyone else taps Valid or Out! on their phone; a majority decides.",
            "Tap Next once you have said it, then tap the last letter of your place.",
            "An Out! majority or running out of time costs a life. Three lives each.",
            "The clock gets shorter every lap. Q, X and Z skip to a new letter.",
        ],
        "controls": "No typing: talk out loud, then tap Next, Valid, Out! or a letter on your phone.",
    },
    # ---- Co-op arcade --------------------------------------------------
    "blast_runners": {
        "title": "Blast Runners",
        "objective": "Clear all 25 levels together as a team.",
        "rules": [
            "A 25-level co-op dungeon crawl plays out on the TV.",
            "The whole team shares one life pool -- protect it.",
            "Steer your runner and blast the enemies.",
            "If the shared lives run out, the run ends for everyone.",
        ],
        "controls": "Steer with the D-pad, press the action button to blast.",
    },
}

_FALLBACK = {
    "title": "Game",
    "objective": "Have fun and outscore everyone.",
    "rules": [
        "The rules for this game are on their way.",
        "Follow the prompts on the TV.",
        "Ask the host if anything is unclear.",
    ],
    "controls": "Follow the prompts on the TV.",
}


def rules_for(game_id: str) -> dict:
    """Return the ``game_started`` rules payload for ``game_id``.

    Unknown ids (anything falling back to ``PlaceholderEngine``) get a
    generic entry so the payload shape is never missing.
    """
    entry = RULES.get(game_id, _FALLBACK)
    return {
        "gameID": game_id,
        "title": entry["title"],
        "objective": entry["objective"],
        "rules": list(entry["rules"]),
        "controls": entry["controls"],
    }
