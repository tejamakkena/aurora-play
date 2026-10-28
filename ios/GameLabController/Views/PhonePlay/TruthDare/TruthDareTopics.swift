import Foundation

// MARK: - Truth or Dare topics
//
// A topic narrows the cards to one theme ("Desi Family", "Office", "Bollywood").
// Mixed, the default, is the level's own cards plus every topic the level
// allows. A topic's cards sit at its `minLevel`: Couples needs Teens or above,
// the rest are all ages. Same rules as the level cards: cheeky at most, never
// explicit, cruel or dangerous.

enum TruthDareTopic: String, CaseIterable, Identifiable {
    case mixed
    case desiFamily
    case friends
    case couples
    case work
    case movies
    case food
    case travel
    case childhood
    case phones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixed:      return "Mixed"
        case .desiFamily: return "Desi Family"
        case .friends:    return "Friends"
        case .couples:    return "Couples"
        case .work:       return "Office"
        case .movies:     return "Bollywood"
        case .food:       return "Food"
        case .travel:     return "Travel"
        case .childhood:  return "Childhood"
        case .phones:     return "Phones"
        }
    }

    var minLevel: TruthDareLevel {
        self == .couples ? .teens : .family
    }

    /// What "Fresh AI cards" asks for when this topic is picked.
    var aiTopic: String {
        switch self {
        case .mixed:      return ""
        case .desiFamily: return "Indian family life: aunties, weddings, festivals, the family WhatsApp group"
        case .friends:    return "friendships, college days and the group chat"
        case .couples:    return "couples and dating, sweet and cheeky but never explicit"
        case .work:       return "office life: meetings, bosses, emails and deadlines"
        case .movies:     return "Bollywood and Tollywood films, songs, dialogues and stars"
        case .food:       return "food, cooking disasters and eating habits"
        case .travel:     return "holidays, trips and travel mishaps"
        case .childhood:  return "childhood memories, school days and growing up"
        case .phones:     return "phones, social media, selfies and screen time"
        }
    }

    var truths: [String] { TruthDareTopicCards.truths[self] ?? [] }
    var dares: [String] { TruthDareTopicCards.dares[self] ?? [] }
}

enum TruthDareTopicCards {

    static let truths: [TruthDareTopic: [String]] = [
        .desiFamily: [
            "Which relative's question at weddings do you dread the most?",
            "What is the most dramatic thing that has happened in your family WhatsApp group?",
            "Which family function did you pretend to be sick to skip?",
            "What is one thing your parents still do not know you did?",
            "Which aunty or uncle always compares you to someone else, and to whom?",
            "What is the strangest home remedy your family made you try?",
            "Which festival food do you eat far too much of every year?",
            "Who in your family is the worst at keeping a secret?",
            "What is the funniest thing you have been scolded for in front of guests?",
            "Which family photo of you would you delete forever if you could?",
            "Have you ever hidden from a relative at a shop or a wedding? Tell the story.",
            "What nickname does your family call you that nobody else knows?",
            "What is the longest you have pretended to be studying while doing something else?",
            "Which family tradition do you secretly love the most?",
        ],
        .friends: [
            "Which friend here would you call first in an emergency, and why?",
            "What is the most embarrassing thing you have done in front of your friends?",
            "Who in this group is most likely to be famous one day?",
            "What is a secret you kept from your best friend for a long time?",
            "Which friend's cooking would you never eat again?",
            "What is the silliest fight you have ever had with a friend?",
            "Who in the group chat replies the slowest, and do you forgive them?",
            "What is the worst gift a friend has ever given you?",
            "Which friend do you think knows you the best?",
            "Have you ever pretended to like a friend's crush? Who?",
            "What is your funniest memory with someone in this room?",
            "What is the craziest plan your friends talked you into?",
            "Who here would survive longest on a desert island?",
            "What is one thing you have never told this group?",
        ],
        .couples: [
            "What was your very first impression of your partner?",
            "What is the most romantic thing anyone has ever done for you?",
            "What is your partner's most annoying habit, said with love?",
            "Who said I love you first, and how did it happen?",
            "What is the worst date you have ever been on?",
            "What song makes you think of your partner?",
            "What is one thing your partner does that always makes you smile?",
            "Who is the better cook in your relationship? Be honest.",
            "What is the silliest argument you two have ever had?",
            "Where would your dream date be, money no object?",
            "What is a habit of yours your partner had to get used to?",
            "Have you ever stalked an ex online? How far back did you scroll?",
            "What is the most embarrassing thing that happened on a date?",
            "What is one thing you would change about your first date?",
        ],
        .work: [
            "What is the most ridiculous excuse you have used to leave work early?",
            "Have you ever fallen asleep in a meeting? Did anyone notice?",
            "What is the worst email you have ever sent by mistake?",
            "Which colleague do you secretly think is the funniest?",
            "What job would you do if money did not matter at all?",
            "What is the longest you have pretended to work while doing nothing?",
            "Have you ever been caught complaining about your boss?",
            "What is the strangest thing you have seen in an office fridge?",
            "What is your most used excuse for a late reply?",
            "Have you ever said you were on mute when you were not?",
            "What is the worst job interview you have ever had?",
            "What do you really do during long video calls with the camera off?",
        ],
        .movies: [
            "Which Bollywood or Tollywood film have you watched more than five times?",
            "Which film dialogue do you use most in real life? Say it with style.",
            "Which film star would you most like to swap lives with for a day?",
            "Which movie made you cry the most, honestly?",
            "Which film song do you know every single word of?",
            "Which hit movie do you secretly think was terrible?",
            "Have you ever acted out a film scene alone in your room? Which one?",
            "Which villain do you actually like more than the hero?",
            "Which film's dance step do you pull out at every wedding?",
            "If your life were a film, what would it be called?",
            "Which actor or actress was your first big film crush?",
            "What is the longest you have waited in a queue for a first-day show?",
        ],
        .food: [
            "What is the strangest food combination you secretly love?",
            "What is the worst thing you have ever cooked?",
            "Which food would you never share, not even with your best friend?",
            "Have you ever eaten something off the floor after the five second rule?",
            "What is the most you have ever eaten in one sitting?",
            "Which dish does everyone love that you cannot stand?",
            "Have you ever finished someone else's leftovers without asking?",
            "What is your midnight snack of choice?",
            "Which street food could you eat every day?",
            "Have you ever lied about cooking something you actually bought?",
            "What is the spiciest thing you have ever eaten, and what happened?",
            "Which family recipe would you save from a fire?",
        ],
        .travel: [
            "What is the worst trip you have ever been on?",
            "Have you ever missed a train, bus or flight? What happened?",
            "What is the strangest thing you have packed for a trip?",
            "Which place would you visit tomorrow if someone else paid?",
            "What is the most embarrassing thing that happened to you on holiday?",
            "Have you ever got completely lost somewhere new?",
            "What is the worst hotel or place you have stayed in?",
            "Who here would be the worst travel partner, and why?",
            "What souvenir have you bought that you regret?",
            "What is the longest journey you have ever taken?",
            "Have you ever pretended to understand a language you did not speak?",
            "Which trip do you remember best from your childhood?",
        ],
        .childhood: [
            "What did you want to be when you grew up?",
            "What is the naughtiest thing you did as a child?",
            "Which cartoon did you watch every single day?",
            "What is the silliest thing you believed as a kid?",
            "Who was your best friend in primary school?",
            "What is the worst haircut you had as a child?",
            "Have you ever blamed a sibling for something you did?",
            "What was your favourite toy, and do you still have it?",
            "What is the funniest thing you did to avoid going to school?",
            "Which teacher did you like the most, and why?",
            "What did you spend your pocket money on?",
            "What is a smell or taste that takes you straight back to childhood?",
        ],
        .phones: [
            "Who was the last person you texted, and what did you say?",
            "What is the most embarrassing app on your phone?",
            "How many unread messages do you have right now?",
            "What is the last thing you searched for online?",
            "Have you ever sent a message to the wrong person? What was it?",
            "Which app do you spend way too much time on?",
            "How many selfies did you take before your last profile picture?",
            "Have you ever pretended your battery died to get out of a call?",
            "What is the oldest photo on your phone right now?",
            "Who here would you trust with your unlocked phone for an hour?",
            "What is the funniest autocorrect mistake you have ever sent?",
            "Which group chat would you leave if you could?",
        ],
    ]

    static let dares: [TruthDareTopic: [String]] = [
        .desiFamily: [
            "Do your best impression of an aunty at a wedding asking about marriage plans.",
            "Give a dramatic blessing to the person on your left, like a grandparent.",
            "Act out a family argument over the TV remote, playing every person.",
            "Do a two minute TV advert for your mother's cooking.",
            "Dance like it is the baraat and the band has just started.",
            "Bargain with the person on your right for a vegetable, shopkeeper style.",
            "Say Happy Diwali in the most dramatic voice you can.",
            "Give a speech as if you just topped your class board exams.",
            "Greet everyone in the room the way you greet elders at a family function, very seriously.",
            "Read your last forwarded WhatsApp message aloud like a news anchor.",
            "Act out an uncle telling the same joke for the tenth time.",
            "Pretend to receive a call from a relative asking about your salary.",
        ],
        .friends: [
            "Do an impression of someone in this room until somebody guesses who.",
            "Let the group pick a song you have to sing the chorus of.",
            "Give a heartfelt award speech to the friend on your left.",
            "Show the group your most recent photo, no skipping.",
            "Talk in a whisper until your next turn.",
            "Do your best dance move for ten seconds.",
            "Tell a two line story about how this group met, as a movie trailer.",
            "Speak only in questions until your next turn.",
            "Let the person on your right style your hair however they like.",
            "Give everyone in the room a new nickname.",
            "Recreate a famous group photo pose with two other players.",
            "Pretend to be the group's tour guide for one minute.",
        ],
        .couples: [
            "Serenade your partner, or the nearest person, with a romantic film song.",
            "Recreate the most famous romantic scene you can think of with another player.",
            "Describe your dream date in exactly ten words.",
            "Do your best impression of your partner, or of a famous couple.",
            "Propose to a cushion as dramatically as you can.",
            "Write a two line love poem about the snacks on the table and read it aloud.",
            "Slow dance with another player for twenty seconds.",
            "Give your partner, or someone here, three sincere compliments.",
            "Act out how you would react to a surprise anniversary party.",
            "Hold hands with the player on your left until your next turn.",
            "Tell the story of your first date as a sports commentator.",
            "Say I love you in three different accents.",
        ],
        .work: [
            "Give a one minute presentation on why naps should be mandatory at work.",
            "Act out your boss walking into a meeting late.",
            "Say you are on mute in five different dramatic ways.",
            "Pitch a ridiculous product to the group like it is a startup.",
            "Do a dramatic reading of the most boring email you can imagine.",
            "Act out a video call where your internet keeps freezing.",
            "Give a motivational speech as the most annoying manager ever.",
            "Act out asking your boss for a holiday, then getting told no.",
            "Do a performance review of the person on your left, very seriously.",
            "Mime typing furiously while explaining what you are working on.",
            "Do the office walk of someone who has just been promoted.",
            "Answer the next question like it is a job interview.",
        ],
        .movies: [
            "Deliver a famous film dialogue in the style of a news anchor.",
            "Do a dramatic slow-motion entry like a film hero.",
            "Act out the climax fight scene of any action movie, with sound effects.",
            "Sing a film song, but every word has to be la.",
            "Recreate a famous movie poster pose.",
            "Do the signature step from a hit film song.",
            "Act like a villain announcing an evil plan for one minute.",
            "Describe your day today as if it were a movie trailer.",
            "Cry like the heroine at the station when the train leaves.",
            "Do your best impression of a famous film star until someone guesses who.",
            "Act out a romantic scene with a pillow as your co-star.",
            "Narrate what the next player does as a film narrator.",
        ],
        .food: [
            "Describe the last thing you ate like a top chef.",
            "Eat a snack with no hands, if it is safe to do so.",
            "Do a TV cooking show for making a cup of tea.",
            "Act out eating the spiciest chilli in the world.",
            "Invent a new dish and sell it to the group in thirty seconds.",
            "Mime making your favourite meal from start to finish.",
            "Rate everyone's snack choices like a food critic.",
            "Pretend you are a waiter taking everyone's order in a fancy accent.",
            "Do a dramatic tasting of a glass of water.",
            "Sing a song about your favourite food, made up on the spot.",
            "Act out a food delivery that arrives two hours late.",
            "Describe your favourite street food without saying its name until someone guesses it.",
        ],
        .travel: [
            "Be a flight attendant giving the safety talk, with actions.",
            "Act out getting through airport security with something silly in your bag.",
            "Give a tour of this room as if it is a famous monument.",
            "Pretend you are lost and ask the group for directions in a made-up language.",
            "Act out a long train journey in thirty seconds.",
            "Do a travel vlog intro for this living room.",
            "Haggle with someone here for a souvenir.",
            "Act out the worst holiday photo pose you can think of.",
            "Describe your dream trip as an over-excited travel agent.",
            "Pack an imaginary suitcase out loud, naming everything.",
            "Act out sleeping in an airport chair.",
            "Pretend your luggage has been lost and complain to the person on your right.",
        ],
        .childhood: [
            "Sing a nursery rhyme with a dramatic twist.",
            "Act out a child begging for a toy in a shop.",
            "Do your best cartoon character impression.",
            "Play a playground game with the person on your left for thirty seconds.",
            "Act out being sent to the head teacher's office.",
            "Recite a poem you learnt in school, or make one up.",
            "Act like a child on the first day of school.",
            "Show everyone how you used to dance as a kid.",
            "Pretend to be a teacher taking attendance for this room.",
            "Act out sneaking a sweet from the kitchen.",
            "Do your best impression of your old school principal.",
            "Tell a bedtime story in under one minute.",
        ],
        .phones: [
            "Read out your last sent text message, no editing.",
            "Show the group your screen time for today.",
            "Do a dramatic unboxing of your own phone, like a tech reviewer.",
            "Take a dramatic selfie with everyone in the room.",
            "Describe your phone wallpaper without showing it until someone guesses it.",
            "Act out losing your phone and then finding it in your hand.",
            "Do a dramatic reading of your last autocorrect fail.",
            "Show the last photo in your camera roll.",
            "Talk like a voice assistant until your next turn.",
            "Act out a phone with one percent battery.",
            "Show everyone your home screen and explain every app.",
            "Put your phone face down and do not touch it until the end of the next round.",
        ],
    ]
}
