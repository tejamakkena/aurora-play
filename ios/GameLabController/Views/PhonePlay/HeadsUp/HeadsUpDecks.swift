import SwiftUI

// MARK: - Heads Up decks
//
// Bundled, offline and family-friendly. Each deck has 40+ cards; a round
// of 60 seconds rarely gets through more than 20, and cards are not
// repeated within a session until the deck runs out.

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
        movies, animals, stars, cricket, food, jobs, home, places,
    ]

    static let movies = HeadsUpDeck(
        id: "movies", title: "Movies", symbol: "film.fill",
        colorHex: ["FF5F6D", "FFC371"],
        words: [
            "The Lion King", "Frozen", "Toy Story", "Finding Nemo", "Harry Potter",
            "Star Wars", "Jurassic Park", "Spider-Man", "Batman", "Superman",
            "Titanic", "Shrek", "Aladdin", "Moana", "Coco",
            "Up", "Cars", "Inside Out", "Zootopia", "Encanto",
            "The Jungle Book", "Kung Fu Panda", "Madagascar", "Ice Age", "Minions",
            "Despicable Me", "Avatar", "The Avengers", "Iron Man", "Black Panther",
            "Home Alone", "Mary Poppins", "The Wizard of Oz", "Ratatouille", "WALL-E",
            "Monsters Inc", "The Incredibles", "Beauty and the Beast", "Cinderella", "Tangled",
            "Paddington", "Matilda", "Night at the Museum", "Pirates of the Caribbean", "E.T.",
        ]
    )

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
        ]
    )

    static let stars = HeadsUpDeck(
        id: "stars", title: "Tollywood and Bollywood", symbol: "star.fill",
        colorHex: ["F7971E", "FF4E50"],
        words: [
            "Shah Rukh Khan", "Amitabh Bachchan", "Salman Khan", "Aamir Khan", "Deepika Padukone",
            "Priyanka Chopra", "Alia Bhatt", "Ranveer Singh", "Hrithik Roshan", "Akshay Kumar",
            "Katrina Kaif", "Kareena Kapoor", "Ranbir Kapoor", "Madhuri Dixit", "Rajinikanth",
            "Chiranjeevi", "Mahesh Babu", "Prabhas", "Allu Arjun", "Jr NTR",
            "Ram Charan", "Samantha", "Nani", "Vijay Deverakonda", "Pawan Kalyan",
            "Nagarjuna", "Venkatesh", "Rashmika Mandanna", "Kamal Haasan", "Sridevi",
            "Baahubali", "RRR", "Pushpa", "Sholay", "Lagaan",
            "3 Idiots", "Dangal", "Dilwale Dulhania Le Jayenge", "Magadheera", "Eega",
            "Kalki", "Arjun Reddy", "Jawan", "Pathaan", "Taare Zameen Par",
            "Ala Vaikunthapurramuloo", "Mahanati", "Chak De India",
        ]
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
        ]
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
        ]
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
        ]
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
        ]
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
        ]
    )
}
