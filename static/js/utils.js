/**
 * Shared Utilities for GameLab2
 * Common functions used across multiple games
 */

// =====================================================
// USER MANAGEMENT
// =====================================================

/**
 * Get current user name from session, localStorage, or prompt
 * @param {string} fallbackPrefix - Prefix for random fallback name
 * @returns {string} User name
 */
function getUserName(fallbackPrefix = 'Player') {
    // Method 1: Try session data from body attribute
    const bodyElement = document.querySelector('body[data-user]');
    if (bodyElement && bodyElement.dataset.user) {
        try {
            const user = JSON.parse(bodyElement.dataset.user);
            const name = user.first_name || user.name || user.email?.split('@')[0];
            if (name) {
                return name;
            }
        } catch (e) {
            console.error('Error parsing user data:', e);
        }
    }
    
    // Method 2: Check localStorage
    let name = localStorage.getItem('playerName');
    if (name) {
        return name;
    }
    
    // Method 3: Check window.user (set by some games)
    if (window.user) {
        const userName = window.user.name || 
                        window.user.first_name || 
                        window.user.username || 
                        window.user.email?.split('@')[0];
        if (userName) {
            return userName;
        }
    }
    
    // Method 4: Prompt user
    name = prompt('Enter your name:');
    if (name && name.trim()) {
        name = name.trim();
        safeLocalStorageSet('playerName', name);
        return name;
    }
    
    // Fallback: Generate random name
    return `${fallbackPrefix}_${Math.floor(Math.random() * 10000)}`;
}

// =====================================================
// CLIPBOARD UTILITIES
// =====================================================

/**
 * Copy text to clipboard with fallback for older browsers
 * @param {string} text - Text to copy
 * @param {Function} onSuccess - Success callback
 * @param {Function} onError - Error callback
 */
function copyToClipboard(text, onSuccess, onError) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text)
            .then(() => {
                if (onSuccess) onSuccess();
            })
            .catch((err) => {
                console.error('Clipboard write failed:', err);
                fallbackCopyToClipboard(text, onSuccess, onError);
            });
    } else {
        fallbackCopyToClipboard(text, onSuccess, onError);
    }
}

/**
 * Fallback copy method for older browsers
 * @private
 */
function fallbackCopyToClipboard(text, onSuccess, onError) {
    const textArea = document.createElement('textarea');
    textArea.value = text;
    textArea.style.position = 'fixed';
    textArea.style.left = '-999999px';
    textArea.style.top = '-999999px';
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();
    
    try {
        const successful = document.execCommand('copy');
        if (successful && onSuccess) {
            onSuccess();
        } else if (!successful && onError) {
            onError();
        }
    } catch (err) {
        console.error('Fallback copy failed:', err);
        if (onError) onError();
        else alert('Could not copy. Room code: ' + text);
    }
    
    document.body.removeChild(textArea);
}

// =====================================================
// UI UTILITIES
// =====================================================

/**
 * Show temporary message/toast
 * @param {string} message - Message to display
 * @param {string} type - Message type: 'info', 'success', 'warning', 'error'
 * @param {number} duration - Duration in ms (default: 3000)
 */
function showMessage(message, type = 'info', duration = 3000) {
    // Create toast if it doesn't exist
    let toast = document.getElementById('game-toast');
    if (!toast) {
        toast = document.createElement('div');
        toast.id = 'game-toast';
        toast.className = 'game-toast';
        document.body.appendChild(toast);
    }
    
    toast.textContent = message;
    toast.className = `game-toast show toast-${type}`;
    
    setTimeout(() => {
        toast.classList.remove('show');
    }, duration);
}

/**
 * Show loading state on button
 * @param {HTMLElement} button - Button element
 * @param {boolean} loading - Loading state
 * @param {string} loadingText - Text to show while loading
 */
function setButtonLoading(button, loading, loadingText = 'Loading...') {
    if (!button) return;
    
    if (loading) {
        button.dataset.originalText = button.textContent;
        button.textContent = loadingText;
        button.disabled = true;
        button.classList.add('loading');
    } else {
        button.textContent = button.dataset.originalText || button.textContent;
        button.disabled = false;
        button.classList.remove('loading');
    }
}

// =====================================================
// STORAGE UTILITIES (with error handling)
// =====================================================

/**
 * Safely set localStorage item
 * @param {string} key
 * @param {string} value
 * @returns {boolean} Success status
 */
function safeLocalStorageSet(key, value) {
    try {
        localStorage.setItem(key, value);
        return true;
    } catch (e) {
        console.warn('localStorage.setItem failed:', e);
        return false;
    }
}

/**
 * Safely get localStorage item
 * @param {string} key
 * @param {string} defaultValue
 * @returns {string|null}
 */
function safeLocalStorageGet(key, defaultValue = null) {
    try {
        return localStorage.getItem(key) || defaultValue;
    } catch (e) {
        console.warn('localStorage.getItem failed:', e);
        return defaultValue;
    }
}

/**
 * Safely remove localStorage item
 * @param {string} key
 */
function safeLocalStorageRemove(key) {
    try {
        localStorage.removeItem(key);
    } catch (e) {
        console.warn('localStorage.removeItem failed:', e);
    }
}

// =====================================================
// PERFORMANCE UTILITIES
// =====================================================

/**
 * Debounce function to limit execution rate
 * @param {Function} func - Function to debounce
 * @param {number} wait - Wait time in ms
 * @returns {Function} Debounced function
 */
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

/**
 * Throttle function to limit execution frequency
 * @param {Function} func - Function to throttle
 * @param {number} limit - Minimum time between calls in ms
 * @returns {Function} Throttled function
 */
function throttle(func, limit) {
    let inThrottle;
    return function(...args) {
        if (!inThrottle) {
            func.apply(this, args);
            inThrottle = true;
            setTimeout(() => inThrottle = false, limit);
        }
    };
}

// =====================================================
// CLEANUP UTILITIES
// =====================================================

/**
 * Enhanced Cleanup Manager for intervals, timeouts, event listeners, and more
 * Prevents memory leaks by tracking and cleaning up all resources
 */
class CleanupManager {
    constructor() {
        this.intervals = [];
        this.timeouts = [];
        this.eventListeners = [];
        this.socketListeners = [];
        this.canvasContexts = [];
        this.animationFrames = [];
        this.domObservers = [];
    }
    
    /**
     * Register an interval for cleanup
     * @param {number} interval - Interval ID
     * @returns {number} The interval ID
     */
    addInterval(interval) {
        this.intervals.push(interval);
        return interval;
    }
    
    /**
     * Register a timeout for cleanup
     * @param {number} timeout - Timeout ID
     * @returns {number} The timeout ID
     */
    addTimeout(timeout) {
        this.timeouts.push(timeout);
        return timeout;
    }
    
    /**
     * Register an event listener for cleanup
     * @param {HTMLElement} element - DOM element
     * @param {string} event - Event name
     * @param {Function} handler - Event handler
     * @param {object} options - Event options
     */
    addEventListener(element, event, handler, options) {
        if (!element) {
            console.warn('CleanupManager: Attempted to add listener to null element');
            return;
        }
        element.addEventListener(event, handler, options);
        this.eventListeners.push({ element, event, handler, options });
    }
    
    /**
     * Register multiple event listeners at once
     * @param {Array} listeners - Array of {element, event, handler, options}
     */
    addEventListeners(listeners) {
        listeners.forEach(({ element, event, handler, options }) => {
            this.addEventListener(element, event, handler, options);
        });
    }
    
    /**
     * Register a socket event listener for cleanup
     * @param {object} socket - Socket.IO instance
     * @param {string} event - Event name
     * @param {Function} handler - Event handler
     */
    addSocketListener(socket, event, handler) {
        socket.on(event, handler);
        this.socketListeners.push({ socket, event, handler });
    }
    
    /**
     * Register a canvas context for cleanup
     * @param {HTMLCanvasElement} canvas - Canvas element
     */
    addCanvas(canvas) {
        if (canvas && canvas.getContext) {
            this.canvasContexts.push(canvas);
        }
    }
    
    /**
     * Register an animation frame for cleanup
     * @param {number} frameId - Animation frame ID
     */
    addAnimationFrame(frameId) {
        this.animationFrames.push(frameId);
    }
    
    /**
     * Register a DOM observer for cleanup
     * @param {MutationObserver|IntersectionObserver|ResizeObserver} observer
     */
    addObserver(observer) {
        this.domObservers.push(observer);
    }
    
    /**
     * Clear a specific interval and remove from tracking
     * @param {number} interval - Interval ID
     */
    clearInterval(interval) {
        clearInterval(interval);
        this.intervals = this.intervals.filter(i => i !== interval);
    }
    
    /**
     * Clear a specific timeout and remove from tracking
     * @param {number} timeout - Timeout ID
     */
    clearTimeout(timeout) {
        clearTimeout(timeout);
        this.timeouts = this.timeouts.filter(t => t !== timeout);
    }
    
    /**
     * Remove a specific event listener and remove from tracking
     * @param {HTMLElement} element
     * @param {string} event
     * @param {Function} handler
     */
    removeEventListener(element, event, handler) {
        element.removeEventListener(event, handler);
        this.eventListeners = this.eventListeners.filter(
            l => !(l.element === element && l.event === event && l.handler === handler)
        );
    }
    
    /**
     * Alias for cleanup(): several game scripts call destroy(), which used to
     * throw and abort whatever followed it (e.g. Canvas Battle's reload).
     */
    destroy() {
        this.cleanup();
    }

    /**
     * Clean up all registered resources
     */
    cleanup() {
        console.log('🧹 CleanupManager: Starting cleanup...', {
            intervals: this.intervals.length,
            timeouts: this.timeouts.length,
            eventListeners: this.eventListeners.length,
            socketListeners: this.socketListeners.length,
            canvases: this.canvasContexts.length,
            animationFrames: this.animationFrames.length,
            observers: this.domObservers.length
        });
        
        // Clear intervals
        this.intervals.forEach(interval => {
            try {
                clearInterval(interval);
            } catch (e) {
                console.warn('Failed to clear interval:', e);
            }
        });
        this.intervals = [];
        
        // Clear timeouts
        this.timeouts.forEach(timeout => {
            try {
                clearTimeout(timeout);
            } catch (e) {
                console.warn('Failed to clear timeout:', e);
            }
        });
        this.timeouts = [];
        
        // Remove event listeners
        this.eventListeners.forEach(({ element, event, handler, options }) => {
            try {
                if (element && element.removeEventListener) {
                    element.removeEventListener(event, handler, options);
                }
            } catch (e) {
                console.warn('Failed to remove event listener:', e);
            }
        });
        this.eventListeners = [];
        
        // Remove socket listeners
        this.socketListeners.forEach(({ socket, event, handler }) => {
            try {
                if (socket && socket.off) {
                    socket.off(event, handler);
                }
            } catch (e) {
                console.warn('Failed to remove socket listener:', e);
            }
        });
        this.socketListeners = [];
        
        // Clear canvas contexts
        this.canvasContexts.forEach(canvas => {
            try {
                const ctx = canvas.getContext('2d');
                if (ctx) {
                    ctx.clearRect(0, 0, canvas.width, canvas.height);
                }
            } catch (e) {
                console.warn('Failed to clear canvas:', e);
            }
        });
        this.canvasContexts = [];
        
        // Cancel animation frames
        this.animationFrames.forEach(frameId => {
            try {
                cancelAnimationFrame(frameId);
            } catch (e) {
                console.warn('Failed to cancel animation frame:', e);
            }
        });
        this.animationFrames = [];
        
        // Disconnect observers
        this.domObservers.forEach(observer => {
            try {
                observer.disconnect();
            } catch (e) {
                console.warn('Failed to disconnect observer:', e);
            }
        });
        this.domObservers = [];
        
        console.log('✅ CleanupManager: Cleanup complete');
    }
    
    /**
     * Get current resource counts (for debugging)
     * @returns {object} Resource counts
     */
    getStats() {
        return {
            intervals: this.intervals.length,
            timeouts: this.timeouts.length,
            eventListeners: this.eventListeners.length,
            socketListeners: this.socketListeners.length,
            canvases: this.canvasContexts.length,
            animationFrames: this.animationFrames.length,
            observers: this.domObservers.length
        };
    }
}

// =====================================================
// SOCKET UTILITIES
// =====================================================

/**
 * Safe socket event wrapper with error handling
 * @param {object} socket - Socket.IO instance
 * @param {string} event - Event name
 * @param {Function} handler - Event handler
 */
function safeSocketOn(socket, event, handler) {
    socket.on(event, (data) => {
        try {
            handler(data);
        } catch (error) {
            console.error(`Error in socket event '${event}':`, error);
            showMessage('An error occurred. Please try again.', 'error');
        }
    });
}

/**
 * Emit socket event with loading state
 * @param {object} socket - Socket.IO instance
 * @param {string} event - Event name
 * @param {object} data - Data to send
 * @param {HTMLElement} button - Button to show loading state (optional)
 */
function emitWithLoading(socket, event, data, button = null) {
    if (button) {
        setButtonLoading(button, true);
    }
    
    socket.emit(event, data);
    
    // Auto-restore button after timeout (in case server doesn't respond)
    if (button) {
        setTimeout(() => {
            setButtonLoading(button, false);
        }, 5000);
    }
}

// =====================================================
// DOM UTILITIES
// =====================================================

/**
 * Efficiently update DOM using DocumentFragment
 * @param {HTMLElement} container - Container element
 * @param {Array} items - Array of items to render
 * @param {Function} renderItem - Function that returns HTML string for each item
 */
function efficientDOMUpdate(container, items, renderItem) {
    const fragment = document.createDocumentFragment();
    const tempDiv = document.createElement('div');
    
    items.forEach(item => {
        tempDiv.innerHTML = renderItem(item);
        while (tempDiv.firstChild) {
            fragment.appendChild(tempDiv.firstChild);
        }
    });
    
    container.innerHTML = '';
    container.appendChild(fragment);
}

// =====================================================
// VALIDATION UTILITIES
// =====================================================

/**
 * Validate room code format
 * @param {string} code - Room code to validate
 * @returns {boolean}
 */
function isValidRoomCode(code) {
    return typeof code === 'string' && 
           code.length === 6 && 
           /^[A-Z0-9]{6}$/.test(code);
}

/**
 * Validate player name
 * @param {string} name - Player name to validate
 * @returns {boolean}
 */
function isValidPlayerName(name) {
    return typeof name === 'string' && 
           name.trim().length >= 2 && 
           name.trim().length <= 20;
}

// =====================================================
// INITIALIZATION
// =====================================================

// Log when utilities are loaded
if (typeof console !== 'undefined') {
    console.log('✅ GameLab2 Utilities loaded');
}

// Export for module systems (if available)
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        getUserName,
        copyToClipboard,
        showMessage,
        setButtonLoading,
        safeLocalStorageSet,
        safeLocalStorageGet,
        safeLocalStorageRemove,
        debounce,
        throttle,
        CleanupManager,
        safeSocketOn,
        emitWithLoading,
        efficientDOMUpdate,
        isValidRoomCode,
        isValidPlayerName
    };
}
