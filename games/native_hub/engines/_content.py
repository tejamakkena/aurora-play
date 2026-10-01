"""Static content pools for the party and mid-group games.

Kept in one module so prompts can be extended without touching engine logic.
Indian and Western content sit side by side deliberately -- the catalog is meant
to work for a mixed living room.
"""

# ---- Bluff It: an obscure fact with a blank the players fill with fakes -----
BLUFF_FACTS = [
    ("The world's largest ____ weighs over 900 kilograms.", "pumpkin"),
    ("In Japan it is traditional to eat ____ on Christmas Day.", "fried chicken"),
    ("The national animal of Scotland is the ____.", "unicorn"),
    ("A group of flamingos is called a ____.", "flamboyance"),
    ("The first item ever sold on eBay was a broken ____.", "laser pointer"),
    ("Cows have best friends and get stressed when ____.", "separated"),
    ("The inventor of the Pringles can is buried in ____.", "a Pringles can"),
    ("Bananas are berries, but ____ are not.", "strawberries"),
    ("The shortest war in history lasted ____ minutes.", "38"),
    ("Octopuses have ____ hearts.", "three"),
    ("In India, the world's largest ____ is held every 12 years.", "gathering"),
    ("The Eiffel Tower can be ____ centimetres taller in summer.", "15"),
    ("A shrimp's heart is located in its ____.", "head"),
    ("The dot over a lowercase i is called a ____.", "tittle"),
    ("Wombat droppings are shaped like ____.", "cubes"),
]

# ---- Herd: answer the way you think the crowd will ---------------------------
HERD_PROMPTS = [
    "Name a breakfast food.",
    "Name a colour.",
    "Name something you find in a kitchen.",
    "Name a Bollywood actor.",
    "Name a cricket shot.",
    "Name a wild animal.",
    "Name something you take on holiday.",
    "Name an Indian street food.",
    "Name a superhero.",
    "Name something that is cold.",
    "Name a school subject.",
    "Name a fruit that is not an apple.",
    "Name a mode of transport.",
    "Name something in your pocket right now.",
    "Name a festival.",
]

# ---- Emoji Movie: secret title, describe it in emoji -------------------------
EMOJI_TITLES = [
    "Titanic", "The Lion King", "Jurassic Park", "Finding Nemo", "Frozen",
    "Sholay", "Dangal", "3 Idiots", "Lagaan", "Bahubali",
    "Harry Potter", "The Matrix", "Toy Story", "Spider-Man", "Up",
    "Jaws", "Home Alone", "Inception", "Zootopia", "Cars",
    "Ra.One", "Krrish", "PK", "Queen", "Gully Boy",
]

# ---- Name Place Animal Thing ------------------------------------------------
NPAT_LETTERS = "ABCDGHJKLMNPRSTV"     # letters with enough easy answers
NPAT_FIELDS = ["name", "place", "animal", "thing"]

# ---- Antakshari: song-chain letters -----------------------------------------
ANTAKSHARI_LETTERS = "ABCDGHJKLMNPRSTVY"

# ---- Odd One Out: shared location, one player is the spy --------------------
SPY_LOCATIONS = [
    "Railway station", "Wedding hall", "Cricket stadium", "Hospital",
    "Space station", "Beach resort", "Movie theatre", "School classroom",
    "Airplane", "Submarine", "Bank vault", "Tea plantation",
    "Night market", "Ski lodge", "Art museum", "Police station",
    "Pirate ship", "Casino floor", "Zoo", "Temple",
]

# ---- Cipher Grid: the shared 5x5 word board ---------------------------------
CIPHER_WORDS = [
    "TIGER", "MANGO", "ROCKET", "TEMPLE", "RIVER", "CROWN", "DRAGON", "MONSOON",
    "SPICE", "MARBLE", "COMPASS", "LANTERN", "THUNDER", "PEACOCK", "SILK",
    "HARBOUR", "CANNON", "ORBIT", "JUNGLE", "MIRROR", "PALACE", "FALCON",
    "EMBER", "GLACIER", "BAZAAR", "COMET", "SADDLE", "VIOLIN", "ANCHOR",
    "PYRAMID", "WHISTLE", "BAMBOO", "COBRA", "SUNSET", "IVORY", "NEEDLE",
    "GARLAND", "CANYON", "TURBAN", "LOTUS", "SABRE", "MARKET", "PARROT",
    "FOSSIL", "KETTLE", "MEADOW", "SHADOW", "TRIDENT", "WALNUT", "ZEPHYR",
]

# ---- Wavelength: the two ends of the dial ------------------------------------
WAVELENGTH_SPECTRA = [
    ("Cold", "Hot"), ("Cheap", "Expensive"), ("Underrated", "Overrated"),
    ("Boring", "Exciting"), ("Round", "Pointy"), ("Useless", "Essential"),
    ("Quiet", "Loud"), ("Casual", "Formal"), ("Scary", "Comforting"),
    ("Old-fashioned", "Modern"), ("Sour", "Sweet"), ("Weak", "Powerful"),
    ("Fictional", "Real"), ("Simple", "Complicated"), ("Rude", "Polite"),
]

# ---- Sealed Auction: lots to bid on -----------------------------------------
AUCTION_LOTS = [
    ("A private island", 10), ("The last slice of pizza", 2),
    ("A time machine", 10), ("A lifetime of free chai", 6),
    ("Your neighbour's Wi-Fi password", 3), ("A talking parrot", 4),
    ("Front-row World Cup final tickets", 8), ("A haunted mansion", 5),
    ("An unlimited flight pass", 9), ("A vintage Ambassador car", 6),
    ("A star named after you", 4), ("A robot that does your chores", 8),
]

# ---- KBC Hot Seat: ladder quiz ----------------------------------------------
KBC_QUESTIONS = [
    ("Which planet is known as the Red Planet?",
     ["Mars", "Venus", "Jupiter", "Mercury"], 0),
    ("Who wrote the Indian national anthem?",
     ["Rabindranath Tagore", "Bankim Chandra", "Sarojini Naidu", "Premchand"], 0),
    ("What is the capital of Australia?",
     ["Canberra", "Sydney", "Melbourne", "Perth"], 0),
    ("How many players are on a cricket team?",
     ["11", "10", "12", "9"], 0),
    ("Which gas do plants absorb?",
     ["Carbon dioxide", "Oxygen", "Nitrogen", "Helium"], 0),
    ("The Taj Mahal is in which city?",
     ["Agra", "Delhi", "Jaipur", "Lucknow"], 0),
    ("What is the largest ocean?",
     ["Pacific", "Atlantic", "Indian", "Arctic"], 0),
    ("Who painted the Mona Lisa?",
     ["Leonardo da Vinci", "Michelangelo", "Raphael", "Donatello"], 0),
    ("Which is the longest river in India?",
     ["Ganga", "Yamuna", "Godavari", "Narmada"], 0),
    ("How many continents are there?",
     ["7", "5", "6", "8"], 0),
    ("What is the chemical symbol for gold?",
     ["Au", "Ag", "Gd", "Go"], 0),
    ("Which country hosted the 2016 Olympics?",
     ["Brazil", "China", "Russia", "Japan"], 0),
]

KBC_LADDER = [1000, 2000, 5000, 10000, 20000, 40000, 80000,
              160000, 320000, 640000, 1250000, 2500000]

# ---- Bollywood Charades ------------------------------------------------------
CHARADES_TITLES = [
    "Sholay", "Dilwale Dulhania Le Jayenge", "3 Idiots", "Lagaan", "Dangal",
    "Bahubali", "Andaz Apna Apna", "Munna Bhai MBBS", "Zindagi Na Milegi Dobara",
    "Queen", "Gully Boy", "Chak De India", "Swades", "Rang De Basanti",
    "Kabhi Khushi Kabhie Gham", "Om Shanti Om", "Golmaal", "Hera Pheri",
    "Taare Zameen Par", "Barfi",
]

# ---- Atlas: place-name chain seeds ------------------------------------------
ATLAS_SEEDS = ["India", "Nepal", "Kolkata", "Madrid", "Norway", "Cairo"]

# A generous but finite validation set. Solo Atlas checks against this; in a
# multiplayer game the room adjudicates, which is how it is played anyway.
ATLAS_PLACES = {
    "india", "indonesia", "iran", "iraq", "ireland", "israel", "italy",
    "japan", "jordan", "jamaica", "kenya", "kuwait", "korea", "kolkata",
    "nepal", "norway", "nigeria", "netherlands", "new zealand", "nagpur",
    "australia", "austria", "argentina", "algeria", "afghanistan", "agra",
    "spain", "sweden", "switzerland", "singapore", "sudan", "surat", "sydney",
    "delhi", "denmark", "dubai", "dhaka", "darjeeling",
    "france", "finland", "fiji", "frankfurt",
    "egypt", "ecuador", "england", "ethiopia",
    "germany", "greece", "ghana", "goa", "guwahati",
    "hungary", "hyderabad", "haryana", "havana",
    "mexico", "morocco", "malaysia", "mumbai", "madrid", "manila", "moscow",
    "canada", "china", "chile", "colombia", "chennai", "cairo", "cuba",
    "brazil", "belgium", "bhutan", "bangladesh", "bangalore", "berlin",
    "portugal", "poland", "peru", "pakistan", "paris", "pune", "prague",
    "turkey", "thailand", "tanzania", "tokyo", "toronto", "tunisia",
    "russia", "romania", "rwanda", "rome", "riyadh", "raipur",
    "ukraine", "uganda", "uruguay", "uzbekistan",
    "vietnam", "venezuela", "vienna", "vadodara",
    "yemen", "york", "yokohama",
    "zambia", "zimbabwe", "zurich",
    "oman", "oslo", "ottawa", "osaka",
    "lebanon", "libya", "laos", "london", "lucknow", "lisbon",
}

# ---- Most Likely To: secret-ballot party voting -----------------------------
MOST_LIKELY_PROMPTS = [
    "Most likely to fall asleep during a family movie night.",
    "Most likely to take charge of the music at a party.",
    "Most likely to be late to a wedding.",
    "Most likely to eat the most at a buffet.",
    "Most likely to win an argument with mom.",
    "Most likely to forget where they parked the car.",
    "Most likely to take a hundred photos and post none.",
    "Most likely to start dancing first at a sangeet.",
    "Most likely to know all the cricket scores by heart.",
    "Most likely to order extra dessert.",
    "Most likely to lose their phone inside their own house.",
    "Most likely to give the best wedding speech.",
    "Most likely to call the family group chat instead of texting.",
    "Most likely to finish everyone else's leftovers.",
    "Most likely to plan the next family trip.",
    "Most likely to binge a whole series in one night.",
    "Most likely to be the peacemaker in a family debate.",
    "Most likely to bring the best homemade dish to a potluck.",
    "Most likely to get lost but refuse to ask for directions.",
    "Most likely to remember everyone's birthday.",
    "Most likely to fall for a WhatsApp forward.",
    "Most likely to be the first one ready for an outing.",
    "Most likely to steal the blanket at night.",
    "Most likely to host the next Diwali party.",
    "Most likely to sing in the car like nobody is listening.",
]
