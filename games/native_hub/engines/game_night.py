"""Game Night: an evening of games, hosted in a single room.

The host (normally the iPad) sets the occasion, the guest of honour, a voice and
a lineup of games. The TV shows a welcome screen until the host presses start,
then a voice welcomes everyone, announces tonight's games, and the room plays
through them one after another with a running tally between rounds.

How it fits the hub: this is an ordinary ``NativeGameEngine`` that *hosts* other
engines. While a hosted game is on screen, ``public_state`` / ``private_state``
are the hosted engine's own, so its existing TV board and phone controller work
untouched. Everything the Game Night itself needs to show (the welcome, the
lineup, the tally) goes out separately -- to phones inside ``private_state``
under a ``night`` key, to the TV on its own ``night_state`` channel -- because
each TV board owns the single ``game_state`` handler.

Phases::

    setup -> welcome -> lineup -> [ intro -> playing -> interlude ]* -> finale -> done

Speech is performed by the TV. The engine publishes an ``announce`` (an id plus
the lines to say); the TV speaks it and reports ``night_announce_done`` when it
finishes. A deadline estimated from the text is the fallback if the TV never
reports back, and a minimum hold keeps each screen up long enough to read.

All verbs are prefixed ``night_`` so they can never collide with the hosted
game's own verbs.
"""

import logging
import time

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines import _humor as H
from games.native_hub.engines import _nhie_packs as P
from games.native_hub.engines import _night_content as N
from utils.room_manager import Player

logger = logging.getLogger(__name__)

#: Phases in which the TV is reading something out and we are waiting on it.
ANNOUNCE_PHASES = ("welcome", "lineup", "intro", "interlude", "finale")


class GameNightEngine(NativeGameEngine):
    game_id = "game_night"
    min_players = 1
    max_players = 20
    late_join = True

    def __init__(self, room, broadcaster) -> None:
        super().__init__(room, broadcaster)
        # Instance attributes shadow the class defaults while a hosted game
        # is running, so the pump ticks as fast as that game needs.
        self.tick_hz = 0.0
        self.heavy_state = False

        self.config: dict = N.clean_config(room.night_config or {}, N.default_config())
        self.phase = "setup"
        self.deadline = 0.0          # fallback: advance when this passes
        self.hold_until = 0.0        # earliest the TV may advance us
        self.announce: dict | None = None
        self._announce_seq = 0

        self.playlist: list[str] = []
        self.index = -1
        self.inner: NativeGameEngine | None = None
        self.inner_gid: str | None = None
        self.inner_roster: list[str] = []
        self.skip_notes: list[str] = []

        self.night_scores: dict[str, int] = {}
        self.log: list[dict] = []
        self._finished = False

    # ---- lifecycle ---------------------------------------------------------------

    def start(self, players: list[Player]) -> None:
        self.night_scores = {p.id: 0 for p in players}
        self.phase = "setup"

    def on_player_join(self, player: Player) -> None:
        self.night_scores.setdefault(player.id, 0)

    def on_player_leave(self, player_id: str) -> None:
        if self.inner is not None and player_id in self.inner_roster:
            try:
                self.inner.on_player_leave(player_id)
            except Exception:
                logger.exception("hosted on_player_leave failed room=%s", self.room.code)

    def stop(self) -> None:
        self._drop_inner()

    def is_over(self) -> bool:
        return self._finished

    def results(self) -> list[dict]:
        scores = {p.id: self.night_scores.get(p.id, 0) for p in self.room.players}
        return self.ranked_results(scores)

    # ---- who may drive -----------------------------------------------------------

    def _is_director(self, player_id: str) -> bool:
        """The host phone, or the TV. A non-player id can only reach the engine
        from a TV socket (``handle_game_action`` rejects it from anywhere else),
        which is what lets the Siri Remote act as a fallback host."""
        player = self.room.player(player_id)
        if player is None:
            return True
        return player.is_host and player.connected

    # ---- actions -----------------------------------------------------------------

    def handle_action(self, player_id: str, action: str, data: dict) -> None:
        if not isinstance(data, dict):
            data = {}

        if action.startswith("night_"):
            self._night_action(player_id, action, data)
            return

        if (self.phase == "playing" and self.inner is not None
                and player_id in self.inner_roster):
            try:
                self.inner.handle_action(player_id, action, data)
            except Exception:
                logger.exception("hosted action failed room=%s action=%s",
                                 self.room.code, action)
            self._check_inner_over()

    def _night_action(self, player_id: str, action: str, data: dict) -> None:
        if action == "night_announce_done":
            self._on_announce_done(player_id, data)
            return

        if action == "night_claim_host":
            # The first phone in is host, which is not always the iPad.
            if self.phase == "setup" and self.room.player(player_id) is not None:
                for p in self.room.players:
                    p.is_host = (p.id == player_id)
            return

        if not self._is_director(player_id):
            return

        if action == "night_configure" and self.phase == "setup":
            self._apply_config(data.get("config"))
        elif action == "night_preview" and self.phase == "setup":
            self._apply_config(data.get("config"))
            self._speak([N.say(self.config, "sample")], preview=True)
        elif action == "night_start" and self.phase == "setup":
            self._apply_config(data.get("config"))
            self._start_night()
        elif action == "night_next":
            if self.phase in ("welcome", "lineup", "intro", "interlude"):
                self._advance()
            elif self.phase == "finale":
                self._finish()
        elif action == "night_skip" and self.phase == "playing":
            self._end_inner(skipped=True)
        elif action == "night_end" and self.phase not in ("setup", "finale", "done"):
            if self.phase == "playing":
                self._drop_inner()
            self._enter_finale()

    def _apply_config(self, raw) -> None:
        if raw is None:
            return
        self.config = N.clean_config(raw, self.config)
        self.room.night_config = dict(self.config)

    # ---- the show ----------------------------------------------------------------

    def _start_night(self) -> None:
        games = list(self.config["games"]) or list(N.DEFAULT_GAMES)
        self.playlist = games
        self.index = -1
        self.log = []
        self.skip_notes = []
        self.night_scores = {p.id: 0 for p in self.room.players}
        for p in self.room.players:
            p.score = 0
        self._speak(N.welcome_lines(self.config), phase="welcome")

    def _speak(self, lines: list[str], phase: str | None = None,
               preview: bool = False) -> None:
        """Publish something for the TV to say. A preview leaves the phase
        alone; anything else moves to ``phase`` and arms its timers."""
        self._announce_seq += 1
        self.announce = {
            "id": self._announce_seq,
            "lines": list(lines),
            "voice": N.voice_params(self.config),
            "preview": preview,
        }
        if preview or phase is None:
            return
        now = time.time()
        self.phase = phase
        hold = N.MIN_HOLD.get(phase, 4)
        self.hold_until = now + hold
        self.deadline = now + max(hold, N.speech_seconds(lines))

    def _on_announce_done(self, player_id: str, data: dict) -> None:
        if not self._is_director(player_id):
            return
        if self.phase not in ANNOUNCE_PHASES or self.announce is None:
            return
        if data.get("id") != self.announce["id"]:
            return
        if time.time() >= self.hold_until:
            self._advance()
        else:
            # Spoken faster than anyone could read it: hold the screen.
            self.deadline = self.hold_until

    def tick(self, dt: float) -> None:
        if self._finished:
            return
        if self.phase == "playing" and self.inner is not None:
            try:
                self.inner.tick(dt)
            except Exception:
                logger.exception("hosted tick failed room=%s", self.room.code)
            self._check_inner_over()
            return
        if (self.phase in ANNOUNCE_PHASES and self.deadline
                and time.time() >= self.deadline):
            self._advance()

    def _advance(self) -> None:
        # If everyone's phone dropped at once, wait for them rather than
        # skipping the whole evening.
        if (self.phase in ("lineup", "intro", "interlude")
                and not self.room.connected_players()):
            self.deadline = time.time() + 5
            return
        if self.phase == "welcome":
            self._speak(N.lineup_lines(self.config, self._playlist_entries()),
                        phase="lineup")
        elif self.phase == "lineup":
            self._next_game()
        elif self.phase == "intro":
            self._launch_inner()
        elif self.phase == "interlude":
            self._next_game()
        elif self.phase == "finale":
            self._finish()

    # ---- hosted games ------------------------------------------------------------

    def _entry(self, gid: str) -> dict:
        info = dict(N.CATALOG_BY_ID.get(gid) or {"id": gid, "name": gid, "emoji": "🎮",
                                                 "blurb": ""})
        cls = self._engine_class(gid)
        info["minPlayers"] = cls.min_players
        info["maxPlayers"] = cls.max_players
        return info

    @staticmethod
    def _engine_class(gid: str):
        # Imported here: the registry imports this module while it loads, so a
        # top-level import would be circular.
        from games.native_hub.registry import engine_for
        return engine_for(gid)

    def _playlist_entries(self) -> list[dict]:
        return [self._entry(gid) for gid in self.playlist]

    def _fits(self, gid: str) -> bool:
        cls = self._engine_class(gid)
        count = len(self.room.connected_players())
        return cls.min_players <= count <= cls.max_players

    def _skip(self, gid: str) -> None:
        entry = self._entry(gid)
        self.skip_notes.append(N.say(self.config, "skipped", game=entry["name"]))
        self.log.append({"gameID": gid, "name": entry["name"], "emoji": entry["emoji"],
                         "skipped": True, "winner": None, "results": []})

    def _next_game(self) -> None:
        while True:
            self.index += 1
            if self.index >= len(self.playlist):
                self._enter_finale()
                return
            gid = self.playlist[self.index]
            if self._fits(gid):
                break
            self._skip(gid)
        entry = self._entry(gid)
        notes, self.skip_notes = self.skip_notes, []
        self._speak(N.intro_lines(self.config, entry, first=not self._played_any(),
                                  notes=notes),
                    phase="intro")

    def _played_any(self) -> bool:
        return any(not item.get("skipped") for item in self.log)

    def _launch_inner(self) -> None:
        gid = self.playlist[self.index]
        # Guests may have come or gone during the intro.
        if not self._fits(gid):
            self._skip(gid)
            self._next_game()
            return
        cls = self._engine_class(gid)
        roster = self.room.connected_players()
        for p in self.room.players:
            p.score = 0                 # in-game score; the tally resumes at the interlude
        inner = cls(self.room, self.bc)
        try:
            inner.apply_night_config(self.config)
            inner.start(roster)
        except Exception:
            logger.exception("hosted game failed to start room=%s game=%s",
                             self.room.code, gid)
            self._skip(gid)
            self._next_game()
            return
        self.inner = inner
        self.inner_gid = gid
        self.inner_roster = [p.id for p in roster]
        self.tick_hz = float(inner.tick_hz or 0.0)
        self.heavy_state = bool(inner.heavy_state)
        self.phase = "playing"
        self.deadline = 0.0
        self.announce = None

    def _drop_inner(self) -> None:
        inner = self.inner
        self.inner = None
        self.inner_gid = None
        self.inner_roster = []
        self.tick_hz = 0.0
        self.heavy_state = False
        if inner is not None:
            try:
                inner.stop()
            except Exception:
                logger.exception("hosted stop failed room=%s", self.room.code)

    def _check_inner_over(self) -> None:
        if self.inner is None:
            return
        try:
            over = self.inner.is_over()
        except Exception:
            logger.exception("hosted is_over failed room=%s", self.room.code)
            over = True
        if over:
            self._end_inner()

    def _end_inner(self, skipped: bool = False) -> None:
        inner, gid = self.inner, self.inner_gid
        results: list[dict] = []
        if inner is not None and not skipped:
            try:
                results = inner.results()
            except Exception:
                logger.exception("hosted results failed room=%s", self.room.code)
        self._drop_inner()

        entry = self._entry(gid) if gid else {"id": "", "name": "", "emoji": "", "blurb": ""}
        awarded = {} if skipped else self._award(results)
        winner = None
        if awarded:
            top = max(awarded.values())
            if top > N.PARTICIPATION_POINTS:
                winner = self.player_name(max(awarded, key=awarded.get))

        self.log.append({
            "gameID": gid, "name": entry["name"], "emoji": entry["emoji"],
            "skipped": skipped, "winner": winner,
            "results": [{"name": self.player_name(pid), "points": pts}
                        for pid, pts in sorted(awarded.items(),
                                               key=lambda kv: kv[1], reverse=True)],
        })
        for p in self.room.players:
            p.score = self.night_scores.get(p.id, 0)

        leader, points = self._leader()
        self._speak(N.interlude_lines(self.config, entry, winner, leader, points, skipped),
                    phase="interlude")

    def _award(self, results: list[dict]) -> dict[str, int]:
        """Turn a finished game's ranking into night points."""
        rows = [r for r in results if isinstance(r, dict) and r.get("playerID")]
        if not rows:
            return {}
        # A game nobody scored in (or where everyone tied) has no winner.
        decisive = len({r.get("score") for r in rows}) > 1
        awarded: dict[str, int] = {}
        for position, row in enumerate(rows, start=1):
            rank = row.get("rank") if isinstance(row.get("rank"), int) else position
            pts = N.RANK_POINTS.get(rank, N.PARTICIPATION_POINTS) if decisive \
                else N.PARTICIPATION_POINTS
            pid = row["playerID"]
            awarded[pid] = pts
            self.night_scores[pid] = self.night_scores.get(pid, 0) + pts
        return awarded

    def _leader(self) -> tuple[str | None, int]:
        if not self.night_scores:
            return None, 0
        pid, pts = max(self.night_scores.items(), key=lambda kv: kv[1])
        if pts <= 0:
            return None, 0
        return self.player_name(pid), pts

    def _enter_finale(self) -> None:
        leader, points = self._leader()
        notes, self.skip_notes = self.skip_notes, []
        self._speak(N.finale_lines(self.config, leader, points, notes), phase="finale")

    def _finish(self) -> None:
        for p in self.room.players:
            p.score = self.night_scores.get(p.id, 0)
        self._finished = True
        self.phase = "done"
        self.deadline = 0.0

    # ---- state -------------------------------------------------------------------

    def _standings(self) -> list[dict]:
        rows = [{"id": p.id, "name": p.name, "points": self.night_scores.get(p.id, 0)}
                for p in self.room.players]
        rows.sort(key=lambda r: r["points"], reverse=True)
        return rows

    def _lineup_ids(self) -> list[str]:
        """Before the show starts, preview the configured lineup."""
        return self.playlist if self.playlist else list(self.config["games"])

    def _lineup_view(self) -> list[dict]:
        view = []
        for i, gid in enumerate(self._lineup_ids()):
            entry = N.CATALOG_BY_ID.get(gid, {"name": gid, "emoji": "🎮"})
            if self.playlist and i < self.index:
                state = "done"
            elif self.playlist and i == self.index:
                state = "current"
            else:
                state = "next"
            view.append({"id": gid, "name": entry["name"], "emoji": entry["emoji"],
                         "state": state})
        return view

    def _current_game(self) -> dict | None:
        if not self.playlist or not (0 <= self.index < len(self.playlist)):
            return None
        if self.phase not in ("intro", "playing"):
            return None
        entry = self._entry(self.playlist[self.index])
        return {"id": entry["id"], "name": entry["name"], "emoji": entry["emoji"],
                "blurb": entry["blurb"]}

    def _common(self) -> dict:
        occasion = N.occasion_for(self.config)
        return {
            "phase": self.phase,
            "title": N.title_for(self.config),
            "cheer": N.cheer_for(self.config),
            "occasion": occasion["id"],
            "occasionLabel": occasion["label"],
            "emoji": occasion["emoji"],
            "honoree": self.config["honoree"],
            "voicePack": {"id": self.config["voicePack"],
                          "name": N.pack_for(self.config)["name"],
                          "emoji": N.pack_for(self.config)["emoji"]},
            "gameIndex": self.index + 1 if self.index >= 0 else 0,
            "gameCount": len(self._lineup_ids()),
            "currentGame": self._current_game(),
            "lineup": self._lineup_view(),
            "standings": self._standings(),
            "lastGame": self.log[-1] if self.log and self.phase in ("interlude", "finale")
                        else None,
        }

    def night_state(self) -> dict:
        """The TV's channel."""
        state = self._common()
        host = next((p for p in self.room.players if p.is_host), None)
        state.update({
            "roomCode": self.room.code,
            "announce": self.announce,
            "hostName": host.name if host else None,
            "guests": [{"id": p.id, "name": p.name, "isHost": p.is_host}
                       for p in self.room.connected_players()],
        })
        return state

    def public_state(self) -> dict:
        if self.phase == "playing" and self.inner is not None:
            try:
                return self.inner.public_state()
            except Exception:
                logger.exception("hosted public_state failed room=%s", self.room.code)
        return {"night": True, "phase": self.phase}

    def private_state(self, player_id: str) -> dict:
        player = self.room.player(player_id)
        is_host = bool(player and player.is_host)
        night = self._common()
        night["isHost"] = is_host
        night["roomCode"] = self.room.code
        night["playing"] = self.phase == "playing" and self.inner is not None
        night["spectating"] = night["playing"] and player_id not in self.inner_roster

        if self.phase == "setup" and is_host:
            night["config"] = dict(self.config)
            night["catalog"] = self._catalog_view()
            night["occasions"] = N.occasion_options()
            night["voicePacks"] = N.voice_pack_options()
            night["nhiePacks"] = P.pack_options()
            night["nhieRoundChoices"] = list(N.NHIE_ROUND_CHOICES)
            night["humorPacks"] = H.pack_options()
            night["guestCount"] = len(self.room.connected_players())

        if night["playing"] and player_id in self.inner_roster:
            try:
                state = dict(self.inner.private_state(player_id))
            except Exception:
                logger.exception("hosted private_state failed room=%s", self.room.code)
                state = {}
            state["night"] = night
            return state
        return {"night": night}

    def _catalog_view(self) -> list[dict]:
        view = []
        for game in N.CATALOG:
            entry = self._entry(game["id"])
            view.append({"id": entry["id"], "name": entry["name"],
                         "emoji": entry["emoji"], "blurb": entry["blurb"],
                         "minPlayers": entry["minPlayers"],
                         "maxPlayers": entry["maxPlayers"]})
        return view


ENGINES = {"game_night": GameNightEngine}
