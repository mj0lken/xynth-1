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

  // --- Web Audio Polyphonic Additive Synth ---
  const TIMBRES = {
    sine: [[1, 1.0]],
    warm: [[1, 0.72], [2, 0.28], [3, 0.08]],
    saw: [[1, 0.48], [2, 0.26], [3, 0.15], [4, 0.08], [5, 0.05]],
    bell: [[1, 0.58], [2.756, 0.28], [5.404, 0.14]]
  };

  let audioCtx = null;
  let masterGain = null;
  const activeVoices = new Map(); // id -> { oscs, voiceGain, x, y, hz, vol, trail }

  function ensureAudio() {
    if (!audioCtx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      audioCtx = new AC();
      masterGain = audioCtx.createGain();
      masterGain.gain.value = 0.26;
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

  function startOrUpdateVoice(id, nx, ny, exactHz = null) {
    const ctx = ensureAudio();
    const hz = exactHz ?? xToFrequency(nx, scaleQuantized);
    const vol = Math.max(0.06, Math.min(1, 0.06 + 0.94 * Math.pow(ny, 0.78)));

    let voice = activeVoices.get(id);
    if (!voice) {
      const voiceGain = ctx ? ctx.createGain() : null;
      const partials = TIMBRES[currentTimbre] || TIMBRES.warm;
      const oscs = [];

      if (ctx && voiceGain) {
        voiceGain.gain.setValueAtTime(0.0001, ctx.currentTime);
        voiceGain.gain.exponentialRampToValueAtTime(Math.max(0.001, vol * 0.65), ctx.currentTime + 0.025);
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
      if (voice.trail.length > 26) voice.trail.shift();

      if (ctx && voice.voiceGain) {
        const t = ctx.currentTime;
        voice.voiceGain.gain.setTargetAtTime(Math.max(0.001, vol * 0.65), t, 0.022);
        for (const item of voice.oscs) {
          item.osc.frequency.setTargetAtTime(Math.min(6000, hz * item.mult), t, 0.028);
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
      voice.voiceGain.gain.setTargetAtTime(0.0001, t, 0.028);
      setTimeout(() => {
        for (const item of voice.oscs) {
          try { item.osc.stop(); item.osc.disconnect(); } catch (_) {}
        }
        try { voice.voiceGain.disconnect(); } catch (_) {}
      }, 160);
    }
    updateHud();
  }

  function rebuildActiveVoiceTimbres() {
    for (const [id, v] of Array.from(activeVoices.entries())) {
      const { x, y, hz } = v;
      stopVoice(id);
      startOrUpdateVoice(id, x, y, hz);
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
  const demoToggle = document.getElementById('demo-toggle');
  const demoLabel = document.getElementById('demo-label');
  const scaleToggle = document.getElementById('scale-toggle');
  const scaleLabel = document.getElementById('scale-label');
  const ferroToggle = document.getElementById('ferro-toggle');

  // --- Choreographed 9-Second Multi-Finger Demo ---
  let demoRunning = false;
  let demoStartMs = 0;

  // Each segment specifies start/end seconds and virtual fingers [{ id, x0, y0, x1, y1, m0, m1 }]
  const DEMO_DURATION_SEC = 8.6;
  const DEMO_SCENES = [
    // Melodic OP-1 style opening hook (A4 -> C5 -> E5 -> G5 -> E5)
    { t0: 0.00, t1: 0.55, fingers: [{ id: 'demo-1', x0: 0.36, y0: 0.62, x1: 0.39, y1: 0.72, m0: 69, m1: 69 }] },
    { t0: 0.55, t1: 1.10, fingers: [{ id: 'demo-1', x0: 0.48, y0: 0.68, x1: 0.50, y1: 0.78, m0: 72, m1: 72 }] },
    { t0: 1.10, t1: 1.75, fingers: [{ id: 'demo-1', x0: 0.61, y0: 0.74, x1: 0.64, y1: 0.84, m0: 76, m1: 76 }] },
    { t0: 1.75, t1: 2.45, fingers: [{ id: 'demo-1', x0: 0.73, y0: 0.84, x1: 0.62, y1: 0.76, m0: 79, m1: 76 }] },
    // 3-Finger shimmering Am9 chord (A3 + E4 + B4)
    {
      t0: 2.50, t1: 4.55,
      fingers: [
        { id: 'demo-1', x0: 0.22, y0: 0.66, x1: 0.24, y1: 0.76, m0: 57, m1: 57 },
        { id: 'demo-2', x0: 0.44, y0: 0.72, x1: 0.46, y1: 0.82, m0: 64, m1: 64 },
        { id: 'demo-3', x0: 0.66, y0: 0.68, x1: 0.69, y1: 0.80, m0: 71, m1: 71 }
      ]
    },
    // Expressive 3-finger glide: Cmaj7 (C4+G4+E5) -> lush A5 bloom (A4+E5+A5)
    {
      t0: 4.60, t1: 6.50,
      fingers: [
        { id: 'demo-1', x0: 0.28, y0: 0.72, x1: 0.40, y1: 0.80, m0: 60, m1: 69 },
        { id: 'demo-2', x0: 0.52, y0: 0.76, x1: 0.64, y1: 0.86, m0: 67, m1: 76 },
        { id: 'demo-3', x0: 0.75, y0: 0.80, x1: 0.86, y1: 0.90, m0: 76, m1: 81 }
      ]
    },
    // Warm held resolution fading gently into stillness
    {
      t0: 6.50, t1: 8.60,
      fingers: [
        { id: 'demo-1', x0: 0.40, y0: 0.80, x1: 0.39, y1: 0.28, m0: 69, m1: 69 },
        { id: 'demo-2', x0: 0.64, y0: 0.86, x1: 0.63, y1: 0.30, m0: 76, m1: 76 },
        { id: 'demo-3', x0: 0.86, y0: 0.90, x1: 0.84, y1: 0.26, m0: 81, m1: 81 }
      ]
    }
  ];

  function stopDemo() {
    if (!demoRunning) return;
    demoRunning = false;
    padEl.classList.remove('is-demo');
    demoToggle.classList.remove('is-playing');
    demoLabel.textContent = '▶ PLAY DEMO';
    for (const id of ['demo-1', 'demo-2', 'demo-3']) {
      stopVoice(id);
    }
    updateHud();
  }

  function startDemo() {
    ensureAudio();
    demoRunning = true;
    demoStartMs = performance.now();
    padEl.classList.add('is-demo');
    demoToggle.classList.add('is-playing');
    demoLabel.textContent = '■ STOP DEMO';
    updateHud();
  }

  function stepDemo(nowMs) {
    if (!demoRunning) return;
    const elapsed = (nowMs - demoStartMs) / 1000;
    if (elapsed >= DEMO_DURATION_SEC) {
      stopDemo();
      return;
    }

    const activeDemoIds = new Set();
    for (const scene of DEMO_SCENES) {
      if (elapsed >= scene.t0 && elapsed < scene.t1) {
        const u = (elapsed - scene.t0) / Math.max(0.01, scene.t1 - scene.t0);
        const smooth = u * u * (3 - 2 * u);
        for (const f of scene.fingers) {
          const x = f.x0 + (f.x1 - f.x0) * smooth;
          const y = f.y0 + (f.y1 - f.y0) * smooth;
          const vib = Math.sin(elapsed * 32 + x * 4) * 0.08 * Math.min(1, u * 3);
          const hz = midiToHz(f.m0 + (f.m1 - f.m0) * smooth + vib);
          startOrUpdateVoice(f.id, x, y, hz);
          activeDemoIds.add(f.id);
        }
      }
    }

    for (const id of ['demo-1', 'demo-2', 'demo-3']) {
      if (!activeDemoIds.has(id) && activeVoices.has(id)) {
        stopVoice(id);
      }
    }

    // Sync ambient background wave directly to the primary demo finger's viewport position
    const lead = activeVoices.get('demo-1');
    if (lead) {
      const rect = padEl.getBoundingClientRect();
      ambientPointer.x = (rect.left + lead.x * rect.width) / Math.max(1, window.innerWidth);
      ambientPointer.targetY = (rect.top + (1 - lead.y) * rect.height) / Math.max(1, window.innerHeight);
      ambientPointer.energy = Math.max(ambientPointer.energy, lead.vol * 0.9);
    }
  }

  demoToggle.addEventListener('click', () => {
    if (demoRunning) stopDemo();
    else startDemo();
  });

  function updateHud() {
    if (activeVoices.size === 0) {
      padEl.classList.remove('is-active');
      statusText.textContent = 'TOUCH, DRAG, OR PRESS PLAY DEMO';
      readoutEl.textContent = '— · 0 Hz';
      return;
    }
    padEl.classList.add('is-active');
    const primary = Array.from(activeVoices.values())[0];
    const count = activeVoices.size;
    if (demoRunning) {
      statusText.textContent = count > 1 ? `DEMO · ${count}-FINGER CHORD` : `DEMO · ${currentTimbre.toUpperCase()}`;
    } else {
      statusText.textContent = count > 1 ? `PLAYING ${count} VOICES` : `PLAYING · ${currentTimbre.toUpperCase()}`;
    }
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

  // --- Interactive 8-Theme Showcase Panel ---
  const themeStage = document.getElementById('theme-preview');
  const themePreviewName = document.getElementById('theme-preview-name');
  const THEME_LABELS = {
    op1: 'OP-1 FIELD',
    tech80s: '80S TECH',
    dieter: 'DIETER WHITE',
    obsidian: 'OBSIDIAN',
    neon: 'NEON CYBER',
    inca: 'INCA GOLD',
    acid: 'ACID MODERN',
    koto: 'KOTO CLAY'
  };

  document.querySelectorAll('[data-preview-theme]').forEach((chip) => {
    chip.addEventListener('click', () => {
      const skin = chip.dataset.previewTheme;
      themeStage.setAttribute('data-skin', skin);
      themePreviewName.textContent = THEME_LABELS[skin] || skin.toUpperCase();
      document.querySelectorAll('[data-preview-theme]').forEach((c) => {
        const active = c === chip;
        c.classList.toggle('is-active', active);
        c.setAttribute('aria-pressed', String(active));
      });
    });
  });

  // --- Reduced-Motion Preference Respect ---
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let reducedMotion = prefersReducedMotion.matches;
  prefersReducedMotion.addEventListener('change', (ev) => {
    reducedMotion = ev.matches;
  });

  // --- Pointer & Keyboard Interaction on the Pad ---
  function normalizedCoords(ev) {
    const rect = padEl.getBoundingClientRect();
    const nx = Math.max(0, Math.min(1, (ev.clientX - rect.left) / Math.max(1, rect.width)));
    const ny = Math.max(0, Math.min(1, 1 - (ev.clientY - rect.top) / Math.max(1, rect.height)));
    return { nx, ny };
  }

  padEl.addEventListener('pointerdown', (ev) => {
    ev.preventDefault();
    if (demoRunning) stopDemo();
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
    if (demoRunning) stopDemo();
    if (ev.key === 'ArrowLeft') kbX = Math.max(0, kbX - 0.06);
    if (ev.key === 'ArrowRight') kbX = Math.min(1, kbX + 0.06);
    if (ev.key === 'ArrowUp') kbY = Math.min(1, kbY + 0.08);
    if (ev.key === 'ArrowDown') kbY = Math.max(0.08, kbY - 0.08);
    startOrUpdateVoice('kb', kbX, kbY);
    clearTimeout(kbTimeout);
    kbTimeout = setTimeout(() => stopVoice('kb'), 420);
  });

  // --- Full-Viewport Ambient Touch / Pointer Waveform ---
  const ambientPointer = { x: 0.5, y: 0.5, energy: 0, targetY: 0.5 };

  window.addEventListener('pointermove', (ev) => {
    ambientPointer.x = ev.clientX / Math.max(1, window.innerWidth);
    ambientPointer.targetY = ev.clientY / Math.max(1, window.innerHeight);
    ambientPointer.energy = Math.min(1, ambientPointer.energy + 0.32);
  }, { passive: true });

  window.addEventListener('pointerdown', (ev) => {
    ambientPointer.x = ev.clientX / Math.max(1, window.innerWidth);
    ambientPointer.targetY = ev.clientY / Math.max(1, window.innerHeight);
    ambientPointer.energy = 1.0;
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

    ambientPointer.y += (ambientPointer.targetY - ambientPointer.y) * 0.12;
    const voicesArr = Array.from(activeVoices.values());
    const synthEnergy = voicesArr.length > 0 ? Math.max(...voicesArr.map((v) => v.vol)) : 0;
    const effective = Math.max(ambientPointer.energy, synthEnergy);
    ambientPointer.energy *= 0.94;

    if (effective < 0.015) return;

    const baseY = ambientPointer.y * h;
    const focusX = ambientPointer.x * w;
    const isPlaying = voicesArr.length > 0;
    const freq = isPlaying
      ? 2.4 + Math.log2(Math.max(120, voicesArr[0].hz) / 120) * 2.8
      : 3.4;

    const grad = ambientCtx.createLinearGradient(0, 0, w, 0);
    if (isPlaying) {
      grad.addColorStop(0, 'rgba(0, 142, 180, 0.0)');
      grad.addColorStop(0.14, 'rgba(0, 142, 180, 0.56)');
      grad.addColorStop(0.50, 'rgba(29, 87, 232, 0.64)');
      grad.addColorStop(0.86, 'rgba(223, 68, 14, 0.56)');
      grad.addColorStop(1, 'rgba(223, 68, 14, 0.0)');
    } else {
      grad.addColorStop(0, 'rgba(0, 142, 180, 0.0)');
      grad.addColorStop(Math.max(0.08, Math.min(0.92, ambientPointer.x - 0.16)), 'rgba(0, 142, 180, 0.36)');
      grad.addColorStop(Math.max(0.10, Math.min(0.94, ambientPointer.x)), 'rgba(29, 87, 232, 0.44)');
      grad.addColorStop(Math.max(0.12, Math.min(0.96, ambientPointer.x + 0.16)), 'rgba(223, 68, 14, 0.38)');
      grad.addColorStop(1, 'rgba(223, 68, 14, 0.0)');
    }

    ambientCtx.save();
    ambientCtx.strokeStyle = grad;
    ambientCtx.lineWidth = isPlaying ? 2.1 : 1.75;
    ambientCtx.beginPath();

    const steps = 160;
    const spread = isPlaying ? Math.max(420, w * 0.62) : Math.max(220, w * 0.32);
    for (let i = 0; i <= steps; i++) {
      const u = i / steps;
      const x = u * w;
      const dist = Math.abs(x - focusX) / spread;
      const env = isPlaying
        ? Math.sin(u * Math.PI) * (0.45 + 0.55 * Math.exp(-dist * dist * 1.4))
        : Math.exp(-dist * dist * 2.2);
      const amp = (12 + effective * (isPlaying ? 40 : 34)) * env;
      const y = baseY + Math.sin(u * Math.PI * 2 * freq - nowSec * (isPlaying ? 8.5 : 5.2)) * amp;
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
          padCtx.fillStyle = 'rgba(43, 247, 202, 0.048)';
          padCtx.fillRect(x, 0, cellW, h);
        }
        padCtx.strokeStyle = isRoot ? 'rgba(43, 247, 202, 0.25)' : 'rgba(255, 255, 255, 0.055)';
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

    // Keep background ambient wave aligned with active touch/pad interaction
    if (voicesArr.length > 0 && !demoRunning) {
      const rect = padEl.getBoundingClientRect();
      const lead = voicesArr[0];
      ambientPointer.x = (rect.left + lead.x * rect.width) / Math.max(1, window.innerWidth);
      ambientPointer.targetY = (rect.top + (1 - lead.y) * rect.height) / Math.max(1, window.innerHeight);
      ambientPointer.energy = Math.max(ambientPointer.energy, lead.vol);
    }

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
      const baseR = Math.min(w, h) * (0.175 + smoothedEnergy * 0.065);

      // Animate ferrofluid physics only when actively driven (or settling smoothly back to rest)
      if (!reducedMotion && (smoothedEnergy > 0.005 || activeVoices.size > 0)) {
        ferroPhase += dt * (1.8 + smoothedEnergy * 5.2);
        const partials = TIMBRES[currentTimbre] || TIMBRES.warm;
        const primaryHz = voicesArr.length > 0 ? voicesArr[0].hz : 220;
        const normPitch = Math.max(0, Math.min(1, Math.log2(primaryHz / 110) / 3.5));

        for (let i = 0; i < VERTEX_COUNT; i++) {
          const theta = (i / VERTEX_COUNT) * Math.PI * 2;
          let target = 1.0 + 0.025 * Math.sin(theta * 3 + ferroPhase * 0.7) * Math.min(1, smoothedEnergy * 2.5);
          if (smoothedEnergy > 0.01) {
            for (let p = 0; p < partials.length; p++) {
              const lobes = 6 + Math.round(normPitch * 10) + p * 3;
              const wave = Math.sin(theta * lobes + ferroPhase * (p % 2 === 0 ? 1.8 : -1.4));
              target += Math.pow(Math.max(0, wave), 2.2) * partials[p][1] * smoothedEnergy * 0.54;
            }
          }
          const accel = (target - radii[i]) * 115 - vels[i] * 10.5;
          vels[i] += accel * dt;
          radii[i] = Math.max(0.65, Math.min(1.88, radii[i] + vels[i] * dt));
        }
      }

      const auraR = baseR * 2.45;
      const aura = padCtx.createRadialGradient(cx, cy, 4, cx, cy, auraR);
      aura.addColorStop(0, `rgba(0, 198, 238, ${0.18 + smoothedEnergy * 0.25})`);
      aura.addColorStop(0.55, `rgba(255, 90, 31, ${0.06 + smoothedEnergy * 0.14})`);
      aura.addColorStop(1, 'rgba(0, 0, 0, 0)');
      padCtx.fillStyle = aura;
      padCtx.beginPath();
      padCtx.arc(cx, cy, auraR, 0, Math.PI * 2);
      padCtx.fill();

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
      padCtx.lineWidth = 2.0 + smoothedEnergy * 1.25;
      padCtx.stroke();
    }

    // 3. Glide Trails, Standing-Wave Rings & Numbered Fingertip Nodes
    // (The full-viewport waveform behind the pad runs instead of a duplicate wave inside the pad.)
    const voiceColors = ['#2bf7ca', '#4da3ff', '#ffb838', '#ff5a1f', '#c46bff'];
    voicesArr.forEach((v, idx) => {
      const color = voiceColors[idx % voiceColors.length];
      const px = v.x * w;
      const py = (1 - v.y) * h;

      // Glide trail
      if (v.trail.length > 1) {
        padCtx.save();
        padCtx.strokeStyle = color;
        padCtx.lineCap = 'round';
        for (let i = 1; i < v.trail.length; i++) {
          const frac = i / v.trail.length;
          padCtx.globalAlpha = frac * 0.55;
          padCtx.lineWidth = 1.4 + frac * 3.0;
          padCtx.beginPath();
          padCtx.moveTo(v.trail[i - 1].x * w, (1 - v.trail[i - 1].y) * h);
          padCtx.lineTo(v.trail[i].x * w, (1 - v.trail[i].y) * h);
          padCtx.stroke();
        }
        padCtx.restore();
      }

      // Concentric standing-wave rings
      padCtx.save();
      padCtx.strokeStyle = color;
      for (let ring = 0; ring < 2; ring++) {
        const phase = (nowSec * 1.4 + ring * 0.5) % 1;
        padCtx.globalAlpha = (1 - phase) * 0.45;
        padCtx.lineWidth = 1.4;
        padCtx.beginPath();
        padCtx.arc(px, py, 14 + phase * (34 + v.vol * 36), 0, Math.PI * 2);
        padCtx.stroke();
      }
      padCtx.restore();

      // Contact node + finger index stamp
      const r = 10 + v.vol * 5;
      padCtx.fillStyle = color;
      padCtx.beginPath();
      padCtx.arc(px, py, r, 0, Math.PI * 2);
      padCtx.fill();
      padCtx.strokeStyle = '#ffffff';
      padCtx.lineWidth = 1.8;
      padCtx.stroke();

      padCtx.fillStyle = '#090c12';
      padCtx.font = '800 10px ui-monospace, SFMono-Regular, Menlo, monospace';
      padCtx.textAlign = 'center';
      padCtx.textBaseline = 'middle';
      padCtx.fillText(String(idx + 1), px, py + 0.5);
    });
  }

  let lastTime = performance.now();
  function frame(nowMs) {
    const dt = Math.min(0.033, Math.max(0.004, (nowMs - lastTime) / 1000));
    lastTime = nowMs;
    const nowSec = nowMs / 1000;

    stepDemo(nowMs);

    if (!reducedMotion || activeVoices.size > 0) {
      drawAmbientWave(nowSec);
    } else {
      ambientCtx.clearRect(0, 0, window.innerWidth, window.innerHeight);
    }
    drawPad(nowSec, dt);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
