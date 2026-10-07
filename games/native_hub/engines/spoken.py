"""Spoken games: the room talks (or sings) out loud, phones only tap.

Atlas and Antakshari used to make players type place names and song titles
into their phones -- the opposite of how either game is played in a living
room. Here the TV is the host and scoreboard, people speak or sing to the
room, and a phone only ever makes a quick tap:

* the room judges (Valid / Out!, Sang it / Missed), because the server
  cannot hear anything;
* whoever just spoke taps the LAST letter of what they said on a 26-letter
  grid, which sets the next required letter.

Neither engine accepts free text as a move. Atlas has one optional,
off-by-default extra: in spelling mode (for kids learning geography) the
speaker may also spell the place, and the TV shows it in the chain.
"""

import random
import string
import time

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines import _content as C

ALPHABET = string.ascii_uppercase
#: Letters almost nothing starts with. Landing on one skips to a fresh
#: letter instead of stalling the room ("skip to a new letter" rule).
HARD_LETTERS = "QXZ"
MAX_PLACE_LEN = 40


def _letter(raw) -> str | None:
    """One A-Z letter, or None for anything else."""
    if not isinstance(raw, str):
        return None
    text = raw.strip().upper()
    return text if len(text) == 1 and text in ALPHABET else None


def _clean_place(raw) -> str:
    if not isinstance(raw, str):
        return ""
    return " ".join(raw.split())[:MAX_PLACE_LEN]


def _payload(data) -> dict:
    return data if isinstance(data, dict) else {}


# ---------------------------------------------------------------------------
# Atlas
# ---------------------------------------------------------------------------

class AtlasEngine(NativeGameEngine):
    """Spoken place-name chain with lives.

    Turn flow: ``say`` (the speaker names a place out loud; everyone else
    taps Valid or Out!) -> ``letter`` (the speaker taps the place's last
    letter) -> next speaker. An Out! majority or the buzzer costs a life and
    shows a short ``verdict`` before the next player gets the same letter.
    Last player standing wins.
    """

    game_id = "atlas"
    min_players = 2
    max_players = 12

    MAX_LIVES = 3
    START_TURN_SECONDS = 10
    MIN_TURN_SECONDS = 5
    LETTER_SECONDS = 12
    VERDICT_SECONDS = 3
    POINTS_PER_PLACE = 10

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.phase = "say"
        self.round = 0                      # turn counter (bots key on it)
        self.letter = ""
        self.order: list[str] = []          # seating order, fixed at start
        self.lives: dict[str, int] = {}
        self.alive: list[str] = []
        self.eliminated: list[str] = []     # first out first
        self.places: dict[str, int] = {}
        self.speaker: str | None = None
        self.deadline = 0.0
        self.turn_seconds = self.START_TURN_SECONDS
        self.turns_taken = 0
        self.votes: dict[str, str] = {}     # judge -> "valid" | "out"
        self.chain: list[dict] = []
        self.verdict: dict | None = None
        self.verdict_seq = 0
        self.skipped: dict | None = None
        self.spelling = False               # optional typed place, off by default
        self.winner: str | None = None
        self._finished = False

    # ---- lifecycle ---------------------------------------------------------

    def start(self, players):
        self.order = [p.id for p in players]
        self.lives = {pid: self.MAX_LIVES for pid in self.order}
        self.places = {pid: 0 for pid in self.order}
        self.alive = list(self.order)
        seed = random.choice(C.ATLAS_SEEDS)
        self.chain = [{"playerID": None, "name": "Start", "place": seed,
                       "letter": seed[0].upper(), "endLetter": seed[-1].upper()}]
        self.letter = seed[-1].upper()
        if self.alive:
            self._begin_turn(self.alive[0])
        else:
            self._finish()

    def _begin_turn(self, pid):
        self.round += 1
        self.speaker = pid
        self.phase = "say"
        self.votes = {}
        self.turn_seconds = self._turn_seconds()
        self.deadline = time.time() + self.turn_seconds

    def _turn_seconds(self) -> int:
        """About 10 s, one second less each full lap of the table."""
        lap = self.turns_taken // max(1, len(self.alive))
        return max(self.MIN_TURN_SECONDS, self.START_TURN_SECONDS - lap)

    def _connected(self, pid) -> bool:
        player = self.room.player(pid)
        return player is not None and player.connected

    def _next_speaker(self) -> str | None:
        if not self.alive:
            return None
        n = len(self.order)
        start = self.order.index(self.speaker) if self.speaker in self.order else -1
        # Skip anyone who is away from the room; fall back to any survivor.
        for need_connected in (True, False):
            for step in range(1, n + 1):
                pid = self.order[(start + step) % n]
                if pid in self.alive and (self._connected(pid) or not need_connected):
                    return pid
        return None

    def _next_turn(self):
        nxt = self._next_speaker()
        if nxt is None:
            self._finish()
            return
        self._begin_turn(nxt)

    def _should_end(self) -> bool:
        if len(self.order) >= 2:
            return len(self.alive) <= 1
        return not self.alive

    def _finish(self):
        self._finished = True
        self.phase = "over"
        self.deadline = 0.0
        if len(self.alive) == 1:
            self.winner = self.alive[0]

    # ---- judging -----------------------------------------------------------

    def judges(self) -> list[str]:
        """Everyone in the room but the speaker -- knocked-out players too."""
        return [p.id for p in self.room.players
                if p.connected and p.id != self.speaker]

    def votes_needed(self) -> int:
        count = len(self.judges())
        return count // 2 + 1 if count else 0

    def _tally(self) -> tuple[int, int]:
        judges = set(self.judges())
        valid = sum(1 for pid, v in self.votes.items() if pid in judges and v == "valid")
        out = sum(1 for pid, v in self.votes.items() if pid in judges and v == "out")
        return valid, out

    def _check_votes(self):
        needed = self.votes_needed()
        if not needed:
            return
        valid, out = self._tally()
        if valid >= needed:
            self._accept()
        elif out >= needed:
            self._strike("out")

    def _flash(self, kind, pid, **extra):
        self.verdict_seq += 1
        self.verdict = {"kind": kind, "playerID": pid, "name": self.player_name(pid),
                        "seq": self.verdict_seq, **extra}

    def _accept(self):
        pid = self.speaker
        self.turns_taken += 1
        self.places[pid] = self.places.get(pid, 0) + 1
        player = self.room.player(pid)
        if player is not None:
            player.score = self.places[pid] * self.POINTS_PER_PLACE
        self.chain.append({"playerID": pid, "name": self.player_name(pid),
                           "place": "", "letter": self.letter, "endLetter": ""})
        self._flash("valid", pid)
        self.phase = "letter"
        self.deadline = time.time() + self.LETTER_SECONDS

    def _strike(self, kind):
        pid = self.speaker
        self.turns_taken += 1
        self.lives[pid] = max(0, self.lives.get(pid, 0) - 1)
        knocked_out = self.lives[pid] == 0
        if knocked_out and pid in self.alive:
            self.alive.remove(pid)
            self.eliminated.append(pid)
        self._flash(kind, pid, livesLeft=self.lives[pid], eliminated=knocked_out)
        # The letter stays: the next player gets the same one.
        self.phase = "verdict"
        self.deadline = time.time() + self.VERDICT_SECONDS

    def _set_letter(self, letter, place="", reason="hard"):
        entry = self.chain[-1] if self.chain else None
        if entry is not None and entry.get("playerID") == self.speaker:
            entry["endLetter"] = letter or ""
            if place:
                entry["place"] = place
        if not letter or letter in HARD_LETTERS:
            fresh = random.choice(C.ATLAS_EASY_LETTERS)
            self.skipped = {"from": letter or "", "to": fresh,
                            "reason": reason if letter else "timeout"}
            letter = fresh
        else:
            self.skipped = None
        self.letter = letter
        self._next_turn()

    # ---- actions -----------------------------------------------------------

    def handle_action(self, player_id, action, data):
        if self._finished:
            return
        data = _payload(data)
        if action == "judge":
            if self.phase != "say" or player_id not in self.judges():
                return
            verdict = data.get("verdict")
            if verdict not in ("valid", "out"):
                return
            self.votes[player_id] = verdict
            self._check_votes()
        elif action == "said":
            # The speaker's own "Next": "I said it", the turn passes.
            if self.phase == "say" and player_id == self.speaker:
                self._accept()
        elif action == "pick_letter":
            if self.phase != "letter" or player_id != self.speaker:
                return
            letter = _letter(data.get("letter"))
            if letter is None:
                return
            player = self.room.player(player_id)
            is_bot = bool(player is not None and player.is_bot)
            # Spelling is optional and off by default. Bots "say" theirs on
            # the TV since they cannot say it out loud.
            place = _clean_place(data.get("place")) if (self.spelling or is_bot) else ""
            self._set_letter(letter, place)
        elif action == "toggle_spelling":
            player = self.room.player(player_id)
            if player is None or not player.is_host:
                return
            on = data.get("on")
            self.spelling = on if isinstance(on, bool) else not self.spelling

    def tick(self, dt):
        if self._finished or not self.deadline or time.time() < self.deadline:
            return
        if self.phase == "say":
            # The buzzer: a turn the room was leaning Valid on still counts.
            valid, out = self._tally()
            if valid > out:
                self._accept()
            else:
                self._strike("timeout")
        elif self.phase == "letter":
            self._set_letter(None, reason="timeout")
        elif self.phase == "verdict":
            if self._should_end():
                self._finish()
            else:
                self._next_turn()

    def on_player_leave(self, player_id):
        self.votes.pop(player_id, None)

    # ---- state -------------------------------------------------------------

    def seconds_left(self) -> int:
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def phase_seconds(self) -> int:
        if self.phase == "say":
            return self.turn_seconds
        if self.phase == "letter":
            return self.LETTER_SECONDS
        if self.phase == "verdict":
            return self.VERDICT_SECONDS
        return 0

    def public_state(self):
        valid, out = self._tally()
        return {
            "phase": self.phase,
            "round": self.round,
            "letter": self.letter,
            "secondsLeft": self.seconds_left(),
            "phaseSeconds": self.phase_seconds(),
            "currentPlayerID": self.speaker,
            "currentName": self.player_name(self.speaker) if self.speaker else "",
            "chain": [dict(e) for e in self.chain[-12:]],
            "chainLength": max(0, len(self.chain) - 1),
            "maxLives": self.MAX_LIVES,
            "players": [
                {"id": pid, "name": self.player_name(pid),
                 "lives": self.lives.get(pid, 0),
                 "isOut": pid not in self.alive,
                 "places": self.places.get(pid, 0),
                 "score": self.places.get(pid, 0) * self.POINTS_PER_PLACE,
                 "isSpeaker": pid == self.speaker}
                for pid in self.order
            ],
            "votes": {"valid": valid, "out": out, "needed": self.votes_needed(),
                      "judges": len(self.judges())},
            "verdict": dict(self.verdict) if self.verdict else None,
            "skipped": dict(self.skipped) if self.skipped else None,
            "spelling": self.spelling,
            "finished": self._finished,
            "winnerID": self.winner,
            "winnerName": self.player_name(self.winner) if self.winner else "",
        }

    def private_state(self, player_id):
        if self.phase == "say":
            role = "speak" if player_id == self.speaker else "judge"
        elif self.phase == "letter":
            role = "pick" if player_id == self.speaker else "wait"
        else:
            role = "wait"
        player = self.room.player(player_id)
        return {
            "phase": self.phase,
            "round": self.round,
            "role": role,
            "letter": self.letter,
            "secondsLeft": self.seconds_left(),
            "phaseSeconds": self.phase_seconds(),
            "isMyTurn": player_id == self.speaker and self.phase in ("say", "letter"),
            "speakerName": self.player_name(self.speaker) if self.speaker else "",
            "myVote": self.votes.get(player_id, ""),
            "lives": self.lives.get(player_id, 0),
            "maxLives": self.MAX_LIVES,
            "isPlaying": player_id in self.lives,
            "isOut": player_id in self.lives and player_id not in self.alive,
            "spelling": self.spelling,
            "isHost": bool(player is not None and player.is_host),
            "hardLetters": list(HARD_LETTERS),
            "finished": self._finished,
        }

    def is_over(self):
        return self._finished

    def results(self):
        """Survivors first, then the latest knocked out; places break ties."""
        out_at = {pid: i for i, pid in enumerate(self.eliminated)}

        def key(pid):
            alive = pid in self.alive
            return (0 if pid == self.winner else 1,
                    0 if alive else 1,
                    -out_at.get(pid, -1),
                    -self.places.get(pid, 0))

        ranked = sorted(self.order, key=key)
        return [
            {"playerID": pid, "name": self.player_name(pid),
             "score": self.places.get(pid, 0) * self.POINTS_PER_PLACE,
             "rank": rank}
            for rank, pid in enumerate(ranked, start=1)
        ]


# ---------------------------------------------------------------------------
# Antakshari
# ---------------------------------------------------------------------------

class AntakshariEngine(NativeGameEngine):
    """Two teams sing in turn; the other team judges.

    Turn flow: ``beat`` (a short break while the TV plays a beat) -> ``sing``
    (the team on turn sings a song starting with the letter; the other
    team's phones show Sang it / Missed) -> on Sang it, ``letter`` (the
    singers tap the last letter of their song) -> the other team sings that
    letter. A miss or the buzzer hands the SAME letter to the other team.
    First to ``TARGET_POINTS`` or the most points after ``GAME_SECONDS``.
    """

    game_id = "antakshari"
    min_players = 2
    max_players = 20

    SING_SECONDS = 30
    LETTER_SECONDS = 12
    BEAT_SECONDS = 4
    TARGET_POINTS = 8
    GAME_SECONDS = 15 * 60
    HINT_AFTER_SECONDS = 12

    DEFAULT_TEAMS = (("a", "Team A", "blue"), ("b", "Team B", "red"))

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.phase = "beat"
        self.round = 0
        self.letter = ""
        self.teams: list[dict] = []          # [{id, name, color, members}]
        self.team_of: dict[str, int] = {}
        self.scores = [0, 0]
        self.singing = 0
        self.deadline = 0.0
        self.turn_started = 0.0
        self.ends_at = 0.0
        self.verdict: dict | None = None
        self.verdict_seq = 0
        self.skipped: dict | None = None
        self.history: list[dict] = []
        self.turn_hint = ""
        self.winner_team: int | None = None
        self._finished = False

    # ---- teams -------------------------------------------------------------

    def _build_teams(self, players):
        ids = [p.id for p in players]
        groups: list[list[str]] = [[], []]
        styles = [list(t) for t in self.DEFAULT_TEAMS]
        placed: set[str] = set()
        data = getattr(self.room, "teams", None)
        room_teams = data.get("teams") if isinstance(data, dict) else None
        if isinstance(room_teams, list) and len(room_teams) >= 2:
            # The room's own teams (games/teams.py). A third or fourth team
            # folds onto the first two -- Antakshari is a two-sided game.
            for i, team in enumerate(room_teams[:2]):
                styles[i] = [str(team.get("id") or styles[i][0]),
                             str(team.get("name") or styles[i][1]),
                             str(team.get("color") or styles[i][2])]
            for i, team in enumerate(room_teams):
                for pid in team.get("members") or []:
                    if pid in ids and pid not in placed:
                        groups[i % 2].append(pid)
                        placed.add(pid)
        for pid in ids:
            if pid not in placed:
                min(groups, key=len).append(pid)
                placed.add(pid)
        # Never leave a side empty when there are people to share out.
        while len(ids) >= 2 and (not groups[0] or not groups[1]):
            big, small = (0, 1) if len(groups[0]) > len(groups[1]) else (1, 0)
            groups[small].append(groups[big].pop())
        self.teams = [{"id": styles[i][0], "name": styles[i][1],
                       "color": styles[i][2], "members": groups[i]} for i in range(2)]
        self.team_of = {pid: i for i in range(2) for pid in groups[i]}

    def judging(self) -> int:
        return 1 - self.singing

    def _members(self, team: int) -> list[str]:
        return list(self.teams[team]["members"]) if 0 <= team < len(self.teams) else []

    # ---- lifecycle ---------------------------------------------------------

    def start(self, players):
        self._build_teams(players)
        self.letter = random.choice(C.ANTAKSHARI_LETTERS)
        self.singing = 0
        now = time.time()
        self.ends_at = now + self.GAME_SECONDS
        self._enter("beat")

    def _enter(self, phase):
        self.phase = phase
        seconds = {"beat": self.BEAT_SECONDS, "sing": self.SING_SECONDS,
                   "letter": self.LETTER_SECONDS}.get(phase, 0)
        self.deadline = time.time() + seconds if seconds else 0.0

    def _start_turn(self):
        self.round += 1
        self.turn_hint = random.choice(C.ANTAKSHARI_HINTS)
        self.turn_started = time.time()
        self._enter("sing")

    def _should_end(self) -> bool:
        return max(self.scores) >= self.TARGET_POINTS or time.time() >= self.ends_at

    def _finish(self):
        self._finished = True
        self.phase = "over"
        self.deadline = 0.0
        a, b = self.scores
        self.winner_team = 0 if a > b else (1 if b > a else None)

    def _sync_player_scores(self):
        for team in range(len(self.teams)):
            for pid in self._members(team):
                player = self.room.player(pid)
                if player is not None:
                    player.score = self.scores[team]

    def _flash(self, kind, team):
        self.verdict_seq += 1
        self.verdict = {"kind": kind, "team": team,
                        "teamName": self.teams[team]["name"] if self.teams else "",
                        "seq": self.verdict_seq}

    def _resolve(self, sang: bool, kind: str):
        team = self.singing
        self.history.append({"team": team, "letter": self.letter,
                             "result": kind, "endLetter": ""})
        self._flash(kind, team)
        if sang:
            self.scores[team] += 1
            self._sync_player_scores()
            if self._should_end():
                self._enter("beat")          # flash the win, then finish
            else:
                self._enter("letter")
        else:
            # The other team gets the letter.
            self.singing = self.judging()
            self._enter("beat")

    def _set_letter(self, letter, reason="hard"):
        if self.history and self.history[-1]["team"] == self.singing:
            self.history[-1]["endLetter"] = letter or ""
        if not letter or letter in HARD_LETTERS:
            fresh = random.choice(C.ANTAKSHARI_LETTERS)
            self.skipped = {"from": letter or "", "to": fresh,
                            "reason": reason if letter else "timeout"}
            letter = fresh
        else:
            self.skipped = None
        self.letter = letter
        self.singing = self.judging()
        self._enter("beat")

    # ---- actions -----------------------------------------------------------

    def handle_action(self, player_id, action, data):
        if self._finished:
            return
        data = _payload(data)
        team = self.team_of.get(player_id)
        if team is None:
            return
        if action == "judge":
            if self.phase != "sing" or team != self.judging():
                return
            verdict = data.get("verdict")
            if verdict == "sang":
                self._resolve(True, "sang")
            elif verdict == "missed":
                self._resolve(False, "missed")
        elif action == "pick_letter":
            if self.phase != "letter" or team != self.singing:
                return
            letter = _letter(data.get("letter"))
            if letter is not None:
                self._set_letter(letter)

    def tick(self, dt):
        if self._finished or not self.deadline or time.time() < self.deadline:
            return
        if self.phase == "beat":
            if self._should_end():
                self._finish()
            else:
                self._start_turn()
        elif self.phase == "sing":
            self._resolve(False, "timeout")
        elif self.phase == "letter":
            self._set_letter(None, reason="timeout")

    # ---- state -------------------------------------------------------------

    def seconds_left(self) -> int:
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def phase_seconds(self) -> int:
        return {"beat": self.BEAT_SECONDS, "sing": self.SING_SECONDS,
                "letter": self.LETTER_SECONDS}.get(self.phase, 0)

    def _hint(self) -> str:
        if self.phase != "sing":
            return ""
        if time.time() - self.turn_started < self.HINT_AFTER_SECONDS:
            return ""
        return self.turn_hint

    def public_state(self):
        return {
            "phase": self.phase,
            "round": self.round,
            "letter": self.letter,
            "secondsLeft": self.seconds_left(),
            "phaseSeconds": self.phase_seconds(),
            "singingTeam": self.singing,
            "teams": [
                {"index": i, "id": t["id"], "name": t["name"], "color": t["color"],
                 "score": self.scores[i],
                 "members": [{"id": pid, "name": self.player_name(pid)}
                             for pid in t["members"]]}
                for i, t in enumerate(self.teams)
            ],
            "target": self.TARGET_POINTS,
            "history": [dict(h) for h in self.history[-10:]],
            "verdict": dict(self.verdict) if self.verdict else None,
            "skipped": dict(self.skipped) if self.skipped else None,
            "hint": self._hint(),
            "gameSecondsLeft": max(0, int(self.ends_at - time.time())) if self.ends_at else 0,
            "finished": self._finished,
            "winnerTeam": self.winner_team,
        }

    def private_state(self, player_id):
        team = self.team_of.get(player_id)
        if team is None:
            role = "wait"
        elif self.phase == "sing":
            role = "sing" if team == self.singing else "judge"
        elif self.phase == "letter":
            role = "pick" if team == self.singing else "wait"
        else:
            role = "wait"
        singing_name = self.teams[self.singing]["name"] if self.teams else ""
        return {
            "phase": self.phase,
            "round": self.round,
            "role": role,
            "letter": self.letter,
            "secondsLeft": self.seconds_left(),
            "phaseSeconds": self.phase_seconds(),
            "myTeam": team if team is not None else -1,
            "myTeamName": self.teams[team]["name"] if team is not None else "",
            "myTeamColor": self.teams[team]["color"] if team is not None else "",
            "singingTeamName": singing_name,
            "teamScores": list(self.scores),
            "target": self.TARGET_POINTS,
            "suggestedLetters": list(C.ANTAKSHARI_LETTERS),
            "hardLetters": list(HARD_LETTERS),
            "finished": self._finished,
        }

    def is_over(self):
        return self._finished

    def results(self):
        """Every singer shares their team's score; the winning side ranks 1."""
        a, b = self.scores
        leader = 0 if a > b else (1 if b > a else None)
        rows = []
        for pid, team in self.team_of.items():
            rank = 1 if leader is None or team == leader else 2
            rows.append({"playerID": pid, "name": self.player_name(pid),
                         "score": self.scores[team], "rank": rank})
        rows.sort(key=lambda r: (r["rank"], -r["score"]))
        return rows


ENGINES = {
    "atlas": AtlasEngine,
    "antakshari": AntakshariEngine,
}
