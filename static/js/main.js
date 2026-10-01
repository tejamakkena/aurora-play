'use strict';

/* ─── roundRect polyfill (Chrome < 99, Firefox < 112) ─────── */
if (!CanvasRenderingContext2D.prototype.roundRect) {
    CanvasRenderingContext2D.prototype.roundRect = function (x, y, w, h, r) {
        r = Math.min(r, w / 2, h / 2);
        this.moveTo(x + r, y);
        this.lineTo(x + w - r, y);
        this.quadraticCurveTo(x + w, y, x + w, y + r);
        this.lineTo(x + w, y + h - r);
        this.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
        this.lineTo(x + r, y + h);
        this.quadraticCurveTo(x, y + h, x, y + h - r);
        this.lineTo(x, y + r);
        this.quadraticCurveTo(x, y, x + r, y);
        this.closePath();
    };
}

/* ─── HERO CANVAS ──────────────────────────────────────────── */
class HeroCanvas {
    constructor(canvas) {
        this.canvas = canvas;
        this.ctx = canvas.getContext('2d');
        this.particles = Array.from({ length: 50 }, () => ({
            x: Math.random(),
            y: Math.random(),
            r: Math.random() * 1.8 + 0.4,
            vx: (Math.random() - 0.5) * 0.00025,
            vy: (Math.random() - 0.5) * 0.00025,
            o: Math.random() * 0.5 + 0.15,
        }));
        this._bound = this._resize.bind(this);
        window.addEventListener('resize', this._bound);
        this._resize();
        this._raf = requestAnimationFrame(this._loop.bind(this));
    }

    _resize() {
        const p = this.canvas.parentElement;
        this.canvas.width  = p.offsetWidth;
        this.canvas.height = p.offsetHeight;
    }

    _loop(ts) {
        this._draw(ts / 1000);
        this._raf = requestAnimationFrame(this._loop.bind(this));
    }

    _draw(t) {
        const { ctx, canvas: { width: W, height: H } } = this;
        ctx.clearRect(0, 0, W, H);

        [
            { px: 0.2 + Math.sin(t * 0.3) * 0.1,       py: 0.45, r: 0.55, c: 'rgba(0,245,255,0.07)' },
            { px: 0.78 + Math.sin(t * 0.22 + 1) * 0.09, py: 0.55, r: 0.42, c: 'rgba(191,95,255,0.07)' },
            { px: 0.5 + Math.sin(t * 0.18 + 2) * 0.14,  py: 0.7,  r: 0.38, c: 'rgba(14,165,233,0.05)' },
        ].forEach(b => {
            const g = ctx.createRadialGradient(b.px * W, b.py * H, 0, b.px * W, b.py * H, b.r * W);
            g.addColorStop(0, b.c);
            g.addColorStop(1, 'transparent');
            ctx.fillStyle = g;
            ctx.fillRect(0, 0, W, H);
        });

        this.particles.forEach(p => {
            p.x = (p.x + p.vx + 1) % 1;
            p.y = (p.y + p.vy + 1) % 1;
            const pulse = (Math.sin(t * 1.4 + p.x * 12) + 1) * 0.3 + 0.4;
            ctx.fillStyle = `rgba(0,245,255,${p.o * pulse})`;
            ctx.beginPath();
            ctx.arc(p.x * W, p.y * H, p.r, 0, Math.PI * 2);
            ctx.fill();
        });

        ctx.fillStyle = 'rgba(0,0,0,0.025)';
        for (let y = 0; y < H; y += 3) ctx.fillRect(0, y, W, 1);
    }

    destroy() {
        cancelAnimationFrame(this._raf);
        window.removeEventListener('resize', this._bound);
    }
}

/* ─── PREVIEW ANIMATIONS ───────────────────────────────────── */
const PREVIEWS = {

    pong(ctx, w, h, t) {
        ctx.fillStyle = '#04000f';
        ctx.fillRect(0, 0, w, h);
        ctx.setLineDash([5, 8]);
        ctx.strokeStyle = 'rgba(255,255,255,0.1)'; ctx.lineWidth = 1;
        ctx.beginPath(); ctx.moveTo(w / 2, 0); ctx.lineTo(w / 2, h); ctx.stroke();
        ctx.setLineDash([]);
        const bx = w / 2 + Math.sin(t * 1.8) * w * 0.38;
        const by = h / 2 + Math.sin(t * 2.4) * h * 0.35;
        const ph = 30, pw = 7;
        ctx.fillStyle = '#00f5ff'; ctx.shadowColor = '#00f5ff'; ctx.shadowBlur = 10;
        ctx.beginPath(); ctx.roundRect(8, by - ph / 2, pw, ph, 3); ctx.fill();
        ctx.fillStyle = '#bf5fff'; ctx.shadowColor = '#bf5fff';
        ctx.beginPath(); ctx.roundRect(w - 15, by - ph / 2, pw, ph, 3); ctx.fill();
        ctx.fillStyle = '#fff'; ctx.shadowColor = '#00f5ff'; ctx.shadowBlur = 16;
        ctx.beginPath(); ctx.arc(bx, by, 5, 0, Math.PI * 2); ctx.fill();
        ctx.shadowBlur = 0;
        ctx.fillStyle = 'rgba(255,255,255,0.35)';
        ctx.font = 'bold 20px Orbitron, monospace'; ctx.textAlign = 'center';
        ctx.fillText('3', w / 2 - 28, 32); ctx.fillText('2', w / 2 + 28, 32);
    },

    stickfight(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        ctx.fillStyle = 'rgba(191,95,255,0.2)'; ctx.fillRect(0, h - 22, w, 2);
        function drawStick(x, y, col, phase) {
            ctx.strokeStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 8;
            ctx.lineWidth = 2.5; ctx.lineCap = 'round';
            const sw = Math.sin(t * 3.5 + phase) * 0.45;
            ctx.beginPath(); ctx.arc(x, y - 32, 9, 0, Math.PI * 2); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(x, y - 23); ctx.lineTo(x, y - 2); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(x, y - 17);
            ctx.lineTo(x + Math.cos(sw + 0.4) * 20, y - 12 + Math.sin(sw) * 10); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(x, y - 17);
            ctx.lineTo(x - Math.cos(sw - 0.3) * 18, y - 14 + Math.sin(-sw) * 8); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(x, y - 2); ctx.lineTo(x + Math.sin(sw) * 14, y + 18); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(x, y - 2); ctx.lineTo(x - Math.sin(sw - 0.6) * 12, y + 18); ctx.stroke();
            ctx.shadowBlur = 0;
        }
        drawStick(w * 0.28, h - 22, '#00f5ff', 0);
        drawStick(w * 0.72, h - 22, '#ff00cc', Math.PI);
        ctx.fillStyle = 'rgba(255,255,255,0.22)';
        ctx.font = 'bold 13px Orbitron, monospace'; ctx.textAlign = 'center';
        ctx.fillText('VS', w / 2, h - 50);
    },

    roadfighter(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        const rl = w * 0.2, rr = w * 0.8;
        ctx.fillStyle = '#111827'; ctx.fillRect(rl, 0, rr - rl, h);
        ctx.strokeStyle = 'rgba(255,255,255,0.18)'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.moveTo(rl, 0); ctx.lineTo(rl, h); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(rr, 0); ctx.lineTo(rr, h); ctx.stroke();
        ctx.setLineDash([18, 18]); ctx.lineDashOffset = -(t * 100) % 36;
        ctx.strokeStyle = 'rgba(255,255,255,0.12)'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.moveTo(w / 2, 0); ctx.lineTo(w / 2, h); ctx.stroke();
        ctx.setLineDash([]); ctx.lineDashOffset = 0;
        const draw_car = (cx, y, col) => {
            ctx.fillStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 10;
            ctx.beginPath(); ctx.roundRect(cx - 14, y, 28, 36, 4); ctx.fill();
            ctx.fillStyle = 'rgba(0,0,0,0.5)';
            ctx.beginPath(); ctx.roundRect(cx - 10, y + 4, 20, 12, 2); ctx.fill();
            ctx.shadowBlur = 0;
        };
        draw_car(w / 2, h - 44, '#00f5ff');
        [{ lane: 0.35, spd: 0.9, off: 0 }, { lane: 0.65, spd: 0.65, off: 0.5 }].forEach(ob => {
            const oy = ((t * 75 * ob.spd + ob.off * h) % (h + 44)) - 44;
            draw_car(rl + (rr - rl) * ob.lane, oy, '#ff4444');
        });
    },

    canvas_battle(ctx, w, h, t) {
        ctx.fillStyle = '#1a1a2e'; ctx.fillRect(0, 0, w, h);
        ctx.fillStyle = '#f5f5f0';
        ctx.beginPath(); ctx.roundRect(18, 18, w - 36, h - 36, 8); ctx.fill();
        const strokes = [
            { x: 48,  y: 58,  col: '#e74c3c', len: 85, a: 0.18  },
            { x: 118, y: 88,  col: '#27ae60', len: 65, a: -0.28 },
            { x: 76,  y: 108, col: '#3498db', len: 72, a: 0.52  },
            { x: 158, y: 52,  col: '#f39c12', len: 52, a: -0.1  },
            { x: 196, y: 92,  col: '#9b59b6', len: 66, a: 0.42  },
        ];
        strokes.forEach((s, i) => {
            const p = Math.min(1, Math.max(0, t * 0.55 - i * 0.14));
            if (p <= 0) return;
            ctx.globalAlpha = 0.82;
            ctx.strokeStyle = s.col; ctx.lineWidth = 11 * p;
            ctx.lineCap = 'round'; ctx.shadowColor = s.col; ctx.shadowBlur = 5;
            ctx.beginPath(); ctx.moveTo(s.x, s.y);
            ctx.lineTo(s.x + Math.cos(s.a) * s.len * p, s.y + Math.sin(s.a) * s.len * p);
            ctx.stroke();
        });
        ctx.globalAlpha = 1; ctx.shadowBlur = 0;
        ctx.fillStyle = 'rgba(30,30,60,0.55)';
        ctx.font = '10px Space Grotesk, sans-serif'; ctx.textAlign = 'left';
        ctx.fillText('Artist Battle', 26, h - 26);
    },

    snake(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        const G = 10, cols = Math.floor(w / G), rows = Math.floor(h / G);
        ctx.fillStyle = 'rgba(255,255,255,0.04)';
        for (let r = 0; r < rows; r++)
            for (let c = 0; c < cols; c++) ctx.fillRect(c * G + 4, r * G + 4, 1, 1);
        const lx = w * 0.62;
        ctx.strokeStyle = 'rgba(245,158,11,0.55)'; ctx.lineWidth = 3;
        ctx.beginPath(); ctx.moveTo(lx - 8, h * 0.82); ctx.lineTo(lx - 8, h * 0.18); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(lx + 8, h * 0.82); ctx.lineTo(lx + 8, h * 0.18); ctx.stroke();
        ctx.strokeStyle = 'rgba(245,158,11,0.3)'; ctx.lineWidth = 2;
        for (let y = h * 0.18; y < h * 0.82; y += 11) {
            ctx.beginPath(); ctx.moveTo(lx - 8, y); ctx.lineTo(lx + 8, y); ctx.stroke();
        }
        const hx = w * 0.27 + Math.sin(t) * w * 0.09;
        const hy = h * 0.52 + Math.cos(t * 1.3) * h * 0.22;
        for (let i = 5; i >= 0; i--) {
            const sx = hx - Math.sin(t - i * 0.45) * i * 8;
            const sy = hy - Math.cos(t * 1.3 - i * 0.45) * i * 6;
            ctx.fillStyle = `rgba(16,185,129,${1 - i * 0.13})`;
            ctx.shadowColor = '#10b981'; ctx.shadowBlur = i === 0 ? 14 : 4;
            ctx.beginPath(); ctx.arc(sx, sy, i === 0 ? 7 : 5, 0, Math.PI * 2); ctx.fill();
        }
        ctx.shadowBlur = 0;
        const face = Math.floor(t * 0.7 % 6) + 1;
        ctx.fillStyle = 'rgba(255,255,255,0.88)';
        ctx.beginPath(); ctx.roundRect(w * 0.73, h * 0.6, 28, 28, 4); ctx.fill();
        ctx.fillStyle = '#04000f'; ctx.font = 'bold 15px monospace'; ctx.textAlign = 'center';
        ctx.fillText(face, w * 0.73 + 14, h * 0.6 + 19);
    },

    tictactoe(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        const sz = 90, sx = (w - sz) / 2, sy = (h - sz) / 2, cell = sz / 3;
        ctx.strokeStyle = 'rgba(255,255,255,0.2)'; ctx.lineWidth = 2;
        for (let i = 1; i < 3; i++) {
            ctx.beginPath(); ctx.moveTo(sx + i * cell, sy); ctx.lineTo(sx + i * cell, sy + sz); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(sx, sy + i * cell); ctx.lineTo(sx + sz, sy + i * cell); ctx.stroke();
        }
        ['X','O','X','','O','','O','','X'].forEach((sym, i) => {
            if (!sym) return;
            const rev = Math.min(1, t * 0.8 - i * 0.25);
            if (rev <= 0) return;
            const cx = sx + (i % 3) * cell + cell / 2;
            const cy = sy + Math.floor(i / 3) * cell + cell / 2;
            const r = (cell / 2 - 6) * rev;
            if (sym === 'O') {
                ctx.strokeStyle = '#00f5ff'; ctx.shadowColor = '#00f5ff'; ctx.shadowBlur = 8;
                ctx.lineWidth = 3 * rev;
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2 * rev); ctx.stroke();
            } else {
                ctx.strokeStyle = '#bf5fff'; ctx.shadowColor = '#bf5fff'; ctx.shadowBlur = 8;
                ctx.lineWidth = 3 * rev;
                const d = r * 0.7;
                ctx.beginPath(); ctx.moveTo(cx - d, cy - d); ctx.lineTo(cx + d, cy + d); ctx.stroke();
                ctx.beginPath(); ctx.moveTo(cx + d, cy - d); ctx.lineTo(cx - d, cy + d); ctx.stroke();
            }
            ctx.shadowBlur = 0;
        });
    },

    connect4(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        const cols = 7, rows = 5;
        const cw = Math.floor(w / (cols + 1)), ch = Math.floor(h / (rows + 1));
        const ox = (w - cw * cols) / 2, oy = (h - ch * rows) / 2;
        ctx.fillStyle = 'rgba(0,50,200,0.18)';
        ctx.beginPath(); ctx.roundRect(ox - 4, oy - 4, cw * cols + 8, ch * rows + 8, 8); ctx.fill();
        const board = [
            [0,0,1,0,0,0,1],[0,1,0,0,0,1,0],[1,0,0,2,1,0,1],[0,0,2,1,2,0,0],[0,2,1,2,0,0,0],
        ];
        for (let r = 0; r < rows; r++) {
            for (let c = 0; c < cols; c++) {
                const fill = board[r][c];
                const drop = Math.min(1, t * 1.2 - (r + c) * 0.07);
                if (drop <= 0) continue;
                const cx = ox + c * cw + cw / 2;
                const cy = (oy + r * ch + ch / 2) - ch * rows * (1 - drop);
                ctx.fillStyle = fill === 1 ? '#ff3333' : fill === 2 ? '#ffcc00' : 'rgba(255,255,255,0.05)';
                ctx.shadowColor = fill === 1 ? '#ff3333' : fill === 2 ? '#ffcc00' : 'transparent';
                ctx.shadowBlur = fill ? 8 : 0;
                ctx.beginPath(); ctx.arc(cx, cy, cw * 0.36, 0, Math.PI * 2); ctx.fill();
                ctx.shadowBlur = 0;
            }
        }
    },

    memory(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        const pairs = ['A', 'B', 'C', 'D'];
        const all = [...pairs, ...pairs];
        const cols = 4, cw = 56, ch = 52, gap = 10;
        const ox = (w - (cw * cols + gap * (cols - 1))) / 2;
        const oy = (h - (ch * 2 + gap)) / 2;
        const flipped = new Set([0, 4, 2, 6]);
        all.forEach((sym, i) => {
            const c = i % cols, r = Math.floor(i / cols);
            const x = ox + c * (cw + gap), y = oy + r * (ch + gap);
            const show = flipped.has(i) || Math.sin(t * 1.5 + i * 0.9) > 0.4;
            ctx.fillStyle = show ? 'rgba(0,245,255,0.1)' : 'rgba(15,0,40,0.85)';
            ctx.strokeStyle = show ? 'rgba(0,245,255,0.45)' : 'rgba(255,255,255,0.1)';
            ctx.lineWidth = 1.5;
            ctx.beginPath(); ctx.roundRect(x, y, cw, ch, 6); ctx.fill(); ctx.stroke();
            ctx.font = show ? '20px sans-serif' : '16px sans-serif';
            ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
            ctx.fillStyle = show ? '#fff' : 'rgba(191,95,255,0.4)';
            ctx.fillText(show ? sym : '?', x + cw / 2, y + ch / 2);
        });
        ctx.textBaseline = 'alphabetic';
    },

    roulette(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        const cx = w / 2, cy = h / 2, R = Math.min(w, h) * 0.38;
        const slots = 18, angle = t * 2;
        for (let i = 0; i < slots; i++) {
            const a1 = (i / slots) * Math.PI * 2 + angle;
            const a2 = ((i + 1) / slots) * Math.PI * 2 + angle;
            ctx.fillStyle = i % 2 === 0 ? '#c0392b' : '#1a1a1a';
            ctx.beginPath(); ctx.moveTo(cx, cy); ctx.arc(cx, cy, R, a1, a2); ctx.fill();
            const ma = (a1 + a2) / 2;
            ctx.fillStyle = '#fff'; ctx.font = 'bold 8px Orbitron, monospace';
            ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
            ctx.save();
            ctx.translate(cx + Math.cos(ma) * R * 0.72, cy + Math.sin(ma) * R * 0.72);
            ctx.rotate(ma + Math.PI / 2); ctx.fillText(i * 2 + 1, 0, 0);
            ctx.restore();
        }
        ctx.textBaseline = 'alphabetic';
        ctx.strokeStyle = '#f59e0b'; ctx.lineWidth = 3; ctx.shadowColor = '#f59e0b'; ctx.shadowBlur = 14;
        ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.stroke();
        ctx.shadowBlur = 0;
        ctx.fillStyle = '#1a0a00'; ctx.beginPath(); ctx.arc(cx, cy, R * 0.12, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = '#f59e0b'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(cx, cy, R * 0.12, 0, Math.PI * 2); ctx.stroke();
        ctx.fillStyle = '#fff'; ctx.shadowColor = '#fff'; ctx.shadowBlur = 10;
        const ba = t * 3.8;
        ctx.beginPath(); ctx.arc(cx + Math.cos(ba) * R * 0.88, cy + Math.sin(ba) * R * 0.88, 4, 0, Math.PI * 2); ctx.fill();
        ctx.shadowBlur = 0;
    },

    poker(ctx, w, h, t) {
        ctx.fillStyle = '#0d4a2a'; ctx.fillRect(0, 0, w, h);
        ctx.strokeStyle = 'rgba(255,255,255,0.04)'; ctx.lineWidth = 1;
        ctx.beginPath(); ctx.arc(w / 2, h + 10, h * 0.85, 0, Math.PI, true); ctx.stroke();
        const draw_card = (x, y, rank, suit, suitCol, reveal) => {
            if (reveal <= 0) return;
            ctx.globalAlpha = Math.min(1, reveal);
            const dy = (1 - reveal) * 35;
            ctx.fillStyle = '#fff'; ctx.shadowColor = 'rgba(0,0,0,0.5)'; ctx.shadowBlur = 8;
            ctx.beginPath(); ctx.roundRect(x, y - dy, 30, 44, 3); ctx.fill(); ctx.shadowBlur = 0;
            ctx.fillStyle = suitCol; ctx.font = 'bold 9px monospace'; ctx.textAlign = 'left';
            ctx.fillText(rank, x + 3, y - dy + 10);
            ctx.font = '13px serif'; ctx.textAlign = 'center';
            ctx.fillText(suit, x + 15, y - dy + 28);
            ctx.globalAlpha = 1;
        };
        [['A','♠','#111'],['K','♥','#cc0000'],['Q','♦','#cc0000']].forEach(([r,s,c],i) =>
            draw_card(w/2 - 55 + i * 38, h/2 - 22, r, s, c, Math.min(1,(t - i*0.28)*1.6)));
        [['J','♥','#cc0000'],['10','♠','#111']].forEach(([r,s,c],i) =>
            draw_card(w/2 - 38 + i * 42, h - 50, r, s, c, Math.min(1,(t - 0.85 - i*0.22)*2)));
        ['#f59e0b','#10b981','#00f5ff'].forEach((col, i) => {
            ctx.fillStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 8;
            ctx.beginPath(); ctx.arc(w*0.14 + i*20 + Math.sin(t+i)*3, h/2, 9, 0, Math.PI*2); ctx.fill();
            ctx.shadowBlur = 0;
            ctx.strokeStyle = 'rgba(255,255,255,0.25)'; ctx.lineWidth = 1;
            ctx.beginPath(); ctx.arc(w*0.14 + i*20 + Math.sin(t+i)*3, h/2, 9, 0, Math.PI*2); ctx.stroke();
        });
    },

    trivia(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        ctx.fillStyle = 'rgba(15,0,40,0.9)'; ctx.strokeStyle = 'rgba(0,245,255,0.22)'; ctx.lineWidth = 1;
        ctx.beginPath(); ctx.roundRect(14, 10, w - 28, 42, 8); ctx.fill(); ctx.stroke();
        const pulse = (Math.sin(t * 2) + 1) * 0.5;
        ctx.fillStyle = `rgba(0,245,255,${0.55 + pulse * 0.45})`;
        ctx.font = 'bold 12px Orbitron, monospace'; ctx.textAlign = 'center';
        ctx.fillText('TRIVIA TIME', w / 2, 36);
        const opts = ['A','B','C','D'];
        const cols = ['#00f5ff','#bf5fff','#f59e0b','#10b981'];
        opts.forEach((opt, i) => {
            const col = i % 2, row = Math.floor(i / 2);
            const bw = (w - 38) / 2, bh = 23;
            const bx = 14 + col * (bw + 10), by = 62 + row * (bh + 8);
            const rev = Math.min(1, t * 1.4 - i * 0.18);
            if (rev <= 0) return;
            ctx.globalAlpha = rev;
            ctx.fillStyle = cols[i] + '18'; ctx.strokeStyle = cols[i] + '60'; ctx.lineWidth = 1;
            ctx.beginPath(); ctx.roundRect(bx, by, bw, bh, 5); ctx.fill(); ctx.stroke();
            ctx.fillStyle = cols[i]; ctx.font = 'bold 9px Orbitron, monospace'; ctx.textAlign = 'left';
            ctx.fillText(opt, bx + 7, by + 15);
        });
        ctx.globalAlpha = 1;
        const pct = 1 - ((t * 0.2) % 1);
        ctx.fillStyle = 'rgba(255,255,255,0.08)';
        ctx.beginPath(); ctx.roundRect(14, h - 18, w - 28, 7, 3); ctx.fill();
        ctx.fillStyle = pct > 0.3 ? '#00f5ff' : '#f43f5e';
        ctx.shadowColor = pct > 0.3 ? '#00f5ff' : '#f43f5e'; ctx.shadowBlur = 5;
        ctx.beginPath(); ctx.roundRect(14, h - 18, (w - 28) * pct, 7, 3); ctx.fill();
        ctx.shadowBlur = 0;
    },

    hangman(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        ctx.strokeStyle = 'rgba(245,158,11,0.65)'; ctx.lineWidth = 3; ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(28, h - 18); ctx.lineTo(w * 0.42, h - 18); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(w * 0.25, h - 18); ctx.lineTo(w * 0.25, 18); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(w * 0.25, 18); ctx.lineTo(w * 0.57, 18); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(w * 0.57, 18); ctx.lineTo(w * 0.57, 36); ctx.stroke();
        const parts = Math.floor(t * 0.58) % 7;
        const fx = w * 0.57, fy = 36;
        ctx.strokeStyle = '#ff6b6b'; ctx.shadowColor = '#ff6b6b'; ctx.shadowBlur = 6; ctx.lineWidth = 2.5;
        if (parts >= 1) { ctx.beginPath(); ctx.arc(fx, fy + 13, 11, 0, Math.PI * 2); ctx.stroke(); }
        if (parts >= 2) { ctx.beginPath(); ctx.moveTo(fx, fy + 24); ctx.lineTo(fx, fy + 54); ctx.stroke(); }
        if (parts >= 3) { ctx.beginPath(); ctx.moveTo(fx, fy + 34); ctx.lineTo(fx - 18, fy + 48); ctx.stroke(); }
        if (parts >= 4) { ctx.beginPath(); ctx.moveTo(fx, fy + 34); ctx.lineTo(fx + 18, fy + 48); ctx.stroke(); }
        if (parts >= 5) { ctx.beginPath(); ctx.moveTo(fx, fy + 54); ctx.lineTo(fx - 15, fy + 70); ctx.stroke(); }
        if (parts >= 6) { ctx.beginPath(); ctx.moveTo(fx, fy + 54); ctx.lineTo(fx + 15, fy + 70); ctx.stroke(); }
        ctx.shadowBlur = 0;
        ctx.fillStyle = 'rgba(255,255,255,0.55)';
        ctx.font = 'bold 14px Orbitron, monospace'; ctx.textAlign = 'center';
        ctx.fillText('_ G A _ E _', w * 0.3, h - 38);
    },

    pictionary(ctx, w, h, t) {
        ctx.fillStyle = '#1a1a2e'; ctx.fillRect(0, 0, w, h);
        ctx.fillStyle = '#f5f5f0';
        ctx.beginPath(); ctx.roundRect(14, 14, w - 28, h - 46, 6); ctx.fill();
        const path = [
            {x:58,y:102},{x:58,y:58},{x:110,y:30},{x:162,y:58},
            {x:162,y:102},{x:58,y:102},{x:98,y:102},{x:98,y:78},{x:116,y:78},{x:116,y:102},
        ];
        const step = Math.floor(((t * 0.28) % 1) * path.length);
        if (step > 1) {
            ctx.strokeStyle = '#3b4bc8'; ctx.lineWidth = 3;
            ctx.lineCap = 'round'; ctx.lineJoin = 'round';
            ctx.shadowColor = '#3b4bc8'; ctx.shadowBlur = 4;
            ctx.beginPath(); ctx.moveTo(path[0].x, path[0].y);
            for (let i = 1; i < step; i++) ctx.lineTo(path[i].x, path[i].y);
            ctx.stroke(); ctx.shadowBlur = 0;
        }
        const lp = path[Math.max(0, step - 1)];
        ctx.font = '15px sans-serif'; ctx.textAlign = 'left';
        ctx.fillText('+', lp.x - 8, lp.y + 5);
        ctx.fillStyle = '#555';
        ctx.font = 'bold 10px Orbitron, monospace'; ctx.textAlign = 'center';
        ctx.fillText('_ _ _ _ _', w / 2, h - 14);
    },

    mafia(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        const vg = ctx.createRadialGradient(w/2, h/2, h*0.15, w/2, h/2, h*0.75);
        vg.addColorStop(0, 'transparent'); vg.addColorStop(1, 'rgba(0,0,0,0.65)');
        ctx.fillStyle = vg; ctx.fillRect(0, 0, w, h);
        [{x:w*0.2,col:'#ff4444'},{x:w*0.4,col:'#888'},{x:w*0.6,col:'#888'},{x:w*0.8,col:'#4488ff'}]
            .forEach((c, i) => {
                const bob = Math.sin(t * 1.2 + i * 1.5) * 2, y = h - 28 + bob;
                ctx.fillStyle = c.col; ctx.globalAlpha = 0.72;
                ctx.shadowColor = c.col; ctx.shadowBlur = i === 0 ? 12 : 4;
                ctx.beginPath(); ctx.arc(c.x, y - 38, 11, 0, Math.PI * 2); ctx.fill();
                ctx.beginPath(); ctx.roundRect(c.x - 9, y - 27, 18, 27, 3); ctx.fill();
                ctx.shadowBlur = 0;
            });
        ctx.globalAlpha = 1;
        const vp = (Math.sin(t * 3) + 1) * 0.5;
        ctx.fillStyle = `rgba(255,68,68,${0.45 + vp * 0.55})`;
        ctx.font = 'bold 11px Orbitron, monospace'; ctx.textAlign = 'center';
        ctx.fillText('VOTE!', w / 2, 26);
    },

    tambola(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        const cw = w - 38, ch = h - 38, ox = 19, oy = 19;
        ctx.fillStyle = 'rgba(245,158,11,0.07)'; ctx.strokeStyle = 'rgba(245,158,11,0.3)'; ctx.lineWidth = 1;
        ctx.beginPath(); ctx.roundRect(ox, oy, cw, ch, 8); ctx.fill(); ctx.stroke();
        const nCols = 5, nRows = 3;
        const cellW = cw / nCols, cellH = ch / nRows;
        const nums = [[4,0,24,0,42],[0,17,0,33,55],[8,0,29,0,61]];
        const marked = new Set([0,2,4,8]);
        for (let r = 0; r < nRows; r++) {
            for (let c = 0; c < nCols; c++) {
                const idx = r * nCols + c, num = nums[r][c];
                const bx = ox + c * cellW, by = oy + r * cellH;
                ctx.fillStyle = num === 0 ? 'rgba(0,0,0,0.28)' : marked.has(idx) ? 'rgba(245,158,11,0.22)' : 'rgba(255,255,255,0.04)';
                ctx.beginPath(); ctx.roundRect(bx + 2, by + 2, cellW - 4, cellH - 4, 4); ctx.fill();
                if (num > 0) {
                    ctx.fillStyle = marked.has(idx) ? '#f59e0b' : 'rgba(255,255,255,0.7)';
                    if (marked.has(idx)) { ctx.shadowColor = '#f59e0b'; ctx.shadowBlur = 7; }
                    ctx.font = 'bold 10px Orbitron, monospace';
                    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
                    ctx.fillText(num, bx + cellW / 2, by + cellH / 2);
                    ctx.shadowBlur = 0;
                }
            }
        }
        ctx.textBaseline = 'alphabetic';
        const called = Math.floor(t * 0.85) % 90 + 1;
        ctx.fillStyle = 'rgba(245,158,11,0.92)'; ctx.shadowColor = '#f59e0b'; ctx.shadowBlur = 10;
        ctx.font = 'bold 11px Orbitron, monospace'; ctx.textAlign = 'right';
        ctx.fillText('#' + called, w - 22, 14); ctx.shadowBlur = 0;
    },

    raja_mantri(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        const cards = [
            {label:'R', name:'Raja',   col:'#f59e0b'},
            {label:'M',  name:'Mantri', col:'#10b981'},
            {label:'K', name:'Kotwal', col:'#00f5ff'},
            {label:'C', name:'Chor',   col:'#f43f5e'},
        ];
        cards.forEach((card, i) => {
            const a = -0.42 + i * 0.28;
            ctx.save();
            ctx.translate(w / 2 + Math.sin(a) * 68, h / 2 + Math.cos(a) * 8);
            ctx.rotate(a * 0.28);
            const flip = Math.sin(t * 0.85 + i * 1.2) > 0 || i < 2;
            const cw = 42, ch = 58;
            ctx.fillStyle = flip ? 'rgba(255,255,255,0.95)' : card.col + '22';
            ctx.strokeStyle = card.col + '70'; ctx.lineWidth = 1;
            ctx.shadowColor = card.col; ctx.shadowBlur = flip ? 10 : 3;
            ctx.beginPath(); ctx.roundRect(-cw / 2, -ch / 2, cw, ch, 5);
            ctx.fill(); if (!flip) ctx.stroke();
            ctx.shadowBlur = 0;
            ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
            if (flip) {
                ctx.font = '18px sans-serif'; ctx.fillText(card.label, 0, -6);
                ctx.fillStyle = card.col; ctx.font = 'bold 7px sans-serif';
                ctx.fillText(card.name, 0, 17);
            } else {
                ctx.fillStyle = card.col + '88'; ctx.font = '15px sans-serif';
                ctx.fillText('?', 0, 0);
            }
            ctx.textBaseline = 'alphabetic';
            ctx.restore();
        });
    },

    digit_guess(ctx, w, h, t) {
        ctx.fillStyle = '#04000f'; ctx.fillRect(0, 0, w, h);
        ctx.fillStyle = 'rgba(0,245,255,0.07)'; ctx.strokeStyle = 'rgba(0,245,255,0.22)'; ctx.lineWidth = 1;
        ctx.beginPath(); ctx.roundRect(w/2 - 68, 14, 136, 34, 8); ctx.fill(); ctx.stroke();
        ctx.fillStyle = 'rgba(0,245,255,0.5)';
        ctx.font = 'bold 17px Orbitron, monospace'; ctx.textAlign = 'center';
        ctx.fillText('? ? ? ?', w / 2, 37);
        const guesses = [
            {digits:'1 3 5 7', bulls:1, cows:2},
            {digits:'2 4 6 8', bulls:2, cows:1},
            {digits:'1 4 5 8', bulls:3, cows:0},
        ];
        guesses.forEach((g, i) => {
            const rev = Math.min(1, t * 0.75 - i * 0.5);
            if (rev <= 0) return;
            const y = 60 + i * 25;
            ctx.globalAlpha = rev;
            ctx.fillStyle = 'rgba(255,255,255,0.04)';
            ctx.beginPath(); ctx.roundRect(18, y, w - 36, 20, 4); ctx.fill();
            ctx.fillStyle = 'rgba(255,255,255,0.7)'; ctx.font = 'bold 10px Orbitron, monospace'; ctx.textAlign = 'left';
            ctx.fillText(g.digits, 26, y + 14);
            ctx.fillStyle = '#f59e0b'; ctx.textAlign = 'right';
            ctx.fillText('B' + g.bulls + ' C' + g.cows, w - 22, y + 14);
        });
        ctx.globalAlpha = 1;
        const blink = Math.floor(t * 2) % 2 === 0;
        ctx.fillStyle = 'rgba(0,245,255,0.07)'; ctx.strokeStyle = 'rgba(0,245,255,0.4)'; ctx.lineWidth = 1;
        ctx.beginPath(); ctx.roundRect(18, h - 30, w - 36, 18, 4); ctx.fill(); ctx.stroke();
        ctx.fillStyle = blink ? 'rgba(0,245,255,0.8)' : 'transparent';
        ctx.font = '10px Orbitron, monospace'; ctx.textAlign = 'left';
        ctx.fillText('|', 26, h - 16);
    },
};

/* ─── PREVIEW ENGINE ────────────────────────────────────────── */
class PreviewEngine {
    constructor() {
        this._active = new Map();
        this._observer = new IntersectionObserver(
            this._onIntersect.bind(this),
            { threshold: 0.15 }
        );
    }

    observe(canvas) { this._observer.observe(canvas); }

    _onIntersect(entries) {
        entries.forEach(e => e.isIntersecting ? this._start(e.target) : this._stop(e.target));
    }

    _start(canvas) {
        if (this._active.has(canvas)) return;
        const name = canvas.closest('[data-preview]')?.dataset.preview;
        if (!name || !PREVIEWS[name]) return;
        const fn = PREVIEWS[name];
        const ctx = canvas.getContext('2d');
        const w = canvas.width, h = canvas.height;
        const t0 = performance.now();
        const loop = (now) => {
            if (!this._active.has(canvas)) return;
            fn(ctx, w, h, (now - t0) / 1000);
            this._active.get(canvas).raf = requestAnimationFrame(loop);
        };
        this._active.set(canvas, { raf: requestAnimationFrame(loop) });
    }

    _stop(canvas) {
        const info = this._active.get(canvas);
        if (!info) return;
        cancelAnimationFrame(info.raf);
        this._active.delete(canvas);
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
    }

    destroy() {
        this._observer.disconnect();
        this._active.forEach(info => cancelAnimationFrame(info.raf));
        this._active.clear();
    }
}

/* ─── CATEGORY FILTER ───────────────────────────────────────── */
class CategoryFilter {
    constructor() {
        this._btns  = document.querySelectorAll('.cat-btn');
        this._lanes = document.querySelectorAll('.game-lane');
        this._btns.forEach(btn => btn.addEventListener('click', () => this.filter(btn.dataset.cat)));
    }

    filter(cat) {
        this._btns.forEach(b => {
            const on = b.dataset.cat === cat;
            b.classList.toggle('active', on);
            b.setAttribute('aria-selected', on ? 'true' : 'false');
        });
        this._lanes.forEach(lane => {
            const show = cat === 'all' || lane.dataset.lane === cat;
            if (show) {
                lane.style.display = '';
                lane.style.animation = 'none';
                void lane.offsetHeight;
                lane.style.animation = '';
            } else {
                lane.style.display = 'none';
            }
        });
    }
}

/* ─── LANE NAVIGATION ───────────────────────────────────────── */
function initLaneNav() {
    document.querySelectorAll('.game-lane').forEach(lane => {
        const track = lane.querySelector('.lane-track');
        if (!track) return;
        const SCROLL = 296;
        lane.querySelector('.lane-prev')?.addEventListener('click', () =>
            track.scrollBy({ left: -SCROLL, behavior: 'smooth' }));
        lane.querySelector('.lane-next')?.addEventListener('click', () =>
            track.scrollBy({ left: SCROLL, behavior: 'smooth' }));

        let dragging = false, startX = 0, scrollLeft = 0;
        track.addEventListener('mousedown', e => {
            dragging = true; startX = e.pageX; scrollLeft = track.scrollLeft;
            track.style.cursor = 'grabbing';
        });
        track.addEventListener('mouseleave', () => { dragging = false; track.style.cursor = ''; });
        track.addEventListener('mouseup',    () => { dragging = false; track.style.cursor = ''; });
        track.addEventListener('mousemove', e => {
            if (!dragging) return;
            e.preventDefault();
            track.scrollLeft = scrollLeft - (e.pageX - startX);
        });
    });
}

/* ─── PORTAL TRANSITION ─────────────────────────────────────── */
class PortalTransition {
    constructor() {
        this._overlay = document.getElementById('portal-overlay');
    }

    bind(cards) {
        if (!this._overlay) return;
        cards.forEach(card => {
            card.addEventListener('click', e => {
                e.preventDefault();
                const rect = card.getBoundingClientRect();
                this._go(
                    rect.left + rect.width / 2,
                    rect.top  + rect.height / 2,
                    card.dataset.url || card.href
                );
            });
        });
    }

    _go(x, y, url) {
        const o = this._overlay;
        o.style.setProperty('--ox', x + 'px');
        o.style.setProperty('--oy', y + 'px');
        o.classList.add('expanding');
        setTimeout(() => { window.location.href = url; }, 520);
    }
}

/* ─── INIT ──────────────────────────────────────────────────── */
document.addEventListener('DOMContentLoaded', () => {
    const heroCanvas = document.getElementById('hero-canvas');
    if (heroCanvas) new HeroCanvas(heroCanvas);

    const canvases = document.querySelectorAll('.preview-canvas');
    if (canvases.length) {
        const engine = new PreviewEngine();
        canvases.forEach(c => engine.observe(c));
    }

    if (document.querySelector('.cat-filter-bar')) new CategoryFilter();

    initLaneNav();

    const portal = new PortalTransition();
    portal.bind(document.querySelectorAll('.lane-card'));
});
