#!/bin/bash

# Comprehensive Game Audit Script for Issue #26
# This script analyzes all 9 games for performance and functionality issues

OUTPUT_DIR="docs/audit_reports"
mkdir -p "$OUTPUT_DIR"

echo "🔍 Starting comprehensive game audit for Issue #26..."
echo ""

# Array of games to audit
games=(
    "tictactoe"
    "connect4"
    "snake"
    "poker"
    "roulette"
    "trivia"
    "canvas_battle"
    "digit_guess"
)

# Function to audit a single game
audit_game() {
    local game=$1
    local js_file="static/js/games/${game}.js"
    local html_file="templates/games/${game}.html"
    local report_file="${OUTPUT_DIR}/${game}_audit.md"
    
    echo "🎮 Auditing: $game"
    echo "================================================" > "$report_file"
    echo "# ${game} Game Audit Report" >> "$report_file"
    echo "## Issue #26 - Game Performance and Functionality" >> "$report_file"
    echo "" >> "$report_file"
    echo "**Audit Date:** $(date)" >> "$report_file"
    echo "**Game:** ${game}" >> "$report_file"
    echo "" >> "$report_file"
    
    # Check if files exist
    echo "## File Status" >> "$report_file"
    if [ -f "$js_file" ]; then
        echo "- ✅ JavaScript file exists: $js_file" >> "$report_file"
        echo "- **Lines of code:** $(wc -l < "$js_file")" >> "$report_file"
    else
        echo "- ❌ **CRITICAL**: JavaScript file missing: $js_file" >> "$report_file"
    fi
    
    if [ -f "$html_file" ]; then
        echo "- ✅ Template file exists: $html_file" >> "$report_file"
    else
        echo "- ❌ Template file missing: $html_file" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # Only analyze if JS file exists
    if [ ! -f "$js_file" ]; then
        echo "⚠️  Skipping detailed analysis - JS file missing"
        return
    fi
    
    # Check for CleanupManager usage
    echo "## Memory Management" >> "$report_file"
    if grep -q "CleanupManager" "$js_file"; then
        echo "- ✅ CleanupManager is used" >> "$report_file"
        local cleanup_uses=$(grep -c "cleanup\." "$js_file")
        echo "- **CleanupManager method calls:** $cleanup_uses" >> "$report_file"
        
        # Check specific cleanup methods
        if grep -q "cleanup.addEventListener" "$js_file"; then
            echo "  - ✅ Uses cleanup.addEventListener" >> "$report_file"
        fi
        if grep -q "cleanup.addInterval" "$js_file"; then
            echo "  - ✅ Uses cleanup.addInterval" >> "$report_file"
        fi
        if grep -q "cleanup.cleanup()" "$js_file"; then
            echo "  - ✅ Calls cleanup.cleanup()" >> "$report_file"
        fi
    else
        echo "- ⚠️  **WARNING**: CleanupManager not found - potential memory leaks" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # Check for WebSocket usage
    echo "## WebSocket Implementation" >> "$report_file"
    if grep -q -i "websocket\|socket\.io\|ws://" "$js_file"; then
        echo "- ℹ️  Uses WebSocket/Socket.io" >> "$report_file"
        echo "  - **Note**: Review for proper cleanup and error handling" >> "$report_file"
    else
        echo "- ℹ️  Uses polling (fetch/HTTP requests)" >> "$report_file"
        local polling_count=$(grep -c "setInterval\|setTimeout" "$js_file")
        echo "  - **Polling mechanisms found:** $polling_count" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # Check polling intervals
    echo "## Performance - Polling Intervals" >> "$report_file"
    if grep -q "setInterval" "$js_file"; then
        echo "- ℹ️  Uses setInterval for updates" >> "$report_file"
        echo "  - **Intervals found:**" >> "$report_file"
        grep -n "setInterval" "$js_file" | while read -r line; do
            echo "    - Line ${line%%:*}: ${line#*:}" >> "$report_file"
        done
    else
        echo "- ✅ No setInterval found" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # Check for common performance issues
    echo "## Performance - DOM Operations" >> "$report_file"
    local inner_html_count=$(grep -c "innerHTML" "$js_file")
    local query_all_count=$(grep -c "querySelectorAll\|getElementsBy" "$js_file")
    
    echo "- **innerHTML operations:** $inner_html_count" >> "$report_file"
    if [ $inner_html_count -gt 10 ]; then
        echo "  - ⚠️  High number of innerHTML operations - review for efficiency" >> "$report_file"
    fi
    echo "- **DOM queries:** $query_all_count" >> "$report_file"
    echo "" >> "$report_file"
    
    # Check for error handling
    echo "## Error Handling" >> "$report_file"
    local try_catch_count=$(grep -c "try\s*{" "$js_file")
    local catch_count=$(grep -c "catch\s*(" "$js_file")
    local console_error=$(grep -c "console.error" "$js_file")
    
    echo "- **Try-catch blocks:** $try_catch_count" >> "$report_file"
    echo "- **Catch statements:** $catch_count" >> "$report_file"
    echo "- **Console.error calls:** $console_error" >> "$report_file"
    
    if [ $catch_count -eq 0 ]; then
        echo "  - ⚠️  **WARNING**: No error handling found" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # Check for visibility handling
    echo "## Tab Visibility Optimization" >> "$report_file"
    if grep -q "visibilitychange" "$js_file"; then
        echo "- ✅ Handles tab visibility (pauses when hidden)" >> "$report_file"
    else
        echo "- ⚠️  No tab visibility handling - continues polling when tab is hidden" >> "$report_file"
    fi
    echo "" >> "$report_file"
    
    # Check for common issues
    echo "## Potential Issues Checklist" >> "$report_file"
    echo "- [ ] Test room creation" >> "$report_file"
    echo "- [ ] Test room joining" >> "$report_file"
    echo "- [ ] Test game start mechanism" >> "$report_file"
    echo "- [ ] Test game logic execution" >> "$report_file"
    echo "- [ ] Test win/loss detection" >> "$report_file"
    echo "- [ ] Test UI updates" >> "$report_file"
    echo "- [ ] Check browser console for errors" >> "$report_file"
    echo "- [ ] Test on mobile browsers" >> "$report_file"
    echo "" >> "$report_file"
    
    # Code metrics
    echo "## Code Metrics" >> "$report_file"
    local func_count=$(grep -c "^function\|async function\|const.*=.*function\|let.*=.*function" "$js_file")
    local comment_count=$(grep -c "^//" "$js_file")
    
    echo "- **Functions/methods:** $func_count" >> "$report_file"
    echo "- **Single-line comments:** $comment_count" >> "$report_file"
    echo "" >> "$report_file"
    
    echo "✅ Audit complete for $game"
    echo ""
}

# Audit all games
for game in "${games[@]}"; do
    audit_game "$game"
done

# Special handling for raja_mantri (has inline JS)
echo "🎮 Auditing: raja_mantri (special case - inline JS)"
RAJA_REPORT="${OUTPUT_DIR}/raja_mantri_audit.md"

cat > "$RAJA_REPORT" << 'EOF'
================================================
# raja_mantri Game Audit Report
## Issue #26 - Game Performance and Functionality

**Audit Date:** $(date)
**Game:** raja_mantri

## File Status
- ❌ **CRITICAL**: No separate JavaScript file exists
- ✅ Template file exists: templates/games/raja_mantri.html
- ⚠️  **Uses inline JavaScript in HTML template**

## Critical Issues

### 1. No Separate JS File
- JavaScript is embedded directly in the HTML template
- This violates the architecture pattern used by all other games
- Makes maintenance and debugging difficult
- No code reusability

### 2. Architecture Inconsistency
- All other 8 games have separate JS files in `static/js/games/`
- Raja Mantri is the only exception
- Should be refactored to match the pattern

### 3. Missing CleanupManager
- Cannot use CleanupManager with inline scripts
- Potential memory leaks from event listeners
- No proper resource cleanup

### 4. No Network Communication
- Currently a local-only game (no room creation/joining)
- Players must all be on the same device
- Doesn't follow the multiplayer pattern of other games

## Recommendations

### High Priority
1. **Extract JS to separate file**: Create `static/js/games/raja_mantri.js`
2. **Implement multiplayer**: Add room creation/joining like other games
3. **Add CleanupManager**: Implement proper resource management
4. **Add server-side game logic**: Currently all logic is client-side

### Medium Priority
5. Add proper error handling
6. Implement game state polling
7. Add mobile responsiveness
8. Add visual feedback for game events

## Potential Issues Checklist
- [ ] Extract inline JS to separate file
- [ ] Implement multiplayer functionality
- [ ] Add CleanupManager
- [ ] Test room creation (N/A - not implemented)
- [ ] Test room joining (N/A - not implemented)
- [ ] Test game start mechanism
- [ ] Test game logic execution
- [ ] Test UI updates
- [ ] Check browser console for errors
- [ ] Test on mobile browsers

## Status
⚠️  **NEEDS MAJOR REFACTORING** - Currently not following the application architecture
EOF

echo "✅ Audit complete for raja_mantri"
echo ""

# Create summary report
SUMMARY="${OUTPUT_DIR}/SUMMARY.md"
echo "📊 Creating summary report..."

cat > "$SUMMARY" << 'EOF'
# Game Audit Summary Report
## Issue #26 - Full Game Audit

**Generated:** $(date)

## Overview

This audit covers all 9 games in GameLab2 for performance and functionality issues as reported in Issue #26.

## Games Audited

1. ✅ TicTacToe
2. ✅ Connect4 (has active PR #25)
3. ✅ Snake
4. ✅ Poker
5. ✅ Roulette
6. ✅ Trivia
7. ⚠️  Raja Mantri (critical issues found)
8. ✅ Canvas Battle
9. ✅ Digit Guess

## Critical Findings

### Raja Mantri - Major Architecture Issue
- **No separate JS file** - uses inline JavaScript
- **No multiplayer support** - local game only
- **No CleanupManager** - potential memory leaks
- **Requires complete refactoring**

## Common Issues Found

### Memory Management
EOF

# Count games with CleanupManager
games_with_cleanup=0
games_without_cleanup=0

for game in "${games[@]}"; do
    js_file="static/js/games/${game}.js"
    if [ -f "$js_file" ]; then
        if grep -q "CleanupManager" "$js_file"; then
            ((games_with_cleanup++))
        else
            ((games_without_cleanup++))
            echo "- ⚠️  **${game}** - Missing CleanupManager" >> "$SUMMARY"
        fi
    fi
done

echo "" >> "$SUMMARY"
echo "**Summary:** $games_with_cleanup games use CleanupManager, $games_without_cleanup do not" >> "$SUMMARY"
echo "" >> "$SUMMARY"

cat >> "$SUMMARY" << 'EOF'

### Performance Optimization

Review individual game reports for:
- Polling interval optimization
- DOM operation efficiency
- Tab visibility handling
- Error handling completeness

## Next Steps

1. **Immediate**: Fix Raja Mantri architecture
2. **High Priority**: Add CleanupManager to games missing it
3. **Medium Priority**: Optimize polling intervals
4. **Testing**: Browser testing for all games
5. **Mobile**: Test responsive design (related to Issue #4)

## Detailed Reports

Individual audit reports are available in the `audit_reports/` directory:
EOF

for game in "${games[@]}"; do
    echo "- [${game}](${game}_audit.md)" >> "$SUMMARY"
done
echo "- [raja_mantri](raja_mantri_audit.md)" >> "$SUMMARY"

echo ""
echo "✅ Summary report created: $SUMMARY"
echo ""
echo "================================================"
echo "🎉 Audit Complete!"
echo "================================================"
echo ""
echo "📁 All reports saved in: $OUTPUT_DIR/"
echo ""
echo "📋 Key Findings:"
echo "  - $games_with_cleanup/8 games use CleanupManager"
echo "  - Raja Mantri needs complete refactoring"
echo "  - Individual reports available for detailed analysis"
echo ""
echo "Next: Review reports and prioritize fixes"
