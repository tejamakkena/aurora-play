"""
Game logic for Digit Guess (Bulls & Cows / Mastermind)
2-player turn-based number guessing game
"""


def validate_number(number):
    """
    Validate that the number is exactly 4 digits
    Returns (is_valid, error_message)
    """
    if not isinstance(number, str):
        number = str(number)
    
    # Remove any whitespace
    number = number.strip()
    
    # Check if it's exactly 4 characters
    if len(number) != 4:
        return False, "Number must be exactly 4 digits"
    
    # Check if all characters are digits
    if not number.isdigit():
        return False, "Number must contain only digits"
    
    return True, None


def calculate_feedback(secret, guess):
    """
    Calculate feedback for a guess against the secret number
    
    Args:
        secret (str): The secret 4-digit number
        guess (str): The guessed 4-digit number
    
    Returns:
        dict: {
            'correct_digits': int,  # How many digits are correct (in any position)
            'correct_positions': int  # How many digits are in the correct position
        }
    """
    secret = str(secret)
    guess = str(guess)
    
    # Count correct positions (exact matches)
    correct_positions = sum(1 for i in range(4) if secret[i] == guess[i])
    
    # Count correct digits (including those in correct positions)
    # Use min of count in secret and count in guess for each digit
    correct_digits = 0
    for digit in set(guess):
        secret_count = secret.count(digit)
        guess_count = guess.count(digit)
        correct_digits += min(secret_count, guess_count)
    
    return {
        'correct_digits': correct_digits,
        'correct_positions': correct_positions
    }


def check_winner(guess, secret):
    """
    Check if the guess matches the secret (game won)
    
    Args:
        guess (str): The guessed number
        secret (str): The secret number
    
    Returns:
        bool: True if guess matches secret exactly
    """
    return str(guess) == str(secret)


def get_game_state_display(guesses, player_name):
    """
    Format guess history for display
    
    Args:
        guesses (list): List of guess dictionaries
        player_name (str): Name of the player
    
    Returns:
        list: Formatted guess history
    """
    return [
        {
            'guess': g['guess'],
            'feedback': f"{g['feedback']['correct_positions']} in position, {g['feedback']['correct_digits']} total correct",
            'player': player_name
        }
        for g in guesses
    ]


def generate_secret_code():
    """Generate a 4-digit secret with all unique digits, as a string."""
    import random
    digits = random.sample("0123456789", 4)
    return "".join(digits)


def check_guess(secret, guess):
    """Return (bulls, cows): exact-position matches and digit matches.

    Note: argument order is (secret, guess), matching calculate_feedback.
    """
    fb = calculate_feedback(secret, guess)
    bulls = fb["correct_positions"]
    cows = fb["correct_digits"] - bulls
    return bulls, cows
