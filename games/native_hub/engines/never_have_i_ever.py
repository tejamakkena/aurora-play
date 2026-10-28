"""Never Have I Ever.

A statement goes up on the TV; everyone answers privately and at the same time,
"I have" or "Never". Then the room finds out who has. Each confession scores a
point, so the final ranking is a tongue-in-cheek "wildest in the room".

The host picks a content pack first (family-safe mix by default, plus themed and
18+ packs). Inside a Game Night the pack is chosen up front on the setup screen
and this step is skipped.
"""

import random

from games.native_hub.engines import _nhie_packs as P
from games.native_hub.engines._bases import RoundBasedEngine

HAVE = "have"
NEVER = "never"


class NeverHaveIEverEngine(RoundBasedEngine):
    game_id = "never_have_i_ever"
    min_players = 2
    max_players = 20
    total_rounds = 10
    first_phase = "answer"
    phase_seconds = {"pack": 25, "answer": 20, "reveal": 9}

    def __init__(self, room, broadcaster) -> None:
        super().__init__(room, broadcaster)
        self.pack_id = P.DEFAULT_PACK
        self.pack_locked = False        # True once a pack was chosen or preset
        self.deck: list[str] = []
        self.statement = ""
        self.confessors: list[str] = []
        self.spotlight: str | None = None

    # ---- configuration -----------------------------------------------------------

    def apply_night_config(self, config: dict) -> None:
        pack = config.get("nhiePack")
        if isinstance(pack, str) and pack in P.PACK_IDS:
            self.pack_id = pack
            self.pack_locked = True
        rounds = config.get("nhieRounds")
        if isinstance(rounds, int) and not isinstance(rounds, bool) and 1 <= rounds <= 30:
            self.total_rounds = rounds

    # ---- round flow --------------------------------------------------------------

    def start_round(self) -> None:
        self.submissions = {}
        # The pack screen only ever appears before the very first statement.
        if self.round == 1 and not self.pack_locked:
            self.enter_phase("pack")
        else:
            self.enter_phase("answer")

    def begin_phase(self, phase: str) -> None:
        if phase == "answer":
            if not self.deck:
                self._build_deck()
            self.statement = self.deck.pop()
            self.confessors = []
            self.spotlight = None

    def _build_deck(self) -> None:
        self.deck = P.statements_for(self.pack_id)
        random.shuffle(self.deck)

    def resolve_phase(self, phase: str) -> str | None:
        if phase == "pack":
            return "answer"
        if phase == "answer":
            self.confessors = [pid for pid, choice in self.submissions.items()
                               if choice == HAVE]
            for pid in self.confessors:
                self.award(pid, 1)
            if self.confessors:
                self.spotlight = random.choice(self.confessors)
            return "reveal"
        return None

    # ---- actions -----------------------------------------------------------------

    def _is_host(self, player_id: str) -> bool:
        player = self.room.player(player_id)
        # A non-player id can only come from the TV's own socket.
        return player is None or player.is_host

    def handle_action(self, player_id: str, action: str, data: dict) -> None:
        if action == "choose_pack":
            if self.phase != "pack" or not self._is_host(player_id):
                return
            pack = data.get("pack")
            if isinstance(pack, str) and pack in P.PACK_IDS:
                self.pack_id = pack
                self.pack_locked = True
                self.deck = []
                self.advance()
        elif action == "answer":
            if self.phase != "answer" or player_id not in self.scores:
                return
            if player_id in self.submissions:
                return                      # first answer stands
            choice = data.get("choice")
            if choice in (HAVE, NEVER):
                self.submissions[player_id] = choice

    # ---- state -------------------------------------------------------------------

    def _names(self, ids: list[str]) -> list[str]:
        return [self.player_name(pid) for pid in ids]

    def _verdict(self) -> str:
        total = len(self.active_players())
        count = len(self.confessors)
        if count == 0:
            return "Nobody? Suspiciously innocent... 🤨"
        if count == 1:
            return f"{self.player_name(self.confessors[0])} stands alone! 😳"
        if total and count >= total:
            return "Everyone has! This room is WILD 🔥"
        if total and count * 2 >= total:
            return "Most of you have. Wow. 👀"
        return f"{count} brave souls confessed 🙋"

    def public_state(self) -> dict:
        state = self.base_public()
        reveal = self.phase == "reveal"
        state.update({
            "statement": self.statement if self.phase in ("answer", "reveal") else "",
            "pack": P.pack_info(self.pack_id),
            "packChoices": P.pack_options() if self.phase == "pack" else [],
            "haveCount": len(self.confessors) if reveal else None,
            "neverCount": (len(self.submissions) - len(self.confessors)) if reveal else None,
            "confessors": self._names(self.confessors) if reveal else [],
            "spotlight": (self.player_name(self.spotlight)
                          if reveal and self.spotlight else None),
            "verdict": self._verdict() if reveal else "",
        })
        return state

    def private_state(self, player_id: str) -> dict:
        state = self.base_private(player_id)
        is_host = self._is_host(player_id)
        state.update({
            "statement": self.statement if self.phase in ("answer", "reveal") else "",
            "myChoice": self.submissions.get(player_id),
            "isHost": is_host,
            "pack": P.pack_info(self.pack_id),
            "packChoices": (P.pack_options()
                            if self.phase == "pack" and is_host else []),
        })
        return state


ENGINES = {"never_have_i_ever": NeverHaveIEverEngine}
