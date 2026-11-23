(() => {
  'use strict';

  // --- Musical Scale Helpers (A Minor Pentatonic & Continuous Theremin) ---
  const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  const MIN_MIDI = 48; // C3 (130.8 Hz)
  const MAX_MIDI = 84; // C6 (1046.5 Hz)
  const PENT_MINOR_A = new Set([9, 0, 2, 4, 7]); // A, C, D, E, G
  const PENT_NOTES = [];
  for (let m = MIN_MIDI; m <= MAX_MIDI; m++) {
    if (PENT_MINOR_A.has(m % 12)) PENT_NOTES.push(m);
  }

  function midiToHz(midi) {
    return 440 * Math.pow(2, (midi - 69) / 12);
  }

  function hzToNoteName(hz) {
    const midi = Math.round(69 + 12 * Math.log2(Math.max(20, hz) / 440));
    const name = NOTE_NAMES[((midi % 12) + 12) % 12];
    const oct = Math.floor(midi / 12) - 1;
    return `${name}${oct}`;
  }

  function xToFrequency(nx, isQuantized) {
    const clamped = Math.max(0, Math.min(1, nx));
    if (!isQuantized) {
      return midiToHz(MIN_MIDI + clamped * (MAX_MIDI - MIN_MIDI));
    }
    const idx = Math.min(PENT_NOTES.length - 1, Math.floor(clamped * PENT_NOTES.length));
    return midiToHz(PENT_NOTES[idx]);
  }

  // --- Minimal Web Audio Polyphonic Additive Synth ---
  const TIMBRES = {
    sine: [[1, 1.0]],
    warm: [[1, 0.72], [2, 0.28], [3, 0.08]],
    saw: [[1, 0.48], [2, 0.26], [3, 0.15], [4, 0.08], [5, 0.05]],
    bell: [[1, 0.58], [2.756, 0.28], [5.404, 0.14]]
  };

  let audioCtx = null;
  let masterGain = null;
  const activeVoices = new Map(); // pointerId -> { oscs, voiceGain, x, y, hz, vol, trail }

  function ensureAudio() {
    if (!audioCtx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      audioCtx = new AC();
      masterGain = audioCtx.createGain();
      masterGain.gain.value = 0.28;
      masterGain.connect(audioCtx.destination);
    }
    if (audioCtx.state === 'suspended') {
      audioCtx.resume().catch(() => {});
    }
    return audioCtx;
  }

  let currentTimbre = 'warm';
  let scaleQuantized = true;
  let ferroEnabled = true;

  function startOrUpdateVoice(id, nx, ny) {
    const ctx = ensureAudio();
    const hz = xToFrequency(nx, scaleQuantized);
    const vol = Math.max(0.06, Math.min(1, 0.06 + 0.94 * Math.pow(ny, 0.78)));

    let voice = activeVoices.get(id);
    if (!voice) {
      const voiceGain = ctx ? ctx.createGain() : null;
      const partials = TIMBRES[currentTimbre] || TIMBRES.warm;
      const oscs = [];

      if (ctx && voiceGain) {
        voiceGain.gain.setValueAtTime(0.0001, ctx.currentTime);
        voiceGain.gain.exponentialRampToValueAtTime(Math.max(0.001, vol * 0.7), ctx.currentTime + 0.02);
        voiceGain.connect(masterGain);

        for (const [mult, amp] of partials) {
          const osc = ctx.createOscillator();
          const g = ctx.createGain();
          osc.type = 'sine';
          osc.frequency.setValueAtTime(Math.min(6000, hz * mult), ctx.currentTime);
          g.gain.value = amp;
          osc.connect(g);
          g.connect(voiceGain);
          osc.start();
          oscs.push({ osc, mult, g });
        }
      }

      voice = { id, oscs, voiceGain, x: nx, y: ny, hz, vol, trail: [{ x: nx, y: ny }] };
      activeVoices.set(id, voice);
    } else {
      voice.x = nx;
      voice.y = ny;
      voice.hz = hz;
      voice.vol = vol;
      voice.trail.push({ x: nx, y: ny });
      if (voice.trail.length > 22) voice.trail.shift();

      if (ctx && voice.voiceGain) {
        const t = ctx.currentTime;
        voice.voiceGain.gain.setTargetAtTime(Math.max(0.001, vol * 0.7), t, 0.02);
        for (const item of voice.oscs) {
          item.osc.frequency.setTargetAtTime(Math.min(6000, hz * item.mult), t, 0.025);
        }
      }
    }
    updateHud();
  }

  function stopVoice(id) {
    const voice = activeVoices.get(id);
    if (!voice) return;
    activeVoices.delete(id);

    if (audioCtx && voice.voiceGain) {
      const t = audioCtx.currentTime;
      voice.voiceGain.gain.cancelScheduledValues(t);
      voice.voiceGain.gain.setTargetAtTime(0.0001, t, 0.025);
      setTimeout(() => {
        for (const item of voice.oscs) {
          try { item.osc.stop(); item.osc.disconnect(); } catch (_) {}
        }
        try { voice.voiceGain.disconnect(); } catch (_) {}
      }, 140);
    }
    updateHud();
  }

  function rebuildActiveVoiceTimbres() {
    for (const [id, v] of Array.from(activeVoices.entries())) {
      const { x, y } = v;
      stopVoice(id);
      startOrUpdateVoice(id, x, y);
    }
  }

  // --- DOM Elements & Controls ---
  const padEl = document.getElementById('pad-surface');
  const padCanvas = document.getElementById('pad-canvas');
  const padCtx = padCanvas.getContext('2d');
  const ambientCanvas = document.getElementById('ambient-wave');
  const ambientCtx = ambientCanvas.getContext('2d');
  const statusText = document.getElementById('pad-status-text');
  const readoutEl = document.getElementById('pad-readout');
  const motionToggle = document.getElementById('motion-toggle');
  const themeToggle = document.getElementById('theme-toggle');
  const scaleToggle = document.getElementById('scale-toggle');
  const scaleLabel = document.getElementById('scale-label');
  const ferroToggle = document.getElementById('ferro-toggle');

  function updateHud() {
    if (activeVoices.size === 0) {
      padEl.classList.remove('is-active');
      statusText.textContent = 'TOUCH OR DRAG TO PLAY';
      readoutEl.textContent = '— · 0 Hz';
      return;
    }
    padEl.classList.add('is-active');
    const primary = Array.from(activeVoices.values())[0];
    const count = activeVoices.size;
    statusText.textContent = count > 1 ? `PLAYING ${count} VOICES` : `PLAYING · ${currentTimbre.toUpperCase()}`;
    readoutEl.textContent = `${hzToNoteName(primary.hz)} · ${Math.round(primary.hz)} Hz · ${Math.round(primary.vol * 100)}%`;
  }

  document.querySelectorAll('[data-timbre]').forEach((btn) => {
    btn.addEventListener('click', () => {
      currentTimbre = btn.dataset.timbre;
      document.querySelectorAll('[data-timbre]').forEach((b) => {
        const active = b === btn;
        b.classList.toggle('is-active', active);
        b.setAttribute('aria-pressed', String(active));
      });
      rebuildActiveVoiceTimbres();
      updateHud();
    });
  });

  scaleToggle.addEventListener('click', () => {
    scaleQuantized = !scaleQuantized;
    scaleToggle.classList.toggle('is-active', scaleQuantized);
    scaleToggle.setAttribute('aria-pressed', String(scaleQuantized));
    scaleLabel.textContent = scaleQuantized ? 'PENTATONIC' : 'THEREMIN';
  });

  ferroToggle.addEventListener('click', () => {
    ferroEnabled = !ferroEnabled;
    ferroToggle.classList.toggle('is-active', ferroEnabled);
    ferroToggle.setAttribute('aria-pressed', String(ferroEnabled));
  });

  // Theme Toggle
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)');
  let explicitTheme = null;

  function effectiveDark() {
    if (explicitTheme) return explicitTheme === 'dark';
    return prefersDark.matches;
  }

  function syncThemeButton() {
    themeToggle.textContent = effectiveDark() ? 'Light' : 'Dark';
  }

  themeToggle.addEventListener('click', () => {
    explicitTheme = effectiveDark() ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', explicitTheme);
    syncThemeButton();
  });
  prefersDark.addEventListener('change', syncThemeButton);
  syncThemeButton();

  // Motion Pause / Reduced-Motion Respect (WCAG 2.2.2)
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let motionPaused = prefersReducedMotion.matches;

  function syncMotionButton() {
    motionToggle.textContent = motionPaused ? 'Resume motion' : 'Pause motion';
  }

  motionToggle.addEventListener('click', () => {
    motionPaused = !motionPaused;
    syncMotionButton();
  });
  syncMotionButton();

  // --- Pointer & Keyboard Interaction on the Pad ---
  function normalizedCoords(ev) {
    const rect = padEl.getBoundingClientRect();
    const nx = Math.max(0, Math.min(1, (ev.clientX - rect.left) / Math.max(1, rect.width)));
    const ny = Math.max(0, Math.min(1, 1 - (ev.clientY - rect.top) / Math.max(1, rect.height)));
    return { nx, ny };
  }

  padEl.addEventListener('pointerdown', (ev) => {
    ev.preventDefault();
    padEl.setPointerCapture(ev.pointerId);
    const { nx, ny } = normalizedCoords(ev);
    startOrUpdateVoice(ev.pointerId, nx, ny);
  });

  padEl.addEventListener('pointermove', (ev) => {
    if (!activeVoices.has(ev.pointerId)) return;
    const { nx, ny } = normalizedCoords(ev);
    startOrUpdateVoice(ev.pointerId, nx, ny);
  });

  const endPointer = (ev) => {
    if (activeVoices.has(ev.pointerId)) stopVoice(ev.pointerId);
  };
  padEl.addEventListener('pointerup', endPointer);
  padEl.addEventListener('pointercancel', endPointer);

  // Accessible keyboard play when pad is focused
  let kbX = 0.5, kbY = 0.72, kbTimeout = null;
  padEl.addEventListener('keydown', (ev) => {
    if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', ' '].includes(ev.key)) return;
    ev.preventDefault();
    if (ev.key === 'ArrowLeft') kbX = Math.max(0, kbX - 0.06);
    if (ev.key === 'ArrowRight') kbX = Math.min(1, kbX + 0.06);
    if (ev.key === 'ArrowUp') kbY = Math.min(1, kbY + 0.08);
    if (ev.key === 'ArrowDown') kbY = Math.max(0.08, kbY - 0.08);
    startOrUpdateVoice('kb', kbX, kbY);
    clearTimeout(kbTimeout);
    kbTimeout = setTimeout(() => stopVoice('kb'), 420);
  });

  // --- Full-Viewport Ambient Touch / Pointer Waveform ---
  const ambientPointer = { x: 0.5, y: 0.5, energy: 0, targetY: 0.5, lastMove: 0 };

  window.addEventListener('pointermove', (ev) => {
    ambientPointer.x = ev.clientX / Math.max(1, window.innerWidth);
    ambientPointer.targetY = ev.clientY / Math.max(1, window.innerHeight);
    ambientPointer.energy = Math.min(1, ambientPointer.energy + 0.35);
    ambientPointer.lastMove = performance.now();
  }, { passive: true });

  window.addEventListener('pointerdown', (ev) => {
    ambientPointer.x = ev.clientX / Math.max(1, window.innerWidth);
    ambientPointer.targetY = ev.clientY / Math.max(1, window.innerHeight);
    ambientPointer.energy = 1.0;
    ambientPointer.lastMove = performance.now();
  }, { passive: true });

  // --- Ferrofluid Spring-Damped Surface Solver ---
  const VERTEX_COUNT = 84;
  const radii = new Float64Array(VERTEX_COUNT).fill(1);
  const vels = new Float64Array(VERTEX_COUNT);
  let ferroPhase = 0;
  let smoothedEnergy = 0;
  let ferroCenterX = 0.5;
  let ferroCenterY = 0.5;

  function resizeCanvases() {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const aw = window.innerWidth;
    const ah = window.innerHeight;
    ambientCanvas.width = Math.floor(aw * dpr);
    ambientCanvas.height = Math.floor(ah * dpr);
    ambientCtx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const rect = padEl.getBoundingClientRect();
    padCanvas.width = Math.floor(rect.width * dpr);
    padCanvas.height = Math.floor(rect.height * dpr);
    padCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  window.addEventListener('resize', resizeCanvases);
  resizeCanvases();

  function drawAmbientWave(nowSec) {
    const w = window.innerWidth;
    const h = window.innerHeight;
    ambientCtx.clearRect(0, 0, w, h);

    // Smoothly track touch Y and decay ambient energy when idle
    ambientPointer.y += (ambientPointer.targetY - ambientPointer.y) * 0.12;
    const voicesArr = Array.from(activeVoices.values());
    const synthEnergy = voicesArr.length > 0 ? Math.max(...voicesArr.map((v) => v.vol)) : 0;
    const effective = Math.max(ambientPointer.energy, synthEnergy);
    ambientPointer.energy *= 0.94;

    if (effective < 0.015) return;

    const baseY = ambientPointer.y * h;
    const focusX = ambientPointer.x * w;
    const freq = voicesArr.length > 0
      ? 2.2 + Math.log2(Math.max(120, voicesArr[0].hz) / 120) * 2.5
      : 3.4;

    const grad = ambientCtx.createLinearGradient(0, 0, w, 0);
    grad.addColorStop(0, 'rgba(0, 198, 238, 0.0)');
    grad.addColorStop(Math.max(0.08, Math.min(0.92, ambientPointer.x - 0.16)), 'rgba(0, 198, 238, 0.42)');
    grad.addColorStop(Math.max(0.10, Math.min(0.94, ambientPointer.x)), 'rgba(34, 96, 255, 0.52)');
    grad.addColorStop(Math.max(0.12, Math.min(0.96, ambientPointer.x + 0.16)), 'rgba(255, 90, 31, 0.42)');
    grad.addColorStop(1, 'rgba(255, 90, 31, 0.0)');

    ambientCtx.save();
    ambientCtx.strokeStyle = grad;
    ambientCtx.lineWidth = 1.8;
    ambientCtx.beginPath();

    const steps = 140;
    for (let i = 0; i <= steps; i++) {
      const u = i / steps;
      const x = u * w;
      const dist = Math.abs(x - focusX) / Math.max(220, w * 0.32);
      const env = Math.exp(-dist * dist * 2.2);
      const amp = (14 + effective * 36) * env;
      const y = baseY + Math.sin(u * Math.PI * 2 * freq - nowSec * 5.2) * amp;
      if (i === 0) ambientCtx.moveTo(x, y);
      else ambientCtx.lineTo(x, y);
    }
    ambientCtx.stroke();
    ambientCtx.restore();
  }

  function drawPad(nowSec, dt) {
    const rect = padEl.getBoundingClientRect();
    const w = rect.width;
    const h = rect.height;
    padCtx.clearRect(0, 0, w, h);

    // 1. Scale fret grid lines
    if (scaleQuantized) {
      const cellW = w / PENT_NOTES.length;
      for (let i = 0; i < PENT_NOTES.length; i++) {
        const x = i * cellW;
        const isRoot = (PENT_NOTES[i] % 12) === 9;
        if (isRoot) {
          padCtx.fillStyle = 'rgba(43, 247, 202, 0.045)';
          padCtx.fillRect(x, 0, cellW, h);
        }
        padCtx.strokeStyle = isRoot ? 'rgba(43, 247, 202, 0.24)' : 'rgba(255, 255, 255, 0.055)';
        padCtx.lineWidth = isRoot ? 1 : 0.6;
        padCtx.beginPath();
        padCtx.moveTo(x, 0);
        padCtx.lineTo(x, h);
        padCtx.stroke();
      }
    }

    const voicesArr = Array.from(activeVoices.values());
    const targetEnergy = voicesArr.length > 0 ? Math.max(...voicesArr.map((v) => v.vol)) : 0;
    smoothedEnergy += (targetEnergy - smoothedEnergy) * Math.min(1, dt * 12);

    // 2. Embedded Liquid Magnetic Ferrofluid
    if (ferroEnabled) {
      const targetCX = voicesArr.length > 0
        ? voicesArr.reduce((s, v) => s + v.x, 0) / voicesArr.length
        : 0.5;
      const targetCY = voicesArr.length > 0
        ? voicesArr.reduce((s, v) => s + (1 - v.y), 0) / voicesArr.length
        : 0.5;
      ferroCenterX += (targetCX - ferroCenterX) * Math.min(1, dt * 8);
      ferroCenterY += (targetCY - ferroCenterY) * Math.min(1, dt * 8);

      const cx = ferroCenterX * w;
      const cy = ferroCenterY * h;
      const baseR = Math.min(w, h) * (0.17 + smoothedEnergy * 0.06);

      if (!motionPaused) {
        ferroPhase += dt * (1.8 + smoothedEnergy * 5.2);
        const partials = TIMBRES[currentTimbre] || TIMBRES.warm;
        const primaryHz = voicesArr.length > 0 ? voicesArr[0].hz : 220;
        const normPitch = Math.max(0, Math.min(1, Math.log2(primaryHz / 110) / 3.5));

        for (let i = 0; i < VERTEX_COUNT; i++) {
          const theta = (i / VERTEX_COUNT) * Math.PI * 2;
          let target = 1.0 + 0.03 * Math.sin(theta * 3 + ferroPhase * 0.7);
          if (smoothedEnergy > 0.01) {
            for (let p = 0; p < partials.length; p++) {
              const lobes = 6 + Math.round(normPitch * 10) + p * 3;
              const wave = Math.sin(theta * lobes + ferroPhase * (p % 2 === 0 ? 1.8 : -1.4));
              target += Math.pow(Math.max(0, wave), 2.2) * partials[p][1] * smoothedEnergy * 0.52;
            }
          }
          const accel = (target - radii[i]) * 115 - vels[i] * 10.5;
          vels[i] += accel * dt;
          radii[i] = Math.max(0.65, Math.min(1.85, radii[i] + vels[i] * dt));
        }
      }

      // Magnetic field aura
      const auraR = baseR * 2.4;
      const aura = padCtx.createRadialGradient(cx, cy, 4, cx, cy, auraR);
      aura.addColorStop(0, `rgba(0, 198, 238, ${0.18 + smoothedEnergy * 0.24})`);
      aura.addColorStop(0.55, `rgba(255, 90, 31, ${0.06 + smoothedEnergy * 0.14})`);
      aura.addColorStop(1, 'rgba(0, 0, 0, 0)');
      padCtx.fillStyle = aura;
      padCtx.beginPath();
      padCtx.arc(cx, cy, auraR, 0, Math.PI * 2);
      padCtx.fill();

      // Smooth closed ferrofluid contour
      const pts = [];
      for (let i = 0; i < VERTEX_COUNT; i++) {
        const theta = (i / VERTEX_COUNT) * Math.PI * 2;
        const r = baseR * radii[i];
        pts.push({ x: cx + Math.cos(theta) * r, y: cy + Math.sin(theta) * r });
      }
      padCtx.beginPath();
      const firstMidX = (pts[VERTEX_COUNT - 1].x + pts[0].x) * 0.5;
      const firstMidY = (pts[VERTEX_COUNT - 1].y + pts[0].y) * 0.5;
      padCtx.moveTo(firstMidX, firstMidY);
      for (let i = 0; i < VERTEX_COUNT; i++) {
        const next = pts[(i + 1) % VERTEX_COUNT];
        padCtx.quadraticCurveTo(pts[i].x, pts[i].y, (pts[i].x + next.x) * 0.5, (pts[i].y + next.y) * 0.5);
      }
      padCtx.closePath();

      const bodyGrad = padCtx.createRadialGradient(cx - baseR * 0.25, cy - baseR * 0.28, 2, cx, cy, baseR * 1.6);
      bodyGrad.addColorStop(0, '#23324a');
      bodyGrad.addColorStop(0.45, '#070a10');
      bodyGrad.addColorStop(1, '#020306');
      padCtx.fillStyle = bodyGrad;
      padCtx.fill();

      const rimGrad = padCtx.createLinearGradient(cx - baseR, cy - baseR, cx + baseR, cy + baseR);
      rimGrad.addColorStop(0, '#2bf7ca');
      rimGrad.addColorStop(0.5, '#3b7bff');
      rimGrad.addColorStop(1, '#ff5a1f');
      padCtx.strokeStyle = rimGrad;
      padCtx.lineWidth = 2.0 + smoothedEnergy * 1.2;
      padCtx.stroke();
    }

    // 3. Direct Touch Waveforms & Luminous Finger Ripples
    const voiceColors = ['#2bf7ca', '#4da3ff', '#ff5a1f', '#ffb838', '#c46bff'];
    voicesArr.forEach((v, idx) => {
      const color = voiceColors[idx % voiceColors.length];
      const px = v.x * w;
      const py = (1 - v.y) * h;

      // Live touch waveform slicing cleanly across the finger's Y line
      padCtx.save();
      padCtx.strokeStyle = color;
      padCtx.globalAlpha = 0.72;
      padCtx.lineWidth = 1.6;
      padCtx.beginPath();
      const cycles = 2 + Math.log2(Math.max(120, v.hz) / 120) * 3.5;
      for (let s = 0; s <= 120; s++) {
        const u = s / 120;
        const x = u * w;
        const dist = Math.abs(x - px) / (w * 0.28);
        const env = Math.exp(-dist * dist * 2.0);
        const y = py + Math.sin(u * Math.PI * 2 * cycles - nowSec * 14) * (10 + v.vol * 24) * env;
        if (s === 0) padCtx.moveTo(x, y);
        else padCtx.lineTo(x, y);
      }
      padCtx.stroke();
      padCtx.restore();

      // Contact node
      padCtx.fillStyle = color;
      padCtx.beginPath();
      padCtx.arc(px, py, 9 + v.vol * 5, 0, Math.PI * 2);
      padCtx.fill();
      padCtx.strokeStyle = '#ffffff';
      padCtx.lineWidth = 1.8;
      padCtx.stroke();
    });
  }

  let lastTime = performance.now();
  function frame(nowMs) {
    const dt = Math.min(0.033, Math.max(0.004, (nowMs - lastTime) / 1000));
    lastTime = nowMs;
    const nowSec = nowMs / 1000;

    if (!motionPaused || activeVoices.size > 0) {
      drawAmbientWave(nowSec);
    } else {
      ambientCtx.clearRect(0, 0, window.innerWidth, window.innerHeight);
    }
    drawPad(nowSec, dt);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
