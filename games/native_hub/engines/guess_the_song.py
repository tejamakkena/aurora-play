"""Guess the Song.

A word goes up on the TV and on every phone. The team in play has to name a song
that fits: the word's Hindi meaning, the word in the title, or the word as a prop
in the scene (train -> "Chaiyya Chaiyya"). They shout it out loud; a judge, who is
the only one who can see the answers, taps **Guessed** or **Not guessed**.

* Four or more players split into two teams that take turns, and the judge is
  someone from the *other* team (rotating). With fewer players everyone is one
  team and the host judges.
* Guessed: the team scores, with praise and a joke. Not guessed: the TV reveals
  the answers, with a roast. A humor pack supplies the lines (see ``_humor``).
* The judge can reveal the Hindi word as a hint for a reduced score.

Everything a phone needs is on the phone (the word, the clock, the verdict, the
reveal), so a TV is a bonus rather than a requirement for playing the round.
"""

from games import content_service as cs
from games.native_hub.engines import _humor as H
from games.native_hub.engines._bases import RoundBasedEngine

GUESSED = "guessed"
MISSED = "missed"

GUESS_POINTS = 10
HINT_POINTS = 7

TEAMS = [
    {"name": "Team Chai", "symbol": "cup.and.saucer.fill"},
    {"name": "Team Lassi", "symbol": "leaf.fill"},
]
SOLO_TEAM = {"name": "Everyone", "symbol": "music.note"}
#: Fewer than this and a split into teams would leave one side nearly empty.
TEAM_MIN_PLAYERS = 4


class GuessTheSongEngine(RoundBasedEngine):
    game_id = "guess_the_song"
    min_players = 2
    max_players = 20
    total_rounds = 8
    first_phase = "guess"
    # "verdict" is the grace period after the clock runs out for a judge who was
    # still deciding; if they never answer, it counts as not guessed.
    phase_seconds = {"guess": 60, "verdict": 20, "reveal": 10}

    def __init__(self, room, broadcaster) -> None:
        super().__init__(room, broadcaster)
        self.humor_pack = H.DEFAULT_PACK
        self.team_members: list[list[str]] = [[]]
        self.team_of: dict[str, int] = {}
        self.team_scores: list[int] = [0]
        self.used: set[str] = set()
        self.entry: dict = {"word": "", "hindi": "", "songs": []}
        self.active_team = 0
        self.judge_id: str | None = None
        self.hint_used = False
        self.outcome: str | None = None
        self.humor_line = ""
        self.filler_line = ""

    # ---- configuration -----------------------------------------------------------

    # ---- setup -------------------------------------------------------------------

    def start(self, players) -> None:
        # Inside a Game Night the host picked the humor style on the setup screen.
        party = (getattr(self.room, "night", None) or {}).get("party") or {}
        humor = party.get("humor")
        if isinstance(humor, str) and humor in H.PACK_IDS:
            self.humor_pack = humor
        self._assign_teams(players)
        self.team_scores = [0] * len(self.team_members)
        super().start(players)

    def _assign_teams(self, players) -> None:
        ids = [p.id for p in players]
        if len(ids) >= TEAM_MIN_PLAYERS:
            self.team_members = [ids[0::2], ids[1::2]]
        else:
            self.team_members = [ids]
        self.team_of = {pid: i for i, members in enumerate(self.team_members)
                        for pid in members}

    def _team_info(self, index: int) -> dict:
        if len(self.team_members) == 1:
            base = SOLO_TEAM
        else:
            base = TEAMS[index % len(TEAMS)]
        return {"id": index, "name": base["name"], "symbol": base["symbol"],
                "score": self.team_scores[index] if index < len(self.team_scores) else 0}

    # ---- rounds ------------------------------------------------------------------

    def begin_phase(self, phase: str) -> None:
        if phase != "guess":
            return
        # A word this table has not been given before, from the content service.
        self.entry = (cs.pick_one(self.room, "song_word", avoid=self.used)
                      or {"word": "Train", "hindi": "Rail", "songs": ["Chaiyya Chaiyya (Dil Se)"]})
        self.used.add(cs.norm_key(self.entry["word"]))
        self.hint_used = False
        self.outcome = None
        self.humor_line = ""
        self.filler_line = ""
        self.active_team = (self.round - 1) % len(self.team_members)
        self.judge_id = self._pick_judge()

    def _pick_judge(self) -> str | None:
        connected = {p.id for p in self.room.connected_players()}
        if len(self.team_members) > 1:
            other = 1 - self.active_team
            pool = [pid for pid in self.team_members[other] if pid in connected]
            if pool:
                # Each side judges every other round, rotating through its members.
                return pool[((self.round - 1) // 2) % len(pool)]
        host = self.room.host()
        if host is not None and host.id in self.team_of and host.connected:
            return host.id
        anyone = [pid for pid in self.team_of if pid in connected]
        return anyone[0] if anyone else None

    def resolve_phase(self, phase: str) -> str | None:
        if phase == "guess":
            return "verdict"
        if phase == "verdict":
            self._settle(MISSED)           # the judge never answered
            return "reveal"
        return None

    def _settle(self, result: str) -> None:
        self.outcome = result
        if result == GUESSED:
            points = HINT_POINTS if self.hint_used else GUESS_POINTS
            self.team_scores[self.active_team] += points
            for pid in self.team_members[self.active_team]:
                self.award(pid, points)
        self.humor_line = H.reaction(self.humor_pack, result)
        self.filler_line = H.filler(self.humor_pack)

    # ---- actions -----------------------------------------------------------------

    def _can_judge(self, player_id: str) -> bool:
        if player_id == self.judge_id:
            return True
        player = self.room.player(player_id)
        if player is None:
            return True                   # only a TV socket sends a non-player id
        # The host steps in only if the chosen judge has dropped out.
        judge = self.room.player(self.judge_id) if self.judge_id else None
        return player.is_host and (judge is None or not judge.connected)

    def handle_action(self, player_id: str, action: str, data: dict) -> None:
        if self.phase not in ("guess", "verdict"):
            return
        if action == "judge":
            result = data.get("result")
            if result in (GUESSED, MISSED) and self._can_judge(player_id):
                self._settle(result)
                self.enter_phase("reveal")
        elif action == "hint":
            if self.phase == "guess" and self._can_judge(player_id):
                self.hint_used = True

    # ---- state -------------------------------------------------------------------

    def _teams_view(self) -> list[dict]:
        view = []
        for i, members in enumerate(self.team_members):
            info = self._team_info(i)
            info["members"] = [self.player_name(pid) for pid in members]
            view.append(info)
        return view

    def _answers_visible_to(self, player_id: str | None) -> bool:
        if self.phase == "reveal" and self.outcome == MISSED:
            return True                   # the reveal: everyone sees what they missed
        return player_id is not None and self._can_judge(player_id)

    def public_state(self) -> dict:
        state = self.base_public()
        reveal = self.phase == "reveal"
        state.update({
            "word": self.entry["word"],
            "hint": self.entry["hindi"] if self.hint_used else None,
            "mode": "teams" if len(self.team_members) > 1 else "together",
            "activeTeam": self._team_info(self.active_team),
            "teams": self._teams_view(),
            "judgeName": self.player_name(self.judge_id) if self.judge_id else None,
            "outcome": self.outcome if reveal else None,
            # Never present before the reveal, and only on a miss.
            "answers": (list(self.entry["songs"])
                        if reveal and self.outcome == MISSED else []),
            "humor": self.humor_line if reveal else "",
            "filler": self.filler_line if reveal else "",
        })
        return state

    def private_state(self, player_id: str) -> dict:
        state = self.base_private(player_id)
        reveal = self.phase == "reveal"
        can_judge = self._can_judge(player_id)
        my_team = self.team_of.get(player_id)
        state.update({
            "word": self.entry["word"],
            "hint": self.entry["hindi"] if self.hint_used else None,
            "mode": "teams" if len(self.team_members) > 1 else "together",
            "activeTeam": self._team_info(self.active_team),
            "teams": self._teams_view(),
            "myTeam": self._team_info(my_team) if my_team is not None else None,
            "isGuesser": (my_team == self.active_team and player_id != self.judge_id),
            "isJudge": can_judge,
            "judgeName": self.player_name(self.judge_id) if self.judge_id else None,
            "answers": (list(self.entry["songs"])
                        if self._answers_visible_to(player_id) else []),
            # What the judge may read out as a hint.
            "hindi": self.entry["hindi"] if can_judge else None,
            "outcome": self.outcome if reveal else None,
            "humor": self.humor_line if reveal else "",
            "filler": self.filler_line if reveal else "",
        })
        return state


ENGINES = {"guess_the_song": GuessTheSongEngine}
