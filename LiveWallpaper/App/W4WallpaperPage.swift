#if !LITE_BUILD
/// The page behind every image or video from the game library. It runs as an ordinary web wallpaper, so
/// the library, per-display playback, pause rules and the desktop picture sync all apply to it unchanged.
enum W4WallpaperPage {
    static let html = #"""
<!doctype html>
<html><head><meta charset="utf-8"><title>w4llpapr</title>
<style>
html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}
#stage{position:absolute;inset:0;transform-origin:50% 50%;will-change:transform}
#media{position:absolute;display:block}
#tint{position:absolute;inset:0;pointer-events:none}
canvas{position:absolute;pointer-events:none}
#fx{inset:0;width:100%;height:100%}
</style>
<script src="config.js"></script>
</head><body>
<div id="stage"><div id="tint"></div></div>
<canvas id="fx"></canvas>
<script>
(function () {
  var C = window.W4 || {};
  var P = Object.assign({
    fit: 'cover', brightness: 0, contrast: 100, saturation: 100, blur: 0, tint: '0 0 0', tintopacity: 0,
    motionon: true, motionamount: 50, motionseconds: 45,
    particleson: true, particlepreset: 'embers', particlecolor: '1 0.878 0.702', particledensity: 100, particlespeed: 100, particlesize: 100,
    pulseon: false, pulseamount: 100, videospeed: 100, videovolume: 0
  }, C.props || {});

  var stage = document.getElementById('stage'), tint = document.getElementById('tint');
  var fx = document.getElementById('fx');
  var fxc = fx.getContext('2d');
  var media = document.createElement(C.kind === 'video' ? 'video' : 'img');
  media.id = 'media';
  var nw = 0, nh = 0, W = 0, H = 0, dpr = 1;
  // Hạt là những đốm sáng mờ, vẽ ở nửa độ phân giải không thấy khác mà đỡ 3/4 số điểm ảnh.
  var FX_SCALE = 0.5, fxDirty = false;
  var rect = { x: 0, y: 0, w: 0, h: 0 };

  function rgb(s, a) {
    var p = String(s).trim().split(/\s+/).map(Number);
    function c(v) { return Math.round(Math.min(1, Math.max(0, v || 0)) * 255); }
    return 'rgba(' + c(p[0]) + ',' + c(p[1]) + ',' + c(p[2]) + ',' + (a === undefined ? 1 : a) + ')';
  }

  function layout() {
    W = window.innerWidth; H = window.innerHeight; dpr = window.devicePixelRatio || 1;
    fx.width = Math.round(W * dpr * FX_SCALE); fx.height = Math.round(H * dpr * FX_SCALE); fxDirty = false;
    if (nw && nh) {
      var mode = P.fit, s;
      if (mode === 'fill') rect = { x: 0, y: 0, w: W, h: H };
      else {
        s = mode === 'contain' ? Math.min(W / nw, H / nh) : mode === 'none' ? 1 / dpr : Math.max(W / nw, H / nh);
        rect = { w: nw * s, h: nh * s, x: (W - nw * s) / 2, y: (H - nh * s) / 2 };
      }
      media.style.left = rect.x + 'px'; media.style.top = rect.y + 'px';
      media.style.width = rect.w + 'px'; media.style.height = rect.h + 'px';
    }
  }

  function applyLook() {
    media.style.filter = 'brightness(' + (1 + P.brightness / 100) + ') contrast(' + P.contrast / 100 + ') saturate(' + P.saturation / 100 + ') blur(' + P.blur + 'px)';
    tint.style.background = rgb(P.tint, P.tintopacity / 100);
    if (C.kind === 'video') {
      media.playbackRate = P.videospeed / 100;
      media.volume = Math.min(1, P.videovolume / 100);
      media.muted = P.videovolume <= 0;
    }
    if (needsAudio()) registerAudio();
    kick();
  }

  // Music
  var bass = 0, heard = false, registered = false;
  function needsAudio() { return P.pulseon; }
  function registerAudio() {
    if (registered || !window.wallpaperRegisterAudioListener) return;
    registered = true;
    window.wallpaperRegisterAudioListener(function (a) {
      heard = true;
      var half = Math.floor(a.length / 2) || 1, b = 0;
      for (var i = 0; i < 6; i++) b += ((a[i] || 0) + (a[i + half] || 0)) / 2;
      bass = Math.max(b / 6, bass * 0.85);
      if (P.pulseon && bass > 0.01) kick();
    });
  }

  // Particles
  var parts = [], last = performance.now(), carry = 0, sprite = null, spriteColor = '';
  var PRESET = {
    embers: { rate: 7, life: 16, v: 34, scale: 0.16, dir: -Math.PI / 2, range: Math.PI / 7, fade: 0.045, from: 'bottom' },
    snow: { rate: 14, life: 20, v: 55, scale: 0.12, dir: Math.PI / 2, range: Math.PI / 8, fade: 0.02, from: 'top' },
    fireflies: { rate: 3, life: 9, v: 12, scale: 0.2, dir: 0, range: Math.PI * 2, fade: 0.1, from: 'any' },
    dust: { rate: 10, life: 22, v: 6, scale: 0.05, dir: 0, range: Math.PI * 2, fade: 0.03, from: 'any' }
  };
  function getSprite() {
    if (sprite && spriteColor === P.particlecolor) return sprite;
    spriteColor = P.particlecolor;
    sprite = document.createElement('canvas'); sprite.width = sprite.height = 48;
    var g = sprite.getContext('2d'), r = g.createRadialGradient(24, 24, 0, 24, 24, 24);
    r.addColorStop(0, rgb(P.particlecolor, 0.9)); r.addColorStop(0.35, rgb(P.particlecolor, 0.4)); r.addColorStop(1, rgb(P.particlecolor, 0));
    g.fillStyle = r; g.fillRect(0, 0, 48, 48);
    return sprite;
  }
  function spawn(k) {
    var speed = k.v * P.particlespeed / 100 * (0.4 + Math.random() * 1.2);
    var a = k.dir + (Math.random() - 0.5) * k.range;
    var x = Math.random() * W, y = k.from === 'bottom' ? H + 20 : k.from === 'top' ? -20 : Math.random() * H;
    parts.push({ x: x, y: y, vx: Math.cos(a) * speed, vy: Math.sin(a) * speed, age: 0,
      life: k.life * (0.65 + Math.random() * 0.7), fade: k.fade, alpha: 0.6 + Math.random() * 0.4,
      size: 48 * k.scale * P.particlesize / 100 * (0.35 + Math.random() * 1.3) });
  }
  function drawParticles(dt) {
    var s = dpr * FX_SCALE;
    fxc.setTransform(s, 0, 0, s, 0, 0);
    if (!P.particleson) { parts.length = 0; if (fxDirty) { fxc.clearRect(0, 0, W, H); fxDirty = false; } return; }
    fxc.clearRect(0, 0, W, H); fxDirty = true;
    var k = PRESET[P.particlepreset] || PRESET.embers;
    carry += k.rate * P.particledensity / 100 * dt;
    while (carry >= 1) { carry -= 1; if (parts.length < 800) spawn(k); }
    fxc.globalCompositeOperation = 'lighter';
    var img = getSprite();
    for (var i = parts.length - 1; i >= 0; i--) {
      var p = parts[i];
      p.age += dt; p.x += p.vx * dt; p.y += p.vy * dt; p.alpha -= p.fade * dt;
      if (p.age > p.life || p.alpha <= 0) { parts.splice(i, 1); continue; }
      fxc.globalAlpha = Math.max(0, p.alpha) * Math.min(1, p.age * 2) * 0.75;
      fxc.drawImage(img, p.x - p.size / 2, p.y - p.size / 2, p.size, p.size);
    }
    fxc.globalAlpha = 1;
  }
  // Frame. Vòng vẽ chỉ chạy khi có thứ đang chuyển động, và tối đa 30 lần/giây
  // (60 khi đang nhún theo nhạc), thay vì chạy theo tần số màn cả khi đứng yên.
  var start = performance.now(), lastTransform = '', running = false, lastDraw = 0;
  function moving() { return P.motionon && C.kind !== 'video'; }
  function wants() {
    if (document.hidden) return false;
    return moving() || P.particleson || parts.length > 0 || (P.pulseon && heard && bass > 0.002);
  }
  function kick() {
    if (running || !wants()) return;
    running = true; last = performance.now(); lastDraw = 0;
    requestAnimationFrame(frame);
  }
  function frame(now) {
    if (!wants()) {
      running = false;
      if (fxDirty) { fxc.clearRect(0, 0, W, H); fxDirty = false; }
      var rest = moving() ? lastTransform : 'none';
      if (rest !== lastTransform) { stage.style.transform = rest === 'none' ? '' : rest; lastTransform = rest; }
      return;
    }
    requestAnimationFrame(frame);
    var gap = P.pulseon && heard ? 15 : 32;
    if (now - lastDraw < gap) return;
    lastDraw = now;
    var dt = Math.min(0.1, (now - last) / 1000); last = now;
    var scale = 1, tx = 0, ty = 0;
    if (P.motionon && C.kind !== 'video') {
      var a = P.motionamount / 100, q = (1 - Math.cos(Math.PI * ((now - start) / 1000) / Math.max(1, P.motionseconds))) / 2;
      scale += a * 0.1 * q; tx = W * 0.04 * a * q; ty = -H * 0.024 * a * q;
    }
    if (P.pulseon && heard) { scale += Math.min(1, bass) * 0.02 * P.pulseamount / 100; bass *= 0.97; }
    var tf = 'scale(' + scale.toFixed(4) + ') translate(' + tx.toFixed(2) + 'px,' + ty.toFixed(2) + 'px)';
    if (tf !== lastTransform) { stage.style.transform = tf; lastTransform = tf; }
    drawParticles(dt);
  }

  function ready() { layout(); applyLook(); kick(); window.w4Ready = true; }
  document.addEventListener('visibilitychange', kick);
  if (C.kind === 'video') {
    media.autoplay = true; media.loop = true; media.muted = true; media.playsInline = true;
    media.addEventListener('loadedmetadata', function () { nw = media.videoWidth; nh = media.videoHeight; layout(); });
    media.src = C.src; stage.insertBefore(media, tint); media.play && media.play().catch(function () {});
    ready();
  } else {
    media.onload = function () { nw = media.naturalWidth; nh = media.naturalHeight; ready(); };
    media.src = C.src; stage.insertBefore(media, tint);
  }
  window.addEventListener('resize', layout);
  window.wallpaperPropertyListener = {
    applyUserProperties: function (props) {
      Object.keys(props).forEach(function (k) { if (props[k] && 'value' in props[k]) P[k] = props[k].value; });
      layout(); applyLook();
    }
  };
})();
</script></body></html>

"""#
}
#endif
