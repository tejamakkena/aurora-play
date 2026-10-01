#!/usr/bin/env python3
"""
Test script for Digit Guess game logic
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'games', 'digit_guess'))

# Import directly from game_logic to avoid Flask dependencies
import game_logic

def test_validate_number():
    print("Testing validate_number()...")
    
    # Valid cases
    assert game_logic.validate_number("1234")[0] == True
    assert game_logic.validate_number("0000")[0] == True
    assert game_logic.validate_number("9999")[0] == True
    
    # Invalid cases
    assert game_logic.validate_number("123")[0] == False  # Too short
    assert game_logic.validate_number("12345")[0] == False  # Too long
    assert game_logic.validate_number("12a4")[0] == False  # Non-digit
    assert game_logic.validate_number("")[0] == False  # Empty
    
    print("✅ validate_number() tests passed!")

def test_calculate_feedback():
    print("\nTesting calculate_feedback()...")
    
    # Exact match
    result = game_logic.calculate_feedback("1234", "1234")
    assert result['correct_digits'] == 4
    assert result['correct_positions'] == 4
    
    # No match
    result = game_logic.calculate_feedback("1234", "5678")
    assert result['correct_digits'] == 0
    assert result['correct_positions'] == 0
    
    # All digits correct but wrong positions
    result = game_logic.calculate_feedback("1234", "4321")
    assert result['correct_digits'] == 4
    assert result['correct_positions'] == 0
    
    # Some correct positions
    result = game_logic.calculate_feedback("1234", "1567")
    assert result['correct_digits'] == 1
    assert result['correct_positions'] == 1
    
    # Mixed: some in position, some not
    result = game_logic.calculate_feedback("1234", "1243")
    assert result['correct_digits'] == 4
    assert result['correct_positions'] == 2  # 1 and 4 in position
    
    # Duplicate digits
    result = game_logic.calculate_feedback("1122", "1234")
    assert result['correct_digits'] == 2  # 1 at pos 0, 2 at pos 2
    assert result['correct_positions'] == 1  # Only 1 at position 0
    
    print("✅ calculate_feedback() tests passed!")

def test_check_winner():
    print("\nTesting check_winner()...")
    
    assert game_logic.check_winner("1234", "1234") == True
    assert game_logic.check_winner("1234", "1235") == False
    assert game_logic.check_winner("0000", "0000") == True
    
    print("✅ check_winner() tests passed!")

if __name__ == "__main__":
    print("=" * 60)
    print("Running Digit Guess Game Logic Tests")
    print("=" * 60)
    
    test_validate_number()
    test_calculate_feedback()
    test_check_winner()
    
    print("\n" + "=" * 60)
    print("🎉 All tests passed!")
    print("=" * 60)
