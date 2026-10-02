"""Social-deduction and trivia engines ported from the browser catalog.

Mafia ports role assignment and win-condition checking from
games/mafia/game_logic.py:MafiaGame, collapsed from its five phases
(lobby/night/day/voting/finished) to the two phases MafiaBoardState/
MafiaControllerView actually know about (day/night) -- discussion and
voting both happen inside the "day" phase on the TV, so there's no
separate voting phase to preserve in the native contract. Raja Mantri
ports role assignment and scoring straight from
games/raja_mantri/socket_events.py. Trivia has no reusable browser logic
(the browser game calls out to a Gemini API for questions), so its
question bank and round loop are original, built to
TVTriviaBoardView/TriviaControllerView's contract.
"""

import random
import time

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines.content_packs import (
    fresh_questions,
    record_questions,
)

# ---------------------------------------------------------------------------
# Mafia -- verified against MafiaBoardState/MafiaControllerView. Role names
# follow the Swift side (`"mafia"`, `"sheriff"`, `"doctor"`, default/"town"),
# not the browser's Role enum (which used "detective").
# ---------------------------------------------------------------------------


class MafiaEngine(NativeGameEngine):
    game_id = "mafia"
    min_players = 5
    max_players = 15

    DAY_SECONDS = 60
    NIGHT_SECONDS = 30

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.roles: dict[str, str] = {}
        self.alive: dict[str, bool] = {}
        self.phase = "night"
        self.round = 1
        self.deadline = 0.0
        self.night_actions: dict[str, dict] = {}
        self.day_votes: dict[str, str] = {}
        self.investigate_results: dict[str, str] = {}
        self.investigate_is_mafia: dict[str, bool] = {}
        self.last_eliminated: str | None = None
        self.last_day_tie = False
        self.winner: str | None = None
        self._finished = False

    def start(self, players):
        ids = [p.id for p in players]
        random.shuffle(ids)
        n = len(ids)
        num_mafia = max(1, n // 4)
        roles = ["mafia"] * num_mafia + ["doctor", "sheriff"] + ["villager"] * (n - num_mafia - 2)
        roles = roles[:n]
        while len(roles) < n:
            roles.append("villager")
        for pid, role in zip(ids, roles):
            self.roles[pid] = role
            self.alive[pid] = True
        self.deadline = time.time() + self.NIGHT_SECONDS

    def seconds_left(self):
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def _alive_ids(self):
        return [pid for pid, ok in self.alive.items() if ok]

    def handle_action(self, player_id, action, data):
        if self._finished or not self.alive.get(player_id):
            return
        role = self.roles.get(player_id)
        target = data.get("targetID")

        if self.phase == "night":
            if action == "eliminate" and role == "mafia" and target in self.alive and self.alive[target]:
                self.night_actions[player_id] = {"action": "eliminate", "target": target}
            elif action == "save" and role == "doctor" and target in self.alive and self.alive[target]:
                self.night_actions[player_id] = {"action": "save", "target": target}
            elif action == "investigate" and role == "sheriff" and target in self.alive and self.alive[target]:
                if player_id in self.night_actions:
                    return                      # one investigation per night
                self.night_actions[player_id] = {"action": "investigate", "target": target}
                is_mafia = self.roles.get(target) == "mafia"
                name = self.player_name(target)
                self.investigate_results[player_id] = (
                    f"{name} is Mafia!" if is_mafia else f"{name} is not Mafia.")
                self.investigate_is_mafia[player_id] = is_mafia
            if self._night_done():
                self._resolve_phase()
        elif self.phase == "day":
            if action == "vote" and target in self.alive and self.alive[target]:
                self.day_votes[player_id] = target
                if all(pid in self.day_votes for pid in self._alive_ids()):
                    self._resolve_phase()       # everyone has voted

    def _night_done(self):
        """Every living special role has acted -- no need to wait the clock out."""
        for pid in self._alive_ids():
            if self.roles[pid] in ("mafia", "doctor", "sheriff") and pid not in self.night_actions:
                player = self.room.player(pid)
                if player is not None and player.connected and not player.is_bot:
                    return False
        return True

    def tick(self, dt):
        if self._finished:
            return
        if self.deadline and time.time() >= self.deadline:
            self._resolve_phase()

    def _resolve_phase(self):
        if self.phase == "night":
            self._resolve_night()
            if self._check_winner():
                return
            self.phase = "day"
            self.day_votes = {}
            self.deadline = time.time() + self.DAY_SECONDS
        else:
            self._resolve_day()
            if self._check_winner():
                return
            self.phase = "night"
            self.round += 1
            self.night_actions = {}
            self.deadline = time.time() + self.NIGHT_SECONDS

    def _resolve_night(self):
        kills: dict[str, int] = {}
        saved = None
        for pid, act in self.night_actions.items():
            if act["action"] == "eliminate":
                kills[act["target"]] = kills.get(act["target"], 0) + 1
            elif act["action"] == "save":
                saved = act["target"]
        self.last_eliminated = None
        if kills:
            victim = max(kills, key=kills.get)
            if victim != saved:
                self.alive[victim] = False
                self.last_eliminated = self.player_name(victim)

    def _resolve_day(self):
        self.last_eliminated = None
        self.last_day_tie = False
        if self.day_votes:
            counts: dict[str, int] = {}
            for target in self.day_votes.values():
                counts[target] = counts.get(target, 0) + 1
            top = max(counts.values())
            leaders = [t for t, c in counts.items() if c == top]
            if len(leaders) > 1:
                self.last_day_tie = True        # a tied vote spares everyone
                return
            eliminated = leaders[0]
            self.alive[eliminated] = False
            self.last_eliminated = self.player_name(eliminated)

    def _check_winner(self):
        alive_mafia = [pid for pid in self._alive_ids() if self.roles[pid] == "mafia"]
        alive_others = [pid for pid in self._alive_ids() if self.roles[pid] != "mafia"]
        if not alive_mafia:
            self.winner = "villagers"
        elif len(alive_mafia) >= len(alive_others):
            self.winner = "mafia"
        else:
            return False
        self._finished = True
        for pid in self.roles:
            on_winning_team = (self.roles[pid] == "mafia") == (self.winner == "mafia")
            player = self.room.player(pid)
            if player is not None:
                player.score = 1000 if on_winning_team else 0
        return True

    def _vote_tally_by_name(self):
        counts: dict[str, int] = {}
        for target in self.day_votes.values():
            name = self.player_name(target)
            counts[name] = counts.get(name, 0) + 1
        return counts

    def public_state(self):
        return {
            "phase": self.phase,
            "round": self.round,
            "secondsLeft": self.seconds_left(),
            "lastEliminated": self.last_eliminated,
            "lastDayTie": self.last_day_tie,
            "votes": self._vote_tally_by_name(),
            "players": [
                {"id": p.id, "name": p.name, "isAlive": self.alive.get(p.id, True),
                 "revealedRole": self.roles.get(p.id) if not self.alive.get(p.id, True) else None}
                for p in self.room.players
            ],
            "winner": self.winner,
        }

    def private_state(self, player_id):
        return {
            "myID": player_id,
            "role": self.roles.get(player_id, "villager"),
            "phase": self.phase,
            "isAlive": self.alive.get(player_id, True),
            "secondsLeft": self.seconds_left(),
            "players": [
                {"id": p.id, "name": p.name, "isAlive": self.alive.get(p.id, True)}
                for p in self.room.players
            ],
            "myVote": self.day_votes.get(player_id),
            "myNightTarget": (self.night_actions.get(player_id) or {}).get("target"),
            "investigateResult": self.investigate_results.get(player_id),
            "investigateIsMafia": self.investigate_is_mafia.get(player_id),
            # Mafia members know each other; nobody else sees this.
            "mafiaTeam": ([self.player_name(pid) for pid, r in self.roles.items()
                           if r == "mafia" and pid != player_id]
                          if self.roles.get(player_id) == "mafia" else []),
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})


# ---------------------------------------------------------------------------
# Raja Mantri -- verified against RajaMantriState/RajaMantriControllerView.
# Scoring ported from games/raja_mantri/socket_events.py:handle_guess.
# ---------------------------------------------------------------------------


class RajaMantriEngine(NativeGameEngine):
    game_id = "raja_mantri"
    min_players = 4
    max_players = 4

    TOTAL_ROUNDS = 4
    REVEAL_SECONDS = 6
    GUESS_SECONDS = 45          # an idle Sipahi lets the Chor escape

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.order: list[str] = []
        self.round = 0
        self.phase = "guess"
        self.roles: dict[str, str] = {}
        self.chor_id: str | None = None
        self.sipahi_id: str | None = None
        self.accused_id: str | None = None
        self.round_result: str | None = None
        self.reveal_until = 0.0
        self._finished = False

    def start(self, players):
        self.order = [p.id for p in players]
        self.round = 0
        self._deal_round()

    def _deal_round(self):
        self.round += 1
        roles = ["Raja", "Mantri", "Chor", "Sipahi"]
        random.shuffle(roles)
        self.roles = {pid: roles[i] for i, pid in enumerate(self.order)}
        self.chor_id = next(pid for pid, r in self.roles.items() if r == "Chor")
        self.sipahi_id = next(pid for pid, r in self.roles.items() if r == "Sipahi")
        self.accused_id = None
        self.round_result = None
        self.phase = "guess"
        self.guess_deadline = time.time() + self.GUESS_SECONDS

    def handle_action(self, player_id, action, data):
        if self._finished or action != "accuse" or self.phase != "guess":
            return
        if player_id != self.sipahi_id:
            return
        target = data.get("targetID")
        if target not in self.roles or target == player_id:
            return
        self._resolve_accusation(target)

    def _resolve_accusation(self, target):
        self.accused_id = target
        is_correct = target == self.chor_id
        awards = {
            self.sipahi_id: 500 if is_correct else 0,
            self.chor_id: 0 if is_correct else 500,
        }
        for pid, role in self.roles.items():
            if role == "Raja":
                awards[pid] = 1000
            elif role == "Mantri":
                awards[pid] = 800
        for pid, amount in awards.items():
            player = self.room.player(pid)
            if player is not None:
                player.score += amount

        chor_name = self.player_name(self.chor_id)
        sipahi_name = self.player_name(self.sipahi_id)
        if target is None:
            self.round_result = f"{sipahi_name} ran out of time! {chor_name} got away!"
        else:
            self.round_result = (
                f"{sipahi_name} correctly caught {chor_name}!" if is_correct
                else f"{sipahi_name} guessed wrong! {chor_name} got away!")
        self.phase = "reveal"
        self.reveal_until = time.time() + self.REVEAL_SECONDS

    def tick(self, dt):
        if self._finished:
            return
        if self.phase == "guess":
            if time.time() >= getattr(self, "guess_deadline", float("inf")):
                self._resolve_accusation(None)      # time up: nobody caught
            return
        if self.phase != "reveal" or time.time() < self.reveal_until:
            return
        if self.round >= self.TOTAL_ROUNDS:
            self._finished = True
        else:
            self._deal_round()

    def public_state(self):
        revealed = self.phase == "reveal"
        return {
            "round": self.round,
            "phase": self.phase,
            "roundResult": self.round_result,
            "players": [
                {"id": pid, "name": self.player_name(pid),
                 "role": self.roles.get(pid) if revealed else None,
                 "isAccused": pid == self.accused_id}
                for pid in self.order
            ],
        }

    def private_state(self, player_id):
        player = self.room.player(player_id)
        return {
            "role": self.roles.get(player_id, ""),
            "phase": self.phase,
            "players": [{"id": pid, "name": self.player_name(pid)} for pid in self.order],
            "score": player.score if player else 0,
            "hasGuessed": self.accused_id is not None,
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})


# ---------------------------------------------------------------------------
# Trivia -- no reusable server logic in games/trivia (it calls a Gemini API
# for questions); question bank and round loop are original, built to
# TVTriviaBoardView/TriviaControllerView's contract.
# ---------------------------------------------------------------------------

TRIVIA_QUESTIONS = [
    ("Science", "What planet is known as the Red Planet?",
     ["Mars", "Venus", "Jupiter", "Saturn"], 0),
    ("Science", "What gas do plants absorb from the atmosphere?",
     ["Oxygen", "Carbon Dioxide", "Nitrogen", "Hydrogen"], 1),
    ("Geography", "What is the longest river in the world?",
     ["Amazon", "Nile", "Yangtze", "Mississippi"], 1),
    ("Geography", "Which country has the most population?",
     ["USA", "Indonesia", "India", "Brazil"], 2),
    ("History", "In what year did World War II end?",
     ["1943", "1945", "1947", "1950"], 1),
    ("History", "Who was the first President of the United States?",
     ["Lincoln", "Jefferson", "Washington", "Adams"], 2),
    ("Sports", "How many players are on a football (soccer) team on the field?",
     ["9", "10", "11", "12"], 2),
    ("Sports", "In which sport would you perform a slam dunk?",
     ["Tennis", "Basketball", "Golf", "Cricket"], 1),
    ("Movies", "Which movie features a character named Jack Dawson?",
     ["Titanic", "Avatar", "Inception", "Gladiator"], 0),
    ("Music", "How many strings does a standard guitar have?",
     ["4", "5", "6", "7"], 2),
    ("General", "What is the capital of Japan?",
     ["Seoul", "Beijing", "Tokyo", "Bangkok"], 2),
    ("General", "How many continents are there on Earth?",
     ["5", "6", "7", "8"], 2),
    ("Science", "What is the chemical symbol for gold?",
     ["Au", "Ag", "Gd", "Go"], 0),
    ("Science", "What force pulls objects toward the Earth?",
     ["Magnetism", "Gravity", "Friction", "Tension"], 1),
    ("Geography", "Mount Everest is located in which mountain range?",
     ["Andes", "Alps", "Himalayas", "Rockies"], 2),
    # --- Science -----------------------------------------------------------
    ("Science", "What is the chemical symbol for silver?",
     ["Au", "Ag", "Si", "Pt"], 1),
    ("Science", "What is H2O commonly known as?",
     ["Hydrogen", "Water", "Salt", "Oxygen"], 1),
    ("Science", "Which organelle is known as the powerhouse of the cell?",
     ["Nucleus", "Ribosome", "Mitochondria", "Chloroplast"], 2),
    ("Science", "What is the boiling point of water at sea level?",
     ["90C", "100C", "110C", "120C"], 1),
    ("Science", "Which planet is the largest in our solar system?",
     ["Earth", "Saturn", "Jupiter", "Neptune"], 2),
    ("Science", "Which blood cells carry oxygen around the body?",
     ["White blood cells", "Red blood cells", "Platelets", "Plasma cells"], 1),
    ("Science", "What is the hardest natural substance on Earth?",
     ["Quartz", "Diamond", "Titanium", "Obsidian"], 1),
    ("Science", "Photosynthesis happens in which part of a plant cell?",
     ["Nucleus", "Chloroplast", "Cell wall", "Vacuole"], 1),
    ("Science", "How many bones are in the adult human body?",
     ["186", "206", "226", "256"], 1),
    ("Science", "What gas makes up most of the Earth's atmosphere?",
     ["Oxygen", "Carbon dioxide", "Nitrogen", "Helium"], 2),
    ("Science", "Which vitamin is produced when skin is exposed to sunlight?",
     ["Vitamin A", "Vitamin C", "Vitamin D", "Vitamin K"], 2),
    ("Science", "What is the center of an atom called?",
     ["Electron", "Nucleus", "Proton shell", "Neutron cloud"], 1),
    ("Science", "Which metal is liquid at room temperature?",
     ["Iron", "Mercury", "Lead", "Aluminium"], 1),
    ("Science", "About how long does light take to travel from the Sun to the Earth?",
     ["8 seconds", "8 minutes", "8 hours", "8 days"], 1),
    ("Science", "Which scientist developed the theory of relativity?",
     ["Isaac Newton", "Galileo Galilei", "Albert Einstein", "Charles Darwin"], 2),
    ("Science", "What is the pH of pure water?",
     ["0", "7", "14", "5"], 1),
    ("Science", "Which part of the human brain is mainly responsible for balance?",
     ["Cerebrum", "Cerebellum", "Brain stem", "Hippocampus"], 1),
    ("Science", "What type of energy is stored in a battery?",
     ["Kinetic", "Thermal", "Chemical", "Nuclear"], 2),
    ("Science", "Which element has the chemical symbol 'O'?",
     ["Gold", "Oxygen", "Osmium", "Silver"], 1),
    ("Science", "How many legs does a spider have?",
     ["6", "8", "10", "12"], 1),
    ("Science", "What is the study of earthquakes called?",
     ["Geology", "Seismology", "Meteorology", "Volcanology"], 1),
    ("Science", "Which planet has the most confirmed moons?",
     ["Jupiter", "Saturn", "Uranus", "Neptune"], 1),
    ("Science", "What is the approximate speed of sound in air?",
     ["123 km/h", "343 m/s", "1500 m/s", "300,000 km/s"], 1),
    ("Science", "Which subatomic particle has a negative charge?",
     ["Proton", "Neutron", "Electron", "Photon"], 2),
    ("Science", "What mainly causes ocean tides on Earth?",
     ["Wind", "The Moon's gravity", "The Sun's heat", "Earthquakes"], 1),
    ("Science", "Which instrument measures atmospheric pressure?",
     ["Thermometer", "Barometer", "Hygrometer", "Anemometer"], 1),
    ("Science", "How many chromosomes do humans normally have in each cell?",
     ["23", "44", "46", "48"], 2),
    ("Science", "What is the freezing point of water in Fahrenheit?",
     ["0F", "28F", "32F", "212F"], 2),
    ("Science", "DNA carries which kind of information in living things?",
     ["Genetic", "Dietary", "Weather", "Electrical"], 0),
    ("Science", "Which force keeps the Moon orbiting the Earth?",
     ["Magnetism", "Gravity", "Friction", "Inertia"], 1),
    # --- Geography ---------------------------------------------------------
    ("Geography", "Which is the largest desert in the world?",
     ["Sahara", "Gobi", "Antarctic", "Kalahari"], 2),
    ("Geography", "Which country is both a continent and a country?",
     ["Australia", "Greenland", "Madagascar", "Iceland"], 0),
    ("Geography", "The Great Barrier Reef lies off the coast of which country?",
     ["Brazil", "Australia", "Mexico", "Thailand"], 1),
    ("Geography", "What is the capital of Canada?",
     ["Toronto", "Vancouver", "Ottawa", "Montreal"], 2),
    ("Geography", "The Amazon rainforest is mostly located in which country?",
     ["Peru", "Colombia", "Brazil", "Venezuela"], 2),
    ("Geography", "Which river flows through Egypt?",
     ["Tigris", "Nile", "Euphrates", "Jordan"], 1),
    ("Geography", "Which European country has the largest population?",
     ["Germany", "France", "Spain", "Italy"], 0),
    ("Geography", "Mount Fuji is in which country?",
     ["China", "South Korea", "Japan", "Taiwan"], 2),
    ("Geography", "The Grand Canyon is in which US state?",
     ["Nevada", "Utah", "Arizona", "Colorado"], 2),
    ("Geography", "What is the smallest country in the world?",
     ["Monaco", "Vatican City", "San Marino", "Liechtenstein"], 1),
    ("Geography", "Which strait separates Spain and Morocco?",
     ["Bosporus", "Gibraltar", "Malacca", "Bering"], 1),
    ("Geography", "The Sahara Desert is primarily on which continent?",
     ["Asia", "Africa", "Australia", "South America"], 1),
    ("Geography", "Which country is known as the Land of the Rising Sun?",
     ["China", "Japan", "Thailand", "South Korea"], 1),
    ("Geography", "What is the capital of Brazil?",
     ["Rio de Janeiro", "Sao Paulo", "Brasilia", "Salvador"], 2),
    ("Geography", "Which ocean lies between Africa and Australia?",
     ["Pacific", "Atlantic", "Indian", "Arctic"], 2),
    ("Geography", "The Eiffel Tower is in which city?",
     ["London", "Paris", "Rome", "Berlin"], 1),
    ("Geography", "Which is the deepest ocean trench on Earth?",
     ["Puerto Rico Trench", "Mariana Trench", "Tonga Trench", "Java Trench"], 1),
    ("Geography", "Which country has the most islands?",
     ["Indonesia", "Philippines", "Sweden", "Canada"], 2),
    ("Geography", "What is the capital of Egypt?",
     ["Cairo", "Alexandria", "Giza", "Luxor"], 0),
    ("Geography", "Which two countries share the longest international border?",
     ["USA and Canada", "Russia and China", "India and China", "Argentina and Chile"], 0),
    ("Geography", "Lake Baikal, the world's deepest lake, is in which country?",
     ["Canada", "Russia", "Finland", "Mongolia"], 1),
    ("Geography", "Which African country was formerly known as Abyssinia?",
     ["Somalia", "Ethiopia", "Sudan", "Kenya"], 1),
    ("Geography", "The Great Wall is in which country?",
     ["India", "China", "Mongolia", "Japan"], 1),
    ("Geography", "Which city is known as the Big Apple?",
     ["Los Angeles", "Chicago", "New York", "Boston"], 2),
    ("Geography", "What is the capital of New Zealand?",
     ["Auckland", "Wellington", "Christchurch", "Queenstown"], 1),
    ("Geography", "Which continent is the least populated?",
     ["Oceania", "Africa", "Antarctica", "South America"], 2),
    ("Geography", "The Danube River flows into which sea?",
     ["Mediterranean Sea", "Black Sea", "Baltic Sea", "Red Sea"], 1),
    ("Geography", "Which country invented paper?",
     ["Egypt", "Greece", "China", "India"], 2),
    ("Geography", "What is the currency of Japan?",
     ["Won", "Yuan", "Yen", "Ringgit"], 2),
    ("Geography", "Which US state has the most active volcanoes?",
     ["California", "Hawaii", "Alaska", "Washington"], 2),
    # --- History -----------------------------------------------------------
    ("History", "Who was the first person to walk on the Moon?",
     ["Buzz Aldrin", "Neil Armstrong", "Michael Collins", "Yuri Gagarin"], 1),
    ("History", "The Titanic sank in which year?",
     ["1905", "1912", "1918", "1923"], 1),
    ("History", "Who was the first woman to win a Nobel Prize?",
     ["Marie Curie", "Rosalind Franklin", "Florence Nightingale", "Ada Lovelace"], 0),
    ("History", "The Berlin Wall fell in which year?",
     ["1979", "1985", "1989", "1991"], 2),
    ("History", "Which ancient civilization built the pyramids of Giza?",
     ["Romans", "Greeks", "Egyptians", "Mayans"], 2),
    ("History", "Who was the British Prime Minister for most of World War II?",
     ["Neville Chamberlain", "Winston Churchill", "Clement Attlee", "Anthony Eden"], 1),
    ("History", "In which year did India gain independence?",
     ["1945", "1947", "1950", "1952"], 1),
    ("History", "Who was the first emperor to unify China?",
     ["Kublai Khan", "Qin Shi Huang", "Han Wudi", "Sun Tzu"], 1),
    ("History", "The Renaissance began in which country?",
     ["France", "Italy", "England", "Spain"], 1),
    ("History", "Who reached the Americas in 1492?",
     ["Vasco da Gama", "Christopher Columbus", "Ferdinand Magellan", "John Cabot"], 1),
    ("History", "Which empire built the Colosseum?",
     ["Greek", "Roman", "Ottoman", "Persian"], 1),
    ("History", "Who was assassinated on 15 March 44 BC?",
     ["Augustus", "Julius Caesar", "Nero", "Caligula"], 1),
    ("History", "Who invented the movable-type printing press?",
     ["Leonardo da Vinci", "Johannes Gutenberg", "Isaac Newton", "Galileo Galilei"], 1),
    ("History", "Which country was the first to grant women the right to vote?",
     ["USA", "UK", "New Zealand", "France"], 2),
    ("History", "World War I began in which year?",
     ["1912", "1914", "1916", "1918"], 1),
    ("History", "Who was the first President of India?",
     ["Jawaharlal Nehru", "Dr. Rajendra Prasad", "Sardar Patel", "Dr. Radhakrishnan"], 1),
    ("History", "The Great Fire of London happened in which year?",
     ["1566", "1666", "1766", "1866"], 1),
    ("History", "Whose nearly intact tomb was discovered in 1922?",
     ["Ramses II", "Tutankhamun", "Cleopatra", "Akhenaten"], 1),
    ("History", "Who led the Salt March in India in 1930?",
     ["Jawaharlal Nehru", "Subhas Chandra Bose", "Mahatma Gandhi", "Bhagat Singh"], 2),
    ("History", "The ancient Olympic Games were held in which country?",
     ["Italy", "Greece", "Egypt", "Turkey"], 1),
    # --- Sports ------------------------------------------------------------
    ("Sports", "How often are the Summer Olympic Games held?",
     ["Every 2 years", "Every 3 years", "Every 4 years", "Every 5 years"], 2),
    ("Sports", "In tennis, what is a score of zero called?",
     ["Nil", "Love", "Duck", "Blank"], 1),
    ("Sports", "Which country won the first FIFA World Cup in 1930?",
     ["Brazil", "Italy", "Uruguay", "Argentina"], 2),
    ("Sports", "How many holes are played in a standard round of golf?",
     ["9", "12", "18", "24"], 2),
    ("Sports", "In cricket, how many legal balls are in one over?",
     ["5", "6", "8", "10"], 1),
    ("Sports", "Which sport uses a puck?",
     ["Field hockey", "Ice hockey", "Lacrosse", "Polo"], 1),
    ("Sports", "Usain Bolt is famous for which sport?",
     ["Swimming", "Boxing", "Athletics", "Cycling"], 2),
    ("Sports", "How many rings are on the Olympic flag?",
     ["4", "5", "6", "7"], 1),
    ("Sports", "In which sport would you hit a shuttlecock?",
     ["Tennis", "Squash", "Badminton", "Table tennis"], 2),
    ("Sports", "Which chess piece moves in an L-shape?",
     ["Bishop", "Rook", "Knight", "Queen"], 2),
    ("Sports", "A marathon is approximately how long?",
     ["26 miles", "13 miles", "10 km", "50 km"], 0),
    ("Sports", "Table tennis originated in which country?",
     ["China", "Japan", "England", "Germany"], 2),
    ("Sports", "In baseball, how many strikes make an out?",
     ["2", "3", "4", "5"], 1),
    ("Sports", "Which Indian cricketer is known as the 'God of Cricket'?",
     ["Virat Kohli", "Sachin Tendulkar", "MS Dhoni", "Rahul Dravid"], 1),
    ("Sports", "How many players from one basketball team are on the court?",
     ["4", "5", "6", "7"], 1),
    ("Sports", "Which Grand Slam tennis tournament is played on clay?",
     ["Wimbledon", "US Open", "French Open", "Australian Open"], 2),
    ("Sports", "In which sport is the term 'home run' used?",
     ["Cricket", "Baseball", "Rugby", "Golf"], 1),
    ("Sports", "What is the maximum possible break in snooker?",
     ["135", "147", "155", "180"], 1),
    ("Sports", "Which country hosts the Tour de France?",
     ["Italy", "Spain", "France", "Belgium"], 2),
    ("Sports", "How many minutes are in a standard football (soccer) match?",
     ["80", "90", "100", "120"], 1),
    # --- Movies ------------------------------------------------------------
    ("Movies", "Who directed the movie 'Inception'?",
     ["Steven Spielberg", "Christopher Nolan", "James Cameron", "Quentin Tarantino"], 1),
    ("Movies", "Which 1997 film won 11 Academy Awards including Best Picture?",
     ["Avatar", "Titanic", "The English Patient", "Braveheart"], 1),
    ("Movies", "Who played the Joker in 'The Dark Knight'?",
     ["Jared Leto", "Joaquin Phoenix", "Heath Ledger", "Jack Nicholson"], 2),
    ("Movies", "Which animated film features a snowman named Olaf?",
     ["Moana", "Frozen", "Tangled", "Brave"], 1),
    ("Movies", "Who directed 'Jurassic Park'?",
     ["George Lucas", "Steven Spielberg", "Ridley Scott", "Peter Jackson"], 1),
    ("Movies", "In 'The Lion King', what kind of animal is Timon?",
     ["Warthog", "Meerkat", "Mandrill", "Hyena"], 1),
    ("Movies", "Who played Iron Man in the Marvel films?",
     ["Chris Evans", "Robert Downey Jr.", "Chris Hemsworth", "Mark Ruffalo"], 1),
    ("Movies", "Which film series features the quote 'May the Force be with you'?",
     ["Star Trek", "Star Wars", "Avatar", "Dune"], 1),
    ("Movies", "Who directed 'Pulp Fiction'?",
     ["Martin Scorsese", "Quentin Tarantino", "David Fincher", "Coen Brothers"], 1),
    ("Movies", "Which film won Best Picture at the 2020 Oscars?",
     ["1917", "Joker", "Parasite", "Once Upon a Time in Hollywood"], 2),
    ("Movies", "In 'Toy Story', what is the cowboy doll's name?",
     ["Buzz", "Woody", "Rex", "Hamm"], 1),
    ("Movies", "Which actress played Hermione Granger?",
     ["Emma Watson", "Emma Stone", "Natalie Portman", "Keira Knightley"], 0),
    ("Movies", "What is the highest-grossing film of all time?",
     ["Avengers: Endgame", "Avatar", "Titanic", "Jurassic World"], 1),
    ("Movies", "Who voiced Darth Vader in the original Star Wars trilogy?",
     ["James Earl Jones", "Harrison Ford", "Mark Hamill", "Alec Guinness"], 0),
    ("Movies", "Which film is set in the fictional country of Wakanda?",
     ["Black Panther", "Thor", "Aquaman", "Wonder Woman"], 0),
    ("Movies", "Who directed 'The Godfather'?",
     ["Francis Ford Coppola", "Martin Scorsese", "Stanley Kubrick", "Brian De Palma"], 0),
    ("Movies", "In 'Finding Nemo', what kind of fish is Nemo?",
     ["Blue tang", "Clownfish", "Angelfish", "Pufferfish"], 1),
    ("Movies", "Which film features a DeLorean time machine?",
     ["Back to the Future", "Ghostbusters", "Terminator", "Men in Black"], 0),
    ("Movies", "Who played the lead role in 'Forrest Gump'?",
     ["Tom Cruise", "Tom Hanks", "Brad Pitt", "Leonardo DiCaprio"], 1),
    ("Movies", "Which film won the first Academy Award for Best Picture?",
     ["Wings", "Sunrise", "The Jazz Singer", "Metropolis"], 0),
    # --- Music -------------------------------------------------------------
    ("Music", "Which band released the album 'Abbey Road'?",
     ["The Rolling Stones", "The Beatles", "Pink Floyd", "Led Zeppelin"], 1),
    ("Music", "Who is known as the 'King of Pop'?",
     ["Elvis Presley", "Michael Jackson", "Prince", "Freddie Mercury"], 1),
    ("Music", "Which instrument has 88 keys?",
     ["Guitar", "Violin", "Piano", "Harp"], 2),
    ("Music", "Who composed the 'Moonlight Sonata'?",
     ["Mozart", "Bach", "Beethoven", "Chopin"], 2),
    ("Music", "Which singer is famous for the song 'Shape of You'?",
     ["Ed Sheeran", "Justin Bieber", "Shawn Mendes", "Bruno Mars"], 0),
    ("Music", "How many musicians play in a string quartet?",
     ["3", "4", "5", "6"], 1),
    ("Music", "Freddie Mercury was the lead singer of which band?",
     ["Queen", "ABBA", "The Who", "Genesis"], 0),
    ("Music", "What does singing 'a cappella' mean?",
     ["With piano", "Without instruments", "Very fast", "Very loud"], 1),
    ("Music", "Which artist released 'Thriller', the best-selling album ever?",
     ["Prince", "Michael Jackson", "Madonna", "Whitney Houston"], 1),
    ("Music", "The sitar is a traditional instrument of which country?",
     ["China", "India", "Japan", "Egypt"], 1),
    # --- Technology --------------------------------------------------------
    ("Technology", "Who co-founded Apple with Steve Jobs?",
     ["Bill Gates", "Steve Wozniak", "Larry Page", "Jeff Bezos"], 1),
    ("Technology", "What does 'WWW' stand for?",
     ["World Wide Web", "World Web Window", "Wide World Web", "Web World Wide"], 0),
    ("Technology", "Which company created the PlayStation?",
     ["Nintendo", "Microsoft", "Sony", "Sega"], 2),
    ("Technology", "In which year was the first iPhone released?",
     ["2005", "2007", "2009", "2010"], 1),
    ("Technology", "The Python language is named after which comedy group?",
     ["Monty Python", "The Pythons band", "Python Films", "A pet snake"], 0),
    ("Technology", "What does 'CPU' stand for?",
     ["Central Processing Unit", "Computer Personal Unit", "Central Program Utility", "Core Processing Unit"], 0),
    ("Technology", "Who founded Microsoft?",
     ["Steve Jobs", "Bill Gates", "Larry Ellison", "Michael Dell"], 1),
    ("Technology", "Which social media platform was founded by Mark Zuckerberg?",
     ["Twitter", "Instagram", "Facebook", "LinkedIn"], 2),
    ("Technology", "What does 'AI' stand for in computing?",
     ["Automated Input", "Artificial Intelligence", "Advanced Interface", "Analog Integration"], 1),
    ("Technology", "Which company makes the Galaxy series of phones?",
     ["Apple", "Samsung", "Huawei", "Xiaomi"], 1),
    ("Technology", "The first fully programmable computer was built in which decade?",
     ["1920s", "1930s", "1940s", "1950s"], 2),
    ("Technology", "What is the name of the virtual assistant on iPhones?",
     ["Alexa", "Siri", "Cortana", "Bixby"], 1),
    # --- Nature ------------------------------------------------------------
    ("Nature", "What is the largest mammal on Earth?",
     ["African elephant", "Blue whale", "Giraffe", "Hippopotamus"], 1),
    ("Nature", "Which bird cannot fly but is an excellent swimmer?",
     ["Ostrich", "Penguin", "Emu", "Kiwi"], 1),
    ("Nature", "How many legs does a lobster have, counting its claws?",
     ["6", "8", "10", "12"], 2),
    ("Nature", "Which animal is known as the 'ship of the desert'?",
     ["Horse", "Camel", "Donkey", "Elephant"], 1),
    ("Nature", "What is a baby frog called after hatching?",
     ["Tadpole", "Newt", "Toadlet", "Pup"], 0),
    ("Nature", "Which tree produces acorns?",
     ["Pine", "Oak", "Maple", "Birch"], 1),
    ("Nature", "What is the fastest land animal?",
     ["Lion", "Cheetah", "Greyhound", "Pronghorn"], 1),
    ("Nature", "Which flower is the national flower of India?",
     ["Rose", "Lotus", "Jasmine", "Marigold"], 1),
    ("Nature", "How many hearts does an octopus have?",
     ["1", "2", "3", "4"], 2),
    ("Nature", "Which is the only mammal capable of true flight?",
     ["Flying squirrel", "Bat", "Sugar glider", "Colugo"], 1),
    # --- General -----------------------------------------------------------
    ("General", "How many days are in a leap year?",
     ["365", "366", "364", "367"], 1),
    ("General", "What is the most spoken native language in the world?",
     ["English", "Spanish", "Mandarin Chinese", "Hindi"], 2),
    ("General", "Which planet is closest to the Sun?",
     ["Venus", "Mercury", "Mars", "Earth"], 1),
    ("General", "How many sides does a hexagon have?",
     ["5", "6", "7", "8"], 1),
    ("General", "What is the capital of France?",
     ["London", "Paris", "Madrid", "Rome"], 1),
    ("General", "Which month has the fewest days?",
     ["April", "June", "February", "November"], 2),
    ("General", "How many colors are in a rainbow?",
     ["5", "6", "7", "8"], 2),
    ("General", "What do you call a baby dog?",
     ["Kitten", "Puppy", "Cub", "Calf"], 1),
    ("General", "Which date is the longest day of the year in the Northern Hemisphere?",
     ["March 21", "June 21", "September 21", "December 21"], 1),
    ("General", "What is 12 multiplied by 12?",
     ["124", "132", "144", "156"], 2),
    ("General", "In which direction does the Sun rise?",
     ["North", "South", "East", "West"], 2),
    ("General", "How many minutes are in one hour?",
     ["30", "60", "90", "100"], 1),
    ("General", "Which word is the opposite of 'ancient'?",
     ["Old", "Modern", "Historic", "Antique"], 1),
    # --- India -------------------------------------------------------------
    ("India", "What is the national animal of India?",
     ["Lion", "Tiger", "Elephant", "Leopard"], 1),
    ("India", "Which city is known as the 'Pink City' of India?",
     ["Udaipur", "Jaipur", "Jodhpur", "Agra"], 1),
    ("India", "The Gateway of India is in which city?",
     ["Delhi", "Mumbai", "Chennai", "Kolkata"], 1),
    ("India", "Which Indian state is famous for its backwaters?",
     ["Goa", "Kerala", "Tamil Nadu", "Odisha"], 1),
    ("India", "Who is known as the 'Father of the Nation' in India?",
     ["Jawaharlal Nehru", "Mahatma Gandhi", "Sardar Patel", "Dr. Ambedkar"], 1),
    ("India", "Diwali is also known as the festival of what?",
     ["Colors", "Lights", "Music", "Harvest"], 1),
    ("India", "Which Mughal emperor built the Taj Mahal?",
     ["Akbar", "Shah Jahan", "Aurangzeb", "Babur"], 1),
    ("India", "What is the currency of India?",
     ["Rupee", "Taka", "Rupiah", "Dinar"], 0),
    ("India", "Which Indian city is known as the 'Silicon Valley of India'?",
     ["Hyderabad", "Chennai", "Bengaluru", "Pune"], 2),
    ("India", "Which sport is India most famous for internationally?",
     ["Hockey", "Cricket", "Football", "Kabaddi"], 1),
    # --- Food --------------------------------------------------------------
    ("Food", "Pizza originated in which country?",
     ["France", "Italy", "Greece", "Spain"], 1),
    ("Food", "Sushi is a traditional dish of which country?",
     ["China", "Thailand", "Japan", "Korea"], 2),
    ("Food", "What is the main ingredient of guacamole?",
     ["Tomato", "Avocado", "Pepper", "Onion"], 1),
    ("Food", "Which spice is known as 'red gold'?",
     ["Turmeric", "Saffron", "Paprika", "Cinnamon"], 1),
    ("Food", "What is tofu made from?",
     ["Wheat", "Soybeans", "Rice", "Corn"], 1),
    # --- Literature --------------------------------------------------------
    ("Literature", "Who wrote 'Romeo and Juliet'?",
     ["Charles Dickens", "William Shakespeare", "Jane Austen", "Oscar Wilde"], 1),
    ("Literature", "Who wrote 'The Jungle Book'?",
     ["Rudyard Kipling", "Mark Twain", "Lewis Carroll", "Enid Blyton"], 0),
    ("Literature", "Which novel begins with the line 'Call me Ishmael'?",
     ["Moby-Dick", "Treasure Island", "Robinson Crusoe", "20,000 Leagues Under the Sea"], 0),
    ("Literature", "Who wrote 'Pride and Prejudice'?",
     ["Charlotte Bronte", "Jane Austen", "Emily Bronte", "Mary Shelley"], 1),
    ("Literature", "Which author created Sherlock Holmes?",
     ["Agatha Christie", "Arthur Conan Doyle", "Edgar Allan Poe", "G.K. Chesterton"], 1),
    ("Literature", "Who wrote the epic poem 'Paradise Lost'?",
     ["John Milton", "Geoffrey Chaucer", "John Donne", "William Blake"], 0),
    # --- Space -------------------------------------------------------------
    ("Space", "What was the first artificial satellite launched into space?",
     ["Explorer 1", "Sputnik 1", "Vostok 1", "Telstar"], 1),
    ("Space", "What is the name of our galaxy?",
     ["Andromeda", "Milky Way", "Triangulum", "Sombrero"], 1),
    ("Space", "Which planet is famous for its prominent ring system?",
     ["Jupiter", "Saturn", "Mars", "Venus"], 1),
    ("Space", "Who was the first human in space?",
     ["Neil Armstrong", "Yuri Gagarin", "Alan Shepard", "Valentina Tereshkova"], 1),
    ("Space", "What is a supernova?",
     ["A new planet", "An exploding star", "A black hole", "A comet"], 1),
]


class TriviaEngine(NativeGameEngine):
    game_id = "trivia"
    min_players = 2
    max_players = 10

    # Reported directly: only 8 of the bank's 15 questions were ever played
    # per game. Using the whole bank means every question gets a turn
    # instead of the game always cutting off partway through it.
    TOTAL_ROUNDS = len(TRIVIA_QUESTIONS)
    ROUND_SECONDS = 20
    REVEAL_DELAY_SECONDS = 1.3
    # How long the correct answer stays up before the next question loads --
    # a real reveal beat, not an instant cut. See `phase` below for why this
    # exists at all.
    REVEAL_HOLD_SECONDS = 3.0

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.round = 0
        self.pool: list[tuple] = []
        self.question: tuple | None = None
        self.question_id = ""
        self.deadline = 0.0
        self.choices_at = 0.0
        self.answered: dict[str, int] = {}
        self.scores: dict[str, int] = {}
        # "answering" while the round timer is live, "reveal" for the beat
        # after it ends where the correct choice is shown. public_state()
        # only includes correctIndex during "reveal" -- it used to be sent
        # unconditionally on every single push, including the very first
        # one for a brand new question, so the TV painted the correct
        # answer green the instant the choices appeared, well before anyone
        # had answered or the timer had run down. Reported directly as
        # "answers are getting revealed way before the questions."
        self.phase = "answering"
        self.reveal_until = 0.0
        self.total_rounds = self.TOTAL_ROUNDS
        self._finished = False
        # Content-pack id used for the current session's pool, so asked
        # questions can be recorded against the right pack history.
        self._pack = "en"

    def start(self, players):
        self.scores = {p.id: 0 for p in players}
        pack = getattr(self.room, "content_pack", "en")
        self._pack = pack
        # Random sampling means no question repeats within a session;
        # fresh_questions additionally skips what this room asked recently.
        pool = fresh_questions(self.room, pack, "trivia")
        self.pool = random.sample(pool, min(self.TOTAL_ROUNDS, len(pool)))
        # A smaller language pack (Telugu/Hindi) plays each question once
        # rather than wrapping round and repeating.
        self.total_rounds = len(self.pool)
        self.round = 0
        self._next_question()

    def _next_question(self):
        self.round += 1
        self.question = self.pool[(self.round - 1) % len(self.pool)]
        self.question_id = f"q{self.round}"
        # Remember the question in the room's rolling history so the next
        # session in this room skips it.
        record_questions(self.room, self._pack, "trivia", [self.question])
        self.answered = {}
        self.phase = "answering"
        now = time.time()
        self.deadline = now + self.ROUND_SECONDS
        self.choices_at = now + self.REVEAL_DELAY_SECONDS

    def seconds_left(self):
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def handle_action(self, player_id, action, data):
        if self._finished or action != "answer" or player_id in self.answered:
            return
        if self.phase != "answering":
            return          # the TV is already showing the correct answer
        if data.get("questionID") != self.question_id:
            return
        idx = data.get("choiceIndex")
        if not isinstance(idx, int):
            return
        self.answered[player_id] = idx
        _, _, _, correct_index = self.question
        if idx == correct_index:
            elapsed = time.time() - (self.deadline - self.ROUND_SECONDS)
            points = max(20, 100 - int(elapsed * 4))
            self.scores[player_id] = self.scores.get(player_id, 0) + points
            player = self.room.player(player_id)
            if player is not None:
                player.score = self.scores[player_id]

    def tick(self, dt):
        if self._finished:
            return
        now = time.time()
        if self.phase == "reveal":
            # Holding here, rather than advancing the instant the timer or
            # every answer comes in, is what actually gives the reveal beat
            # above a duration to be seen for.
            if now >= self.reveal_until:
                if self.round >= self.total_rounds:
                    self._finished = True
                else:
                    self._next_question()
            return

        active = self.room.connected_players()
        everyone_answered = bool(active) and all(p.id in self.answered for p in active)
        if now >= self.deadline or everyone_answered:
            self.phase = "reveal"
            self.reveal_until = now + self.REVEAL_HOLD_SECONDS

    def public_state(self):
        category, text, choices, correct_index = self.question
        state = {
            "secondsLeft": self.seconds_left(),
            "showChoices": time.time() >= self.choices_at,
            "questionID": self.question_id,
            "questionText": text,
            "choices": choices,
            "category": category,
            "phase": self.phase,
            "answeredPlayerIDs": list(self.answered.keys()),
            "players": [
                {"id": p.id, "name": p.name, "score": self.scores.get(p.id, 0), "isHost": p.is_host}
                for p in self.room.players
            ],
            "finished": self._finished,
        }
        # Only present once the reveal phase actually starts -- see the
        # `phase` doc comment in __init__ for why this can't just be sent
        # unconditionally.
        if self.phase == "reveal":
            state["correctIndex"] = correct_index
        return state

    def private_state(self, player_id):
        # The phone needs the question text itself, not just the choices --
        # without it the controller shows answer buttons with no question.
        category, text, choices, _ = self.question
        return {
            "choices": choices,
            "questionID": self.question_id,
            "questionText": text,
            "category": category,
            "score": self.scores.get(player_id, 0),
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results(self.scores)


ENGINES = {
    "mafia": MafiaEngine,
    "raja_mantri": RajaMantriEngine,
    "trivia": TriviaEngine,
}
