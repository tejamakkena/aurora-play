"""Would You Rather for the TV: everybody votes at once, the TV shows the split.

Each round shows one dilemma ("Would you rather A or B?"). Everyone picks a
side on their phone in secret; the reveal shows the percentage on each side
and who chose what, so the argument can start. Points are light on purpose:
going with the crowd earns 100, and being the only one on your side earns a
150 "brave" bonus. Cards come from the content service, so a table never
sees the same dilemma twice.
"""

from games import content_service as cs
from games.native_hub.engines._bases import RoundBasedEngine

MAJORITY_POINTS = 100
LONE_WOLF_POINTS = 150


class WouldRatherEngine(RoundBasedEngine):
    game_id = "would_rather"
    min_players = 2
    max_players = 20
    total_rounds = 8
    first_phase = "vote"
    phase_seconds = {"vote": 25, "reveal": 9}

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.a = ""
        self.b = ""
        self.used: set[str] = set()
        self.votes: dict[str, str] = {}      # player id -> "a" | "b"
        self.reveal: dict | None = None

    def begin_phase(self, phase):
        if phase == "vote":
            card = cs.pick_one(self.room, "would_rather", avoid=self.used)
            self.a, self.b = card if card else ("fly", "be invisible")
            self.used.add(cs.norm_key(self.a + "|" + self.b))
            self.votes = {}
            self.reveal = None

    def handle_action(self, player_id, action, data):
        if action != "vote" or self.phase != "vote":
            return
        if self.room.player(player_id) is None:
            return
        side = data.get("side") if isinstance(data, dict) else None
        if side not in ("a", "b"):
            return
        self.votes[player_id] = side
        # Mirrored into submissions so the room moves on once everyone voted.
        self.submissions[player_id] = side

    def resolve_phase(self, phase):
        if phase != "vote":
            return None
        a_ids = [pid for pid, s in self.votes.items() if s == "a"]
        b_ids = [pid for pid, s in self.votes.items() if s == "b"]
        total = len(a_ids) + len(b_ids)
        for side_ids, other_ids in ((a_ids, b_ids), (b_ids, a_ids)):
            for pid in side_ids:
                if len(side_ids) >= len(other_ids):
                    self.award(pid, MAJORITY_POINTS)
                elif len(side_ids) == 1:
                    self.award(pid, LONE_WOLF_POINTS)
        self.reveal = {
            "a": len(a_ids), "b": len(b_ids), "total": total,
            "aPercent": round(100 * len(a_ids) / total) if total else 0,
            "bPercent": round(100 * len(b_ids) / total) if total else 0,
            "aNames": [self.player_name(p) for p in a_ids],
            "bNames": [self.player_name(p) for p in b_ids],
        }
        return "reveal"

    def public_state(self):
        state = self.base_public()
        state.update({
            "a": self.a, "b": self.b,
            "votesSoFar": len(self.votes),
            "reveal": self.reveal if self.phase == "reveal" else None,
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "a": self.a, "b": self.b,
            "hasVoted": player_id in self.votes,
            "myVote": self.votes.get(player_id),
        })
        return state

    def on_player_leave(self, player_id):
        super().on_player_leave(player_id)
        self.votes.pop(player_id, None)


ENGINES = {
    "would_rather": WouldRatherEngine,
}
