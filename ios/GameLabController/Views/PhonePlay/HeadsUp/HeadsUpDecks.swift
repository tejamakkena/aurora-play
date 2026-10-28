import SwiftUI

// MARK: - Forehead Charades decks
//
// Bundled, offline and family-friendly. Each deck has 140 to 270 cards, and
// the phone remembers what it dealt (PhonePlayDealer) so cards do not come
// round again until a deck has been played through.

struct HeadsUpDeck: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let colorHex: [String]
    let words: [String]

    var colors: [Color] { colorHex.map { Color(hex: $0) } }

    static func == (lhs: HeadsUpDeck, rhs: HeadsUpDeck) -> Bool { lhs.id == rhs.id }
}

enum HeadsUpDecks {

    static let all: [HeadsUpDeck] = [
        tollywoodMovies, bollywoodMovies, southMovies, tollywoodActors, bollywoodActors, hollywoodMovies,
        animals, cricket, food, jobs, home, places,
    ]

    static let tollywoodMovies = HeadsUpDeck(
        id: "tollywood_movies", title: "Tollywood Movies", symbol: "film.stack.fill",
        colorHex: ["F7971E", "FF4E50"],
        words: HeadsUpData.tollywoodMovies
    )

    static let bollywoodMovies = HeadsUpDeck(
        id: "bollywood_movies", title: "Bollywood Movies", symbol: "popcorn.fill",
        colorHex: ["FF512F", "DD2476"],
        words: HeadsUpData.bollywoodMovies
    )

    static let southMovies = HeadsUpDeck(
        id: "south_movies", title: "South Indian Hits", symbol: "film.circle.fill",
        colorHex: ["11998E", "38EF7D"],
        words: HeadsUpData.southMovies
    )

    static let tollywoodActors = HeadsUpDeck(
        id: "tollywood_actors", title: "Tollywood Actors", symbol: "star.fill",
        colorHex: ["FDC830", "F37335"],
        words: HeadsUpData.tollywoodActors
    )

    static let bollywoodActors = HeadsUpDeck(
        id: "bollywood_actors", title: "Bollywood Actors", symbol: "star.circle.fill",
        colorHex: ["EC008C", "FC6767"],
        words: HeadsUpData.bollywoodActors
    )

    static let hollywoodMovies = HeadsUpDeck(
        id: "hollywood_movies", title: "Hollywood Movies", symbol: "film.fill",
        colorHex: ["FF5F6D", "FFC371"],
        words: HeadsUpData.hollywoodMovies + HeadsUpDecks.classicMovies
    )

    /// The original family movie cards, kept as part of the Hollywood deck.
    private static let classicMovies: [String] = [
        "The Lion King", "Frozen", "Toy Story", "Finding Nemo",
        "Harry Potter", "Star Wars", "Jurassic Park", "Spider-Man",
        "Batman", "Superman", "Titanic", "Shrek",
        "Aladdin", "Moana", "Coco", "Up",
        "Cars", "Inside Out", "Zootopia", "Encanto",
        "The Jungle Book", "Kung Fu Panda", "Madagascar", "Ice Age",
        "Minions", "Despicable Me", "Avatar", "The Avengers",
        "Iron Man", "Black Panther", "Home Alone", "Mary Poppins",
        "The Wizard of Oz", "Ratatouille", "WALL-E", "Monsters Inc",
        "The Incredibles", "Beauty and the Beast", "Cinderella", "Tangled",
        "Paddington", "Matilda", "Night at the Museum", "Pirates of the Caribbean",
        "E.T.",
    ]

    static let animals = HeadsUpDeck(
        id: "animals", title: "Animals", symbol: "pawprint.fill",
        colorHex: ["11998E", "38EF7D"],
        words: [
            "Elephant", "Giraffe", "Kangaroo", "Penguin", "Tiger",
            "Lion", "Monkey", "Peacock", "Crocodile", "Dolphin",
            "Shark", "Octopus", "Owl", "Parrot", "Camel",
            "Zebra", "Panda", "Koala", "Rabbit", "Squirrel",
            "Snake", "Frog", "Butterfly", "Bee", "Spider",
            "Horse", "Cow", "Goat", "Sheep", "Chicken",
            "Duck", "Crab", "Turtle", "Bat", "Wolf",
            "Fox", "Bear", "Hippo", "Rhino", "Cheetah",
            "Flamingo", "Jellyfish", "Polar Bear", "Gorilla", "Hedgehog",
        ] + HeadsUpData.animals
    )

    static let cricket = HeadsUpDeck(
        id: "cricket", title: "Cricket", symbol: "figure.cricket",
        colorHex: ["2193B0", "6DD5ED"],
        words: [
            "Sachin Tendulkar", "Virat Kohli", "MS Dhoni", "Rohit Sharma", "Kapil Dev",
            "Sunil Gavaskar", "Jasprit Bumrah", "Hardik Pandya", "Ravindra Jadeja", "Anil Kumble",
            "Sourav Ganguly", "Rahul Dravid", "Yuvraj Singh", "Virender Sehwag", "Shubman Gill",
            "Rishabh Pant", "Mithali Raj", "Smriti Mandhana", "Don Bradman", "Shane Warne",
            "Brian Lara", "Muttiah Muralitharan", "Ben Stokes", "Steve Smith", "Kane Williamson",
            "Six", "Four", "Wicket", "Hat-trick", "Century",
            "Duck", "Yorker", "Googly", "Bouncer", "Run Out",
            "Stumped", "LBW", "Super Over", "World Cup", "IPL",
            "Umpire", "Third Umpire", "Wicket Keeper", "Free Hit", "Maiden Over",
        ] + HeadsUpData.cricket
    )

    static let food = HeadsUpDeck(
        id: "food", title: "Food", symbol: "fork.knife",
        colorHex: ["F857A6", "FF5858"],
        words: [
            "Biryani", "Dosa", "Idli", "Samosa", "Pani Puri",
            "Butter Chicken", "Paneer Tikka", "Gulab Jamun", "Jalebi", "Pizza",
            "Burger", "Pasta", "Noodles", "Sushi", "Tacos",
            "Ice Cream", "Chocolate", "Popcorn", "Pancakes", "Waffles",
            "Mango Lassi", "Chai", "Coffee", "Sandwich", "French Fries",
            "Pav Bhaji", "Vada Pav", "Upma", "Pongal", "Pesarattu",
            "Gongura Pickle", "Rasam", "Sambar", "Curd Rice", "Halwa",
            "Ladoo", "Kheer", "Momos", "Spring Rolls", "Doughnut",
            "Cupcake", "Watermelon", "Pineapple", "Banana", "Coconut",
        ] + HeadsUpData.food
    )

    static let jobs = HeadsUpDeck(
        id: "jobs", title: "Jobs", symbol: "briefcase.fill",
        colorHex: ["8E2DE2", "4A00E0"],
        words: [
            "Doctor", "Teacher", "Pilot", "Chef", "Firefighter",
            "Police Officer", "Astronaut", "Farmer", "Dentist", "Nurse",
            "Engineer", "Artist", "Singer", "Dancer", "Magician",
            "Photographer", "Plumber", "Electrician", "Carpenter", "Barber",
            "Tailor", "Postman", "Lifeguard", "Scientist", "Vet",
            "Zookeeper", "Librarian", "Judge", "Lawyer", "Waiter",
            "Cashier", "Mechanic", "Bus Driver", "Taxi Driver", "Sailor",
            "Soldier", "Gardener", "Baker", "Painter", "Clown",
            "Detective", "News Reader", "Cricket Umpire", "Software Developer", "Architect",
        ] + HeadsUpData.jobs
    )

    static let home = HeadsUpDeck(
        id: "home", title: "Things at Home", symbol: "house.fill",
        colorHex: ["43CEA2", "185A9D"],
        words: [
            "Toothbrush", "Pillow", "Blanket", "Mirror", "Ceiling Fan",
            "Refrigerator", "Pressure Cooker", "Television", "Remote Control", "Sofa",
            "Bed", "Chair", "Table", "Clock", "Lamp",
            "Umbrella", "Broom", "Mop", "Bucket", "Washing Machine",
            "Microwave", "Kettle", "Frying Pan", "Spoon", "Plate",
            "Cup", "Towel", "Soap", "Shampoo", "Comb",
            "Shoes", "Slippers", "Door Bell", "Key", "Window",
            "Curtains", "Bookshelf", "Calendar", "Charger", "Laptop",
            "Vacuum Cleaner", "Iron", "Doormat", "Flower Pot", "Light Switch",
        ] + HeadsUpData.home
    )

    static let places = HeadsUpDeck(
        id: "places", title: "Famous Places", symbol: "globe.asia.australia.fill",
        colorHex: ["FDC830", "F37335"],
        words: [
            "Taj Mahal", "Eiffel Tower", "Great Wall of China", "Statue of Liberty", "Pyramids of Giza",
            "Charminar", "Golden Temple", "Gateway of India", "India Gate", "Red Fort",
            "Qutub Minar", "Mysore Palace", "Tirupati", "Ramoji Film City", "Golconda Fort",
            "Big Ben", "Colosseum", "Leaning Tower of Pisa", "Sydney Opera House", "Mount Everest",
            "Niagara Falls", "Grand Canyon", "Burj Khalifa", "Disneyland", "Times Square",
            "Hollywood Sign", "Machu Picchu", "Stonehenge", "Mount Fuji", "Petra",
            "Christ the Redeemer", "Golden Gate Bridge", "Buckingham Palace", "Kerala Backwaters", "Goa Beaches",
            "Hampi", "Ajanta Caves", "Marina Beach", "Lotus Temple", "Victoria Memorial",
            "Hussain Sagar", "Araku Valley", "Statue of Unity", "Kaziranga", "Amazon Rainforest",
        ] + HeadsUpData.places
    )
}
