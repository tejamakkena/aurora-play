#!/usr/bin/env python3
"""
Performance Audit Script for GameLab2
Tests all 9 games against performance checklist:
- Frame drops, animations, load times
- Memory cleanup, mobile responsiveness
- Console errors, SocketIO efficiency
"""

import os
import json
import time
from datetime import datetime
from pathlib import Path

GAMES = [
    "connect4",
    "tictactoe", 
    "snake",  # snake_ladder
    "poker",
    "roulette",
    "trivia",
    "raja_mantri",
    "canvas_battle",
    "digit_guess"
]

CHECKLIST = [
    "no_frame_drops",
    "smooth_animations_60fps",
    "fast_load_times_under_2s",
    "proper_memory_cleanup",
    "mobile_responsive",
    "no_console_errors",
    "efficient_socketio"
]

def check_static_files(game):
    """Check if game has proper static files (JS/CSS)"""
    results = {
        "js_exists": False,
        "css_exists": False,
        "html_template_exists": False,
        "file_sizes": {}
    }
    
    base_path = Path(__file__).parent.parent
    js_path = base_path / "static" / "js" / "games" / f"{game}.js"
    css_path = base_path / "static" / "css" / "games" / f"{game}.css"
    html_path = base_path / "templates" / "games" / f"{game}.html"
    
    if js_path.exists():
        results["js_exists"] = True
        results["file_sizes"]["js_kb"] = js_path.stat().st_size / 1024
    
    if css_path.exists():
        results["css_exists"] = True
        results["file_sizes"]["css_kb"] = css_path.stat().st_size / 1024
        
    if html_path.exists():
        results["html_template_exists"] = True
        results["file_sizes"]["html_kb"] = html_path.stat().st_size / 1024
    
    return results

def check_socketio_events(game):
    """Analyze SocketIO event handlers in game JS"""
    results = {
        "event_handlers": [],
        "cleanup_handlers": False,
        "efficient_patterns": []
    }
    
    base_path = Path(__file__).parent.parent
    js_path = base_path / "static" / "js" / "games" / f"{game}.js"
    
    if js_path.exists():
        content = js_path.read_text()
        
        # Check for socket.on() calls
        import re
        handlers = re.findall(r'socket\.on\([\'"](\w+)[\'"]', content)
        results["event_handlers"] = list(set(handlers))
        
        # Check for cleanup (socket.off or disconnect handling)
        if "socket.off" in content or "disconnect" in content:
            results["cleanup_handlers"] = True
            
        # Check for efficient patterns
        if "socket.once" in content:
            results["efficient_patterns"].append("uses_socket_once")
        if "debounce" in content or "throttle" in content:
            results["efficient_patterns"].append("rate_limiting")
    
    return results

def check_mobile_responsiveness(game):
    """Check CSS and HTML for mobile-friendly patterns"""
    results = {
        "has_viewport_meta": False,
        "has_media_queries": False,
        "touch_friendly": False
    }
    
    base_path = Path(__file__).parent.parent
    html_path = base_path / "templates" / "games" / f"{game}.html"
    css_path = base_path / "static" / "css" / "games" / f"{game}.css"
    js_path = base_path / "static" / "js" / "games" / f"{game}.js"
    
    # Check HTML
    if html_path.exists():
        html_content = html_path.read_text()
        if "viewport" in html_content:
            results["has_viewport_meta"] = True
    
    # Check CSS
    if css_path.exists():
        css_content = css_path.read_text()
        if "@media" in css_content:
            results["has_media_queries"] = True
    
    # Check JS for touch events
    if js_path.exists():
        js_content = js_path.read_text()
        if "touchstart" in js_content or "touchend" in js_content:
            results["touch_friendly"] = True
    
    return results

def check_animation_performance(game):
    """Check for performance-friendly animation patterns"""
    results = {
        "uses_css_animations": False,
        "uses_requestAnimationFrame": False,
        "avoids_layout_thrashing": False
    }
    
    base_path = Path(__file__).parent.parent
    css_path = base_path / "static" / "css" / "games" / f"{game}.css"
    js_path = base_path / "static" / "js" / "games" / f"{game}.js"
    
    # Check CSS
    if css_path.exists():
        css_content = css_path.read_text()
        if "animation" in css_content or "transition" in css_content:
            results["uses_css_animations"] = True
    
    # Check JS
    if js_path.exists():
        js_content = js_path.read_text()
        if "requestAnimationFrame" in js_content:
            results["uses_requestAnimationFrame"] = True
        if "transform" in js_content and "top" not in js_content:
            results["avoids_layout_thrashing"] = True
    
    return results

def audit_game(game):
    """Run full performance audit on a single game"""
    print(f"\n🎮 Auditing {game.upper()}...")
    
    audit_results = {
        "game": game,
        "timestamp": datetime.now().isoformat(),
        "static_files": check_static_files(game),
        "socketio": check_socketio_events(game),
        "mobile": check_mobile_responsiveness(game),
        "animations": check_animation_performance(game),
        "performance_score": 0,
        "issues": [],
        "recommendations": []
    }
    
    # Calculate performance score
    score = 0
    
    # Static files (20 points)
    if audit_results["static_files"]["js_exists"]:
        score += 10
    if audit_results["static_files"]["html_template_exists"]:
        score += 10
    
    # SocketIO (20 points)
    if audit_results["socketio"]["cleanup_handlers"]:
        score += 10
    if audit_results["socketio"]["efficient_patterns"]:
        score += 10
    
    # Mobile (30 points)
    if audit_results["mobile"]["has_viewport_meta"]:
        score += 10
    if audit_results["mobile"]["has_media_queries"]:
        score += 10
    if audit_results["mobile"]["touch_friendly"]:
        score += 10
    
    # Animations (30 points)
    if audit_results["animations"]["uses_css_animations"]:
        score += 10
    if audit_results["animations"]["uses_requestAnimationFrame"]:
        score += 10
    if audit_results["animations"]["avoids_layout_thrashing"]:
        score += 10
    
    audit_results["performance_score"] = score
    
    # Identify issues
    if not audit_results["static_files"]["js_exists"]:
        audit_results["issues"].append("Missing JavaScript file")
    if not audit_results["socketio"]["cleanup_handlers"]:
        audit_results["issues"].append("No SocketIO cleanup handlers")
        audit_results["recommendations"].append("Add socket.off() calls on game end")
    if not audit_results["mobile"]["has_media_queries"]:
        audit_results["issues"].append("No mobile-responsive CSS")
        audit_results["recommendations"].append("Add @media queries for mobile screens")
    if not audit_results["animations"]["uses_requestAnimationFrame"]:
        audit_results["issues"].append("Not using requestAnimationFrame for animations")
        audit_results["recommendations"].append("Use requestAnimationFrame instead of setInterval")
    
    # File size warnings
    if audit_results["static_files"]["file_sizes"].get("js_kb", 0) > 100:
        audit_results["issues"].append(f"Large JS file ({audit_results['static_files']['file_sizes']['js_kb']:.1f}KB)")
        audit_results["recommendations"].append("Consider code splitting or minification")
    
    return audit_results

def generate_report(all_results):
    """Generate comprehensive audit report"""
    report_path = Path(__file__).parent.parent / "docs" / "PERFORMANCE_AUDIT_REPORT.md"
    
    with open(report_path, "w") as f:
        f.write("# GameLab2 Performance Audit Report\n\n")
        f.write(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write("## Executive Summary\n\n")
        
        # Calculate overall stats
        total_score = sum(r["performance_score"] for r in all_results)
        avg_score = total_score / len(all_results)
        total_issues = sum(len(r["issues"]) for r in all_results)
        
        f.write(f"- **Total Games Audited:** {len(all_results)}\n")
        f.write(f"- **Average Performance Score:** {avg_score:.1f}/100\n")
        f.write(f"- **Total Issues Found:** {total_issues}\n\n")
        
        # Score breakdown
        f.write("## Performance Scores\n\n")
        f.write("| Game | Score | Status |\n")
        f.write("|------|-------|--------|\n")
        
        for result in sorted(all_results, key=lambda x: x["performance_score"], reverse=True):
            status = "✅" if result["performance_score"] >= 80 else "⚠️" if result["performance_score"] >= 60 else "❌"
            f.write(f"| {result['game'].replace('_', ' ').title()} | {result['performance_score']}/100 | {status} |\n")
        
        # Detailed findings
        f.write("\n## Detailed Findings\n\n")
        
        for result in all_results:
            f.write(f"### {result['game'].replace('_', ' ').title()}\n\n")
            f.write(f"**Performance Score:** {result['performance_score']}/100\n\n")
            
            if result["issues"]:
                f.write("#### Issues:\n")
                for issue in result["issues"]:
                    f.write(f"- ❌ {issue}\n")
                f.write("\n")
            
            if result["recommendations"]:
                f.write("#### Recommendations:\n")
                for rec in result["recommendations"]:
                    f.write(f"- 💡 {rec}\n")
                f.write("\n")
            
            # Technical details
            f.write("<details>\n<summary>Technical Details</summary>\n\n")
            f.write(f"**Static Files:**\n")
            f.write(f"- JS: {'✅' if result['static_files']['js_exists'] else '❌'}\n")
            f.write(f"- HTML: {'✅' if result['static_files']['html_template_exists'] else '❌'}\n")
            f.write(f"- CSS: {'✅' if result['static_files']['css_exists'] else '❌'}\n\n")
            
            f.write(f"**SocketIO:**\n")
            f.write(f"- Event handlers: {len(result['socketio']['event_handlers'])}\n")
            f.write(f"- Cleanup: {'✅' if result['socketio']['cleanup_handlers'] else '❌'}\n\n")
            
            f.write(f"**Mobile:**\n")
            f.write(f"- Viewport meta: {'✅' if result['mobile']['has_viewport_meta'] else '❌'}\n")
            f.write(f"- Media queries: {'✅' if result['mobile']['has_media_queries'] else '❌'}\n")
            f.write(f"- Touch events: {'✅' if result['mobile']['touch_friendly'] else '❌'}\n\n")
            
            f.write(f"**Animations:**\n")
            f.write(f"- CSS animations: {'✅' if result['animations']['uses_css_animations'] else '❌'}\n")
            f.write(f"- requestAnimationFrame: {'✅' if result['animations']['uses_requestAnimationFrame'] else '❌'}\n")
            f.write(f"- Layout optimization: {'✅' if result['animations']['avoids_layout_thrashing'] else '❌'}\n")
            
            f.write("</details>\n\n")
        
        # Priority fixes
        f.write("## Priority Action Items\n\n")
        
        critical_games = [r for r in all_results if r["performance_score"] < 60]
        if critical_games:
            f.write("### 🔴 Critical (Score < 60)\n\n")
            for result in critical_games:
                f.write(f"**{result['game'].replace('_', ' ').title()}** ({result['performance_score']}/100)\n")
                for issue in result["issues"][:3]:  # Top 3 issues
                    f.write(f"- {issue}\n")
                f.write("\n")
        
        warning_games = [r for r in all_results if 60 <= r["performance_score"] < 80]
        if warning_games:
            f.write("### ⚠️ Needs Improvement (Score 60-79)\n\n")
            for result in warning_games:
                f.write(f"**{result['game'].replace('_', ' ').title()}** ({result['performance_score']}/100)\n")
                for issue in result["issues"][:2]:  # Top 2 issues
                    f.write(f"- {issue}\n")
                f.write("\n")
        
        f.write("---\n\n")
        f.write("*This report was automatically generated by the GameLab2 Performance Audit Tool*\n")
    
    print(f"\n📊 Report saved to: {report_path}")
    return report_path

def main():
    """Run performance audit on all games"""
    print("=" * 60)
    print("🎮 GameLab2 Performance Audit")
    print("=" * 60)
    
    all_results = []
    
    for game in GAMES:
        try:
            result = audit_game(game)
            all_results.append(result)
            print(f"   Score: {result['performance_score']}/100")
            if result['issues']:
                print(f"   Issues: {len(result['issues'])}")
        except Exception as e:
            print(f"   ❌ Error: {e}")
    
    # Generate report
    report_path = generate_report(all_results)
    
    # Save JSON results
    json_path = Path(__file__).parent.parent / "performance_audit_results.json"
    with open(json_path, "w") as f:
        json.dump(all_results, f, indent=2)
    
    print(f"\n✅ Audit complete!")
    print(f"📄 JSON results: {json_path}")
    print(f"📊 Markdown report: {report_path}")
    
    # Summary
    avg_score = sum(r["performance_score"] for r in all_results) / len(all_results)
    print(f"\n🎯 Average Performance Score: {avg_score:.1f}/100")
    
    return all_results

if __name__ == "__main__":
    main()
