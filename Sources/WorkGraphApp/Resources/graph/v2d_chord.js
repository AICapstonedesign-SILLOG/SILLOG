/* 원형 차트(코드형, 분야끼리): 둘레 전체 = 분야(색 띠, 업무가 많은 분야부터 위에서 시계 방향).
   띠 길이 = 업무 수. 띠 사이를 잇는 리본 = 두 분야 업무가 같이 쓴 자료 수(띠 안에서 같이 쓴 자료 비율만큼 차지).
   분야나 리본에 올리면 그것만 진하게, 숫자는 띠 안쪽에 업무 수. */
window.V3D = window.V3D || {};
window.V3D.chord = function (main, data, ui) {
  const NS = 'http://www.w3.org/2000/svg', FONT = '"SUIT","Apple SD Gothic Neo",sans-serif', RAD = Math.PI / 180;
  const el = (n, a, p) => { const e = document.createElementNS(NS, n); for (const k in a || {}) e.setAttribute(k, a[k]); if (p) p.appendChild(e); return e; };
  const f1 = v => v.toFixed(1);

  main.innerHTML = '';
  if (!data.tasks.length) return () => {};
  const themes = data.themes.filter(th => data.tasks.some(t => t.theme === th.id));
  data.tasks.forEach(t => { if (!themes.some(th => th.id === t.theme)) themes.push({ id: t.theme, name: t.theme, color: t.color }); });
  // 분야마다 쓴 자료 모음(종류 이름 + 자료 이름으로 구분)
  const keyOf = (k, it) => k + ':' + (typeof it === 'string' ? it : (it.id ?? it.name ?? JSON.stringify(it)));
  themes.forEach(th => {
    th.tasks = data.tasks.filter(t => t.theme === th.id); th.n = th.tasks.length; th.items = new Set();
    th.tasks.forEach(t => Object.entries(t.items || {}).forEach(([k, arr]) => arr.forEach(it => th.items.add(keyOf(k, it)))));
  });
  // 행렬: 두 분야가 같이 쓴 자료 수. 대각선 = 그 분야만 쓴 자료 수
  // 분야마다 자료별로 쓴 업무 수(버블 크기, 확대 목록)
  themes.forEach(th => { th.use = new Map(); th.tasks.forEach(t => Object.entries(t.items || {}).forEach(([k, arr]) => arr.forEach(it => { const key = keyOf(k, it); const u = th.use.get(key) || { key, k, name: typeof it === 'string' ? it : (it.name ?? it.title ?? String(it.id ?? '')), n: 0 }; u.n++; th.use.set(key, u); }))); });
  const N = themes.length, M = themes.map(() => themes.map(() => 0));
  for (let i = 0; i < N; i++) for (let j = i + 1; j < N; j++) { let c = 0; themes[i].items.forEach(x => { if (themes[j].items.has(x)) c++; }); M[i][j] = M[j][i] = c; }
  themes.forEach((th, i) => { let solo = 0; th.items.forEach(x => { if (!themes.some((o, j) => j !== i && o.items.has(x))) solo++; }); M[i][i] = solo; });
  themes.forEach((th, i) => { M[i][i] = 0; th.shared = M[i].reduce((a, v) => a + v, 0); });   // 리본은 다른 분야와 같이 쓴 자료만
  const order = themes.map((_, i) => i).sort((a, b) => themes[b].n - themes[a].n);   // 띠 길이와 순서 = 업무 수

  const wrap = document.createElement('div'); wrap.style.cssText = 'position:absolute;inset:0;font-family:' + FONT; main.appendChild(wrap);
  const svg = el('svg', { style: 'display:block;width:100%;height:100%' }, wrap);
  const tip = document.createElement('div');
  tip.style.cssText = 'position:absolute;pointer-events:none;background:#fff;border:1px solid #E6E1DB;border-radius:8px;padding:6px 9px;font-size:12px;color:#24150F;box-shadow:0 2px 8px rgba(36,21,15,.08);display:none;white-space:nowrap';
  wrap.appendChild(tip);
  const showTip = (ev, html) => { tip.innerHTML = html; tip.style.display = 'block'; const b = wrap.getBoundingClientRect(); tip.style.left = (ev.clientX - b.left + 12) + 'px'; tip.style.top = (ev.clientY - b.top + 12) + 'px'; };

  let ribbons = [];
  // 쉬는 때는 리본마다 작은 쪽 분야 색. 분야나 리본을 고르면 그것만 색이 남고 나머지는 연한 회갈색
  const REST = '#D8D0C8';
  const focus = (ti, one) => ribbons.forEach(r => {
    const on = one ? (r.i === one.i && r.j === one.j) : ti !== null ? (r.i === ti || r.j === ti) : false;
    const col = one ? themes[one.i].color : ti !== null ? themes[ti].color : REST;
    const any = ti !== null || !!one;
    r.e.setAttribute('fill', !any ? r.base : on ? (one ? r.base : (r.i === ti ? themes[r.j].color : themes[r.i].color)) : REST);
    r.e.setAttribute('fill-opacity', any ? (on ? .9 : .4) : .72);
    if (r.num) r.num.setAttribute('opacity', !any || on ? 1 : 0);
  });
  // 고정 선택: 분야 띠나 리본을 누르면 그대로 진하게 남고, 왼쪽 위 카드에 업무나 같이 쓴 자료가 나옴. 빈 곳을 누르면 풀림
  let pin = null;   // { ti } 또는 { rb }
  const card = document.createElement('div');
  card.style.cssText = 'position:absolute;left:24px;top:16px;width:250px;max-height:70%;overflow:auto;background:#fff;border:1px solid #ECE7E2;border-radius:12px;padding:12px 14px;font-size:12px;color:#4A3E37;box-shadow:0 3px 12px rgba(36,21,15,.08);display:none';
  wrap.appendChild(card);
  const esc = x => String(x).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const kindName = k => data.kinds?.[k]?.name || k;
  const showCard = () => { card.style.display = 'none'; };   // 카드 대신 그 분야 쪽으로 확대한다(zoomTo)
  const showCardOld = () => {
    if (!pin) { card.style.display = 'none'; return; }
    let html = '';
    if (pin.ti != null) {
      const th = themes[pin.ti];
      html = `<div style="display:flex;align-items:center;gap:6px;margin-bottom:8px"><span style="width:9px;height:9px;border-radius:50%;background:${th.color}"></span><b style="font-size:13px">${esc(th.name)}</b><span style="color:#8C837C">업무 ${th.n}개</span></div>`
        + th.tasks.slice().sort((a, b) => (b.mins || 0) - (a.mins || 0)).map(t => `<div data-id="${t.id}" style="padding:5px 0;border-top:1px solid #F2EEEA;cursor:pointer;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;${t.id === ui.sel ? 'font-weight:700;color:#24150F' : ''}">${esc(t.title)}</div>`).join('');
    } else {
      const { i, j } = pin.rb, A = themes[i], B = themes[j];
      const shared = [...A.items].filter(x => B.items.has(x)).map(x => { const c = x.indexOf(':'); return [x.slice(0, c), x.slice(c + 1)]; });
      html = `<div style="margin-bottom:8px"><b style="font-size:13px">${esc(A.name)}, ${esc(B.name)}</b><div style="color:#8C837C;margin-top:2px">같이 쓴 자료 ${shared.length}개</div></div>`
        + shared.slice(0, 40).map(([k, nm]) => `<div style="padding:5px 0;border-top:1px solid #F2EEEA;white-space:nowrap;overflow:hidden;text-overflow:ellipsis"><span style="color:#8C837C">${esc(kindName(k))}</span>  ${esc(nm)}</div>`).join('')
        + (shared.length > 40 ? `<div style="color:#8C837C;padding-top:5px">외 ${shared.length - 40}개</div>` : '');
    }
    card.innerHTML = html; card.style.display = 'block';
    card.querySelectorAll('[data-id]').forEach(d => d.addEventListener('click', () => ui.open(+d.dataset.id || d.dataset.id)));
  };
  // 확대 보기 왼쪽 목록: 고른 분야의 자료 전부(종류별, 많이 쓴 순). 고리에 다 못 들어간 자료도 여기서 보인다. 버블을 누르면 목록에서 그 자료를 찾아 줌
  const side = document.createElement('div');
  side.style.cssText = 'position:absolute;left:28px;top:96px;bottom:16px;width:230px;overflow:auto;font-size:12px;line-height:1.85;color:#4A3E37;display:none;scrollbar-width:thin';
  wrap.appendChild(side);
  const fillSide = ti => {
    const th = themes[ti];
    side.innerHTML = Object.keys(data.kinds || {}).map(k => {
      const list = [...th.use.values()].filter(u => u.k === k).sort((a, b) => b.n - a.n);
      if (!list.length) return '';
      return `<div style="margin:12px 0 2px;font-weight:700;color:#2A201B"><span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${data.kinds[k].color};margin-right:7px"></span>${esc(kindName(k))} <span style="font-weight:400;color:#9A918A">${list.length}</span></div>`
        + list.map(u => `<div data-k="${esc(u.key)}" title="${esc(u.name)}" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding-left:15px">${esc(u.name)}${u.n > 1 ? ` <span style="color:#9A918A">${u.n}</span>` : ''}</div>`).join('');
    }).join('');
    side.scrollTop = 0;
  };
  const markSide = key => {
    side.querySelectorAll('[data-on]').forEach(d => { d.removeAttribute('data-on'); d.style.fontWeight = ''; d.style.color = ''; });
    const d = [...side.querySelectorAll('[data-k]')].find(q => q.dataset.k === key); if (!d) return;
    d.setAttribute('data-on', ''); d.style.fontWeight = '700'; d.style.color = '#24150F'; d.scrollIntoView({ block: 'center', behavior: 'smooth' });
  };
  // 확대: 분야를 누르면 그 분야 띠와 자료 버블 쪽으로 부드럽게 다가감, 풀면 원래대로
  let zg = null, geo = null;
  const zoomTo = () => {
    if (!zg || !geo) return;
    const th = pin?.ti != null ? themes[pin.ti] : null;
    if (!th) { zg.style.transform = 'translate(0px,0px) scale(1)'; return; }
    const { W, H, cx, cy, R } = geo, mid = (th.a0 + th.a1) / 2, span = Math.min(330, th.a1 - th.a0);
    const k = Math.max(1.35, Math.min(2.4, 1.6 * 70 / Math.max(40, span)));   // 좁은 분야일수록 더 크게
    const px = cx + (R * .78) * Math.cos(mid * RAD), py = cy + (R * .78) * Math.sin(mid * RAD);
    zg.style.transform = `translate(${W / 2 - k * px}px,${H / 2 - k * py}px) scale(${k})`;
  };
  // 변형: 분야를 고르면 그 분야 띠가 둘레의 절반 넘게 넓어지며 오른쪽으로 돌아오고, 그 자리에 자료 이름과 요약이 나타남. 풀면 되돌아감
  let emph = 0, emphTi = null, raf2 = 0;
  const morphTo = (ti, done) => {
    const from = emph, to = ti != null ? 1 : 0, t0 = performance.now(), D = 650;
    if (ti != null) { emphTi = ti; fillSide(ti); }
    cancelAnimationFrame(raf2);
    const step = now => { const k = Math.min(1, (now - t0) / D), e = k < .5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
      emph = from + (to - from) * e; draw(); if (k < 1) raf2 = requestAnimationFrame(step); else { if (!to) { emphTi = null; draw(); } done?.(); } };
    raf2 = requestAnimationFrame(step);
  };
  const applyPin = () => { pin ? (pin.ti != null ? focus(pin.ti, null) : focus(null, pin.rb)) : focus(null, null); };
  // 다른 분야로 바로 옮길 때는 한 번 풀었다가 새 분야로 다시 확대(돌림이 튀지 않게)
  const setPin = p => { const was = pin?.ti ?? null; pin = p; const now = pin?.ti ?? null; applyPin(); if (now === was) return; if (was != null && now != null) morphTo(null, () => morphTo(now)); else morphTo(now); };
  const hide = () => { tip.style.display = 'none'; applyPin(); };
  // 누르기: 띠, 버블, 이름뿐 아니라 그 분야 쪽 영역(가운데 리본 포함) 어디를 눌러도 그 분야. 원 바깥 빈 곳은 풀기
  svg.addEventListener('click', ev => {
    if (!geo?.g) return;
    const p = svg.createSVGPoint(); p.x = ev.clientX; p.y = ev.clientY;
    const q = p.matrixTransform(geo.g.getScreenCTM().inverse()), rr = Math.hypot(q.x, q.y), ang = Math.atan2(q.y, q.x) / RAD;
    const hit = rr < geo.outR + 90 ? themes.findIndex(th => ((ang - th.a0 + 1.5) % 360 + 360) % 360 <= th.a1 - th.a0 + 3) : -1;
    if (hit < 0) setPin(null); else if (pin?.ti !== hit) setPin({ ti: hit });
  });

  function draw() {
    const W = wrap.clientWidth, H = wrap.clientHeight;
    if (W < 50 || H < 50) return;
    svg.setAttribute('width', W); svg.setAttribute('height', H); svg.innerHTML = '';
    const R = Math.max(90, Math.min(W / 2 - 250, H / 2 - 130)), cyOff = 0, BAND = 14, cx = W / 2, cy = H / 2 + cyOff;
    zg = el('g', {}, svg); geo = { W, H, cx, cy, R };
    const g = el('g', { transform: `translate(${cx},${cy})` }, zg); geo.g = g; geo.outR = R + BAND + 10 + 13 * Object.keys(data.kinds || {}).length + 12;
    const P = (rr, a) => [rr * Math.cos(a * RAD), rr * Math.sin(a * RAD)];
    // 둘레 나누기: 분야 사이 틈 GAP, 나머지를 자료 수 비율로
    const GAP = 3, total = themes.reduce((a, th) => a + th.n, 0) || 1, span = 360 - GAP * N;
    // 고른 분야 무게: emph 에 따라 둘레의 55% 까지
    const wOf = i => { const th = themes[i]; if (i !== emphTi || !emph) return th.n; const target = .55 / .45 * Math.max(1, total - th.n); return th.n + (Math.max(th.n, target) - th.n) * emph; };
    const wt = order.reduce((q, i) => q + wOf(i), 0);
    let a = -90 + GAP / 2;
    order.forEach(i => { const th = themes[i]; th.a0 = a; th.a1 = a + span * wOf(i) / wt; a = th.a1 + GAP; });
    if (emphTi != null && emph) { const m = (themes[emphTi].a0 + themes[emphTi].a1) / 2, rot = -((m % 360) + 360) % 360, r2 = (rot < -180 ? rot + 360 : rot) * emph; themes.forEach(th => { th.a0 += r2; th.a1 += r2; }); }
    // 각 분야 띠 안에서 상대 분야별 몫(상대 순서도 둘레 순서대로)
    const seg = themes.map(() => ({}));
    order.forEach(i => { const th = themes[i]; let c = th.a0; const k = (th.a1 - th.a0) / (th.shared || 1);
      // 자기 몫은 가운데 오도록: 앞쪽 상대들, 자기, 뒤쪽 상대들 순
      const pos = order.indexOf(i), seq = [...order.slice(pos + 1), ...order.slice(0, pos)].reverse();
      [...seq.slice(0, Math.floor(seq.length / 2)), i, ...seq.slice(Math.floor(seq.length / 2))].forEach(j => { const w = M[i][j] * k; seg[i][j] = [c, c + w]; c += w; }); });
    ribbons = [];
    // 확대하는 동안 리본과 숫자는 흐려져 왼쪽 목록과 고리가 읽히게
    const fade = emphTi != null ? (1 - .82 * emph).toFixed(2) : 1;
    const defs = el('defs', {}, svg), rg = el('g', { opacity: fade }, g), ng = el('g', { opacity: fade }, g), r = R - 2;
    const pt = a => P(r, a).map(f1).join(' ');
    for (let i = 0; i < N; i++) for (let j = i + 1; j < N; j++) {
      const v = M[i][j]; if (!v) continue;
      const [s0, s1] = seg[i][j], [t0, t1] = seg[j][i];
      const big0 = s1 - s0 > 180 ? 1 : 0, big1 = t1 - t0 > 180 ? 1 : 0;
      const d = i === j
        ? `M${pt(s0)} A${r} ${r} 0 ${big0} 1 ${pt(s1)} Q${f1(P(r * .35, (s0 + s1) / 2)[0])} ${f1(P(r * .35, (s0 + s1) / 2)[1])} ${pt(s0)}Z`
        : `M${pt(s0)} A${r} ${r} 0 ${big0} 1 ${pt(s1)} Q0 0 ${pt(t0)} A${r} ${r} 0 ${big1} 1 ${pt(t1)} Q0 0 ${pt(s0)}Z`;
      const small = themes[i].n <= themes[j].n ? themes[i] : themes[j];
      const e = el('path', { d, fill: small.color, 'fill-opacity': .72, stroke: '#fff', 'stroke-width': 1.1, 'stroke-opacity': .85 }, rg);
      const rb = { e, i, j, base: small.color };
      // 같이 쓴 자료 수: 리본이 굵으면 가운데쯤에 숫자
      if (v >= 5 && ((s1 - s0) * RAD * r > 14 || (t1 - t0) * RAD * r > 14)) {   // 작은 리본 숫자는 겹치므로 올렸을 때 말풍선으로만
        const [mx, my] = P(r * .55, ((s0 + s1) / 2 + (t0 + t1) / 2) / 2 + (Math.abs((s0 + s1) / 2 - (t0 + t1) / 2) > 180 ? 180 : 0));
        rb.num = el('text', { x: f1(mx), y: f1(my), 'text-anchor': 'middle', 'dominant-baseline': 'middle', 'font-size': 12, 'font-weight': 700, fill: '#2A201B', 'pointer-events': 'none' }, ng);
        rb.num.textContent = '자료 ' + v;
      }
      const html = i === j ? `<b>${themes[i].name}</b>에서만 쓴 자료 ${v}개` : `<b>${themes[i].name}, ${themes[j].name}</b> 같이 쓴 자료 ${v}개`;
      e.addEventListener('mouseenter', ev => { focus(null, rb); showTip(ev, html); });
      e.addEventListener('mousemove', ev => showTip(ev, html));
      e.addEventListener('mouseleave', hide);
      e.style.cursor = 'pointer';
      ribbons.push(rb);
    }
    // 분야 띠, 자료 버블, 이름
    order.forEach(i => {
      const th = themes[i], big = th.a1 - th.a0 > 180 ? 1 : 0, r1 = R + 4, r2 = R + 4 + BAND;
      const [ax, ay] = P(r2, th.a0), [bx, by] = P(r2, th.a1), [qx, qy] = P(r1, th.a1), [dx, dy] = P(r1, th.a0);
      const ag = el('g', {}, g);
      el('path', { d: `M${f1(ax)} ${f1(ay)} A${r2} ${r2} 0 ${big} 1 ${f1(bx)} ${f1(by)} L${f1(qx)} ${f1(qy)} A${r1} ${r1} 0 ${big} 0 ${f1(dx)} ${f1(dy)}Z`, fill: th.color }, ag);
      // 자료 버블: 자료 하나가 버블 하나. 분야 띠 바깥 둘레를 따라 종류 순(주제 → 산출물)으로 늘어놓음.
      // 색 = 자료 범례, 크기 = 그 분야에서 그 자료를 쓴 업무 수. 둘레에 다 못 들어가면 많이 쓴 자료부터 채움
      const mid = (th.a0 + th.a1) / 2, na = ((mid % 360) + 360) % 360, right = na < 90 || na > 270;
      const use = th.use;
      // 층: 자료 종류마다 고리 한 겹. 진한 종류(주제)가 안쪽, 연한 종류가 바깥
      const KO = Object.keys(data.kinds || {}), BR = R + BAND + 10, STEP = 13, rOf = n => 2.2 + 3.6 * Math.sqrt(Math.min(n, 6) / 6);
      const sel = i === emphTi && emph > 0;
      const lpos = new Map();   // 겹 배치 자리
      const bundles = [];   // 묶음 버블: (종류, 같이 가는 리본 방향)이 같은 자료를 하나로
      KO.forEach((k, layer) => {
        const LR = BR + layer * STEP + 5, arcLen = (th.a1 - th.a0) * RAD * LR;
        let list = [...use.values()].filter(u => u.k === k);
        // 다 못 들어가면 많이 쓴 자료만 남김(놓는 순서는 데이터 그대로)
        if (list.reduce((q, u) => q + rOf(u.n) * 2 + 1, 0) > arcLen) { let used = 0; const keep = new Set(); [...list].sort((p2, q2) => q2.n - p2.n).forEach(u => { const w = rOf(u.n) * 2 + 1; if (used + w <= arcLen) { used += w; keep.add(u); } }); list = list.filter(u => keep.has(u)); }
        // 자리 = 데이터: 그 자료를 같이 쓴 분야로 가는 리본이 붙는 자리(여러 분야면 같이 쓴 자료가 가장 많은 분야), 이 분야만 쓴 자료는 이 분야 자기 몫 자리
        const anchorOf = u => { let best = -1; themes.forEach((o, j) => { if (j !== i && o.items.has(u.key) && (best < 0 || M[i][j] > M[i][best])) best = j; }); return best < 0 ? i : best; };
        const byA = new Map(); list.forEach(u => { const j = anchorOf(u); if (!byA.has(j)) byA.set(j, []); byA.get(j).push(u); });
        const toPx = a2 => (a2 - th.a0) * RAD * LR, want = [];
        byA.forEach((arr, j) => {
          const [s0, s1] = seg[i][j], mid2 = (toPx(s0) + toPx(s1)) / 2, span2 = Math.max(toPx(s1) - toPx(s0), arr.reduce((q, u) => q + rOf(u.n) * 2 + 1, 0));
          arr.forEach((u, q) => want.push({ u, r: rOf(u.n), s: mid2 - span2 / 2 + span2 * (q + .5) / arr.length }));
        });
        want.sort((p2, q2) => p2.s - q2.s);
        // 겹치지 않게 앞에서부터 밀고, 띠 끝을 넘으면 뒤에서부터 당김
        let end = 0; want.forEach(w => { w.s = Math.max(w.s, end + w.r + .5); end = w.s + w.r + .5; });
        let lim = arcLen; for (let q = want.length - 1; q >= 0; q--) { const w = want[q]; w.s = Math.min(w.s, lim - w.r - .5); lim = w.s - w.r - .5; }
        want.forEach(w => { const a2 = th.a0 + w.s / LR / RAD, [x, y] = P(LR, a2); lpos.set(w.u, { x, y, r: w.r, a: a2 }); });
        // 묶음: 같은 (종류, 리본 방향) 자료를 버블 하나로. 자리는 그 리본 자리의 가운데, 크기는 자료 수의 제곱근
        const allK = [...use.values()].filter(u => u.k === k), bj = new Map();
        allK.forEach(u => { const j = anchorOf(u); if (!bj.has(j)) bj.set(j, []); bj.get(j).push(u); });
        const bw = [...bj].map(([j, arr]) => { const [s0, s1] = seg[i][j], c = arr.length, lab = c > 1 ? String(c) : '';
          return { arr, c, k, lab, r: Math.min(5.8, 2.4 + 3.4 * Math.sqrt(Math.min(c, 16) / 16)), ex: lab ? 3 + 6.5 * lab.length : 0, s: (toPx(s0) + toPx(s1)) / 2 }; }).sort((p2, q2) => p2.s - q2.s);
        let e2 = 0; bw.forEach(w => { w.s = Math.max(w.s, e2 + w.r + .5); e2 = w.s + w.r + w.ex + .5; });
        let l2 = arcLen; for (let q = bw.length - 1; q >= 0; q--) { const w = bw[q]; w.s = Math.min(w.s, l2 - w.r - w.ex - .5); l2 = w.s - w.r - .5; }
        bw.forEach(w => { w.LR = LR; bundles.push(w); });
      });
      // 고른 분야: 자료를 종류 순(안에서는 많이 쓴 순)으로 한 줄 고리에 늘어놓고 바깥으로 이름(레퍼런스처럼 방사형 글자)
      const rpos = new Map();
      const groups = [];
      if (sel) {
        // 종류마다 구간을 나눠(자료 수의 제곱근 비율, 있으면 최소 3개 자리) 그 안에 많이 쓴 자료부터. 구간 사이는 틈, 구간 머리에 종류 이름과 개수
        const RR = BR + 10, GAPPX = 18, kinds = KO.map(k => ({ k, list: [...use.values()].filter(u => u.k === k).sort((a, b) => b.n - a.n) })).filter(o => o.list.length);
        const arcLen = (th.a1 - th.a0) * RAD * RR - GAPPX * (kinds.length - 1), slot = 9.5;
        const wsum = kinds.reduce((q, o) => q + Math.sqrt(o.list.length), 0) || 1;
        let cur = th.a0;
        kinds.forEach(o => {
          const cap = Math.max(Math.min(3, o.list.length), Math.floor(arcLen * Math.sqrt(o.list.length) / wsum / slot)), part = o.list.slice(0, cap);
          const g0 = cur; let used = 0;
          part.forEach(u => { const r = rOf(u.n), da = (r + 1.6) / RR / RAD; cur += da; const [x, y] = P(RR, cur); rpos.set(u, { x, y, r, a: cur }); cur += da; used++; });
          groups.push({ k: o.k, a0: g0, a1: cur, n: o.list.length, shown: part.length });
          cur += GAPPX / RR / RAD;
        });
      }
      const lerp = (p2, q2, k2) => p2 + (q2 - p2) * k2, labOp = Math.max(0, (emph - .45) / .55), fsz = 11 / (1 + 1.15 * emph);
      (sel ? new Set([...lpos.keys(), ...rpos.keys()]) : []).forEach(u => {
        const A = lpos.get(u), B = rpos.get(u); let x, y, op = 1;
        if (sel && A && B) { x = lerp(A.x, B.x, emph); y = lerp(A.y, B.y, emph); }
        else if (sel && A) { x = A.x; y = A.y; op = 1 - emph; }
        else if (sel && B) { const [sx, sy] = P(R + BAND + 4, B.a); x = lerp(sx, B.x, emph); y = lerp(sy, B.y, emph); op = emph; }
        else { x = A.x; y = A.y; }
        if (op <= .02) return;
        const r = (A || B).r, b = el('circle', { cx: f1(x), cy: f1(y), r: f1(r), fill: data.kinds[u.k].color, opacity: op.toFixed(2) }, ag);
        const html2 = `<b>${u.name}</b><br><span style="color:#8C837C">${data.kinds[u.k].name}, ${th.name} 업무 ${u.n}개에서 씀</span>`;
        b.addEventListener('mouseenter', ev => { ev.stopPropagation(); showTip(ev, html2); }); b.addEventListener('mousemove', ev => showTip(ev, html2));
        b.addEventListener('click', ev => { if (pin?.ti === i) { ev.stopPropagation(); markSide(u.key); } });
        if (B && labOp > 0) {
          const ang = ((B.a % 360) + 360) % 360, flip = ang > 90 && ang < 270, [lx2, ly2] = P(BR + 10 + r + 5, B.a);
          const tl = el('text', { x: f1(lx2), y: f1(ly2), 'text-anchor': flip ? 'end' : 'start', 'dominant-baseline': 'middle', 'font-size': f1(fsz), fill: '#4A3E37', opacity: labOp.toFixed(2), transform: `rotate(${f1(flip ? B.a + 180 : B.a)} ${f1(lx2)} ${f1(ly2)})`, 'pointer-events': 'none' }, ag);
          tl.textContent = u.name.length > 34 ? u.name.slice(0, 33) + '…' : u.name;
        }
      });
      if (!sel) bundles.forEach(w => {
        const a2 = th.a0 + w.s / w.LR / RAD, [x, y] = P(w.LR, a2), kd = data.kinds[w.k];
        const bb = el('circle', { cx: f1(x), cy: f1(y), r: f1(w.r), fill: kd.color }, ag);
        const names = w.arr.slice().sort((p2, q2) => q2.n - p2.n).map(u => esc(u.name)), nm = names.slice(0, 3).join(', ') + (names.length > 3 ? ` 외 ${names.length - 3}개` : '');
        const html3 = `<b>${esc(kd.name)} ${w.c}개</b><br><span style="color:#8C837C">${th.name}, ${nm}</span>`;
        bb.addEventListener('mouseenter', ev => showTip(ev, html3)); bb.addEventListener('mousemove', ev => showTip(ev, html3));
        if (w.lab) { const [tx, ty] = P(w.LR, th.a0 + (w.s + w.r + 2 + w.lab.length * 3.3) / w.LR / RAD);
          const tt = el('text', { x: f1(tx), y: f1(ty), 'text-anchor': 'middle', 'dominant-baseline': 'central', 'font-size': 11, fill: '#6E6862', 'pointer-events': 'none' }, ag); tt.textContent = w.lab; }
      });
      // 종류 구간 머리: 고리 안쪽에 종류 색 짧은 호와 이름, 개수(다 못 보이면 '보이는 수 / 전체')
      if (sel && labOp > 0) groups.forEach(gq => {
        const ri = BR + 2, big = gq.a1 - gq.a0 > 180 ? 1 : 0, [x0, y0] = P(ri, gq.a0), [x1, y1] = P(ri, gq.a1);
        el('path', { d: `M${f1(x0)} ${f1(y0)} A${ri} ${ri} 0 ${big} 1 ${f1(x1)} ${f1(y1)}`, fill: 'none', stroke: data.kinds[gq.k].color, 'stroke-width': f1(3 / (1 + 1.15 * emph)), 'stroke-linecap': 'round', opacity: labOp.toFixed(2) }, ag);
        const am = gq.a0, flip = ((am % 360) + 360) % 360 > 90 && ((am % 360) + 360) % 360 < 270, [hx, hy] = P(BR - 8, am);
        const ht = el('text', { x: f1(hx), y: f1(hy), 'text-anchor': flip ? 'start' : 'end', 'dominant-baseline': 'middle', 'font-size': f1(fsz * 1.05), 'font-weight': 700, fill: '#4A3E37', opacity: labOp.toFixed(2), transform: `rotate(${f1(flip ? am + 180 : am)} ${f1(hx)} ${f1(hy)})`, 'pointer-events': 'none' }, ag);
        ht.textContent = `${data.kinds[gq.k].name} ${gq.shown < gq.n ? gq.shown + '/' + gq.n : gq.n}`;
      });
      // 분야 이름: 버블 바깥, 가로 글자
      const outR = R + BAND + 10 + 13 * Object.keys(data.kinds || {}).length + 12, [lx, ly] = P(outR, mid);
      const t = el('text', { x: f1(lx), y: f1(ly), 'text-anchor': right ? 'start' : 'end', 'dominant-baseline': 'middle', 'font-size': 13.5, 'font-weight': 700, fill: '#2A201B' }, ag);
      t.textContent = th.name; if (sel) t.setAttribute('opacity', (1 - emph).toFixed(2));
      const n = el('tspan', { 'font-weight': 400, fill: '#8C837C', dx: 6, 'font-size': 12 }, t); n.textContent = '업무 ' + th.n;
      const html = `<b>${th.name}</b> 업무 ${th.n}개, 자료 ${th.items.size}개`;
      ag.addEventListener('mouseenter', ev => { focus(i, null); showTip(ev, html); });
      ag.addEventListener('mousemove', ev => showTip(ev, html));
      ag.addEventListener('mouseleave', hide);
      ag.style.cursor = 'pointer';
    });
    // 카메라: 고른 분야(오른쪽으로 돌아온 띠)의 바깥쪽으로 다가가며 확대. emph 와 같은 프레임이라 끊기지 않음
    if (emphTi != null && emph > 0) {
      const th = themes[emphTi], m = (th.a0 + th.a1) / 2, k = 1 + 1.15 * emph;
      const px = cx + (R + 40) * Math.cos(m * RAD), py = cy + (R + 40) * Math.sin(m * RAD);
      const fx = px + ((W > 900 ? W * .5 + 120 : W * .5) - px) * emph, fy = py + (H * .52 - py) * emph;
      zg.setAttribute('transform', `translate(${f1(fx - k * px)},${f1(fy - k * py)}) scale(${k.toFixed(3)})`);
      const cg = el('g', { opacity: Math.max(0, (emph - .3) / .7).toFixed(2), style: 'cursor:pointer' }, svg);
      const c1 = el('text', { x: 28, y: 34, 'font-size': 18, 'font-weight': 700, fill: th.color }, cg); c1.textContent = th.name;
      const c2 = el('text', { x: 28, y: 56, 'font-size': 12.5, fill: '#6E6862' }, cg); c2.textContent = `업무 ${th.n}개, 자료 ${th.items.size}개, 같이 쓴 분야 ${themes.filter((o, j) => j !== emphTi && M[emphTi][j] > 0).length}곳`;
      const c3 = el('text', { x: 28, y: 78, 'font-size': 12, fill: '#9A918A' }, cg); c3.textContent = '‹ 전체 보기';
      cg.addEventListener('click', ev => { ev.stopPropagation(); setPin(null); });
    }
    side.style.display = emphTi != null && emph > .05 ? 'block' : 'none'; side.style.opacity = Math.max(0, (emph - .3) / .7).toFixed(2);
    applyPin();
  }
  // 다른 보기에서 고른 업무가 있으면 그 업무의 분야를 고른 채로 시작
  if (ui.sel) { const t = data.tasks.find(q => q.id === ui.sel), ti = t ? themes.findIndex(th => th.id === t.theme) : -1; if (ti >= 0) { pin = { ti }; emphTi = ti; emph = 1; fillSide(ti); } }
  const ro = new ResizeObserver(draw); ro.observe(wrap); draw(); showCard();
  return () => { ro.disconnect(); wrap.remove(); };
};
