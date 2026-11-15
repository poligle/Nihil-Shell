(() => {
  const root = document.documentElement;
  const config = window.nihil || {};
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const look = () => root.dataset.look === "glass" ? "glass" : "plain";

  const stage = document.querySelector(".stage");
  let refresh = () => {};
  if (stage) {
    const pictures = [...stage.querySelectorAll(".shots img")];
    const note = stage.querySelector(".look-note");
    const all = [...stage.querySelectorAll(".say")];
    const dots = stage.querySelector(".rail .dots");
    const sources = config.sources || (step => [step.dataset.src]);
    const missing = new Set();
    const loads = new Map();
    const found = new Set();
    let steps = [];
    let index = -1;
    let ticket = 0;

    const load = src => {
      if (!loads.has(src)) {
        loads.set(src, new Promise((done, fail) => {
          const image = new Image();
          image.onload = () => done(src);
          image.onerror = () => fail(src);
          image.src = src;
        }));
      }
      return loads.get(src);
    };
    const order = step => {
      const looks = (step.dataset.looks || "plain").split(" ");
      const preferred = look() === "glass" ? ["glass", "plain"] : ["plain", "glass"];
      return preferred.filter(which => looks.includes(which) && !missing.has(`${step.dataset.shot}:${which}`));
    };
    const picture = async step => {
      for (const which of order(step)) {
        for (const src of sources(step, which)) {
          try {
            await load(src);
            return { which, src };
          } catch (e) {}
        }
        missing.add(`${step.dataset.shot}:${which}`);
      }
      return null;
    };

    const show = async step => {
      const mine = ++ticket;
      const got = await picture(step);
      if (mine !== ticket || !got) return;
      if (note) {
        note.hidden = got.which === look();
        note.textContent = got.which === "glass" ? "Smoked glass" : "Plain";
      }
      const alt = (got.which === "glass" && step.dataset.altGlass) || step.dataset.alt || "";
      const [front, back] = pictures[0].classList.contains("on") ? pictures : [pictures[1], pictures[0]];
      if (front.getAttribute("src") === got.src) {
        front.alt = alt;
        return;
      }
      if (back.getAttribute("src") !== got.src) back.src = got.src;
      try { await back.decode(); } catch (e) {}
      if (mine !== ticket) return;
      back.alt = alt;
      front.alt = "";
      back.classList.add("on");
      front.classList.remove("on");
    };

    const go = i => {
      index = i;
      const step = steps[i];
      all.forEach(s => s.classList.toggle("on", s === step));
      [...dots.children].forEach((dot, k) => dot.setAttribute("aria-current", String(k === i)));
      stage.dataset.shape = step.dataset.shape || "";
      show(step);
      steps.slice(i + 1, i + 3).forEach(next => picture(next));
    };

    const span = () => Math.max(1, stage.offsetHeight - innerHeight);
    const jump = i => {
      const per = span() / steps.length;
      scrollTo({ top: stage.offsetTop + per * i + per / 2, behavior: reduce ? "auto" : "smooth" });
    };

    let frame = 0;
    const update = () => {
      frame = 0;
      const box = stage.getBoundingClientRect();
      const progress = Math.min(0.9999, Math.max(0, -box.top / span()));
      const i = Math.floor(progress * steps.length);
      if (i !== index) go(i);
      root.classList.toggle("staging", box.bottom > innerHeight * 0.45);
    };
    const soon = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };

    const build = () => {
      steps = all.filter(step => !("probe" in step.dataset) || found.has(step));
      stage.style.setProperty("--steps", steps.length);
      dots.replaceChildren(...steps.map((step, i) => {
        const dot = document.createElement("button");
        dot.type = "button";
        dot.className = "dot";
        dot.setAttribute("aria-label", step.dataset.name);
        const tip = document.createElement("span");
        tip.className = "tip";
        tip.textContent = step.dataset.name;
        dot.append(tip);
        dot.addEventListener("click", () => jump(i));
        return dot;
      }));
      index = -1;
      update();
    };

    addEventListener("scroll", soon, { passive: true });
    refresh = () => {
      soon();
      if (steps[index]) show(steps[index]);
    };

    all.filter(step => "probe" in step.dataset).forEach(step => {
      picture(step).then(got => {
        if (got) {
          found.add(step);
          build();
        }
      });
    });
    build();
  }

  const smoke = document.querySelector(".smoke");
  const layoutSmoke = () => {
    if (!smoke) return;
    const css = getComputedStyle(root);
    const px = name => parseFloat(css.getPropertyValue(name));
    const w = innerWidth, h = innerHeight, r = px("--r");
    const x0 = px("--left"), y0 = px("--top"), x1 = w - px("--t"), y1 = h - px("--t");
    const hole = `M${x0 + r} ${y0}H${x1 - r}A${r} ${r} 0 0 1 ${x1} ${y0 + r}V${y1 - r}A${r} ${r} 0 0 1 ${x1 - r} ${y1}` +
      `H${x0 + r}A${r} ${r} 0 0 1 ${x0} ${y1 - r}V${y0 + r}A${r} ${r} 0 0 1 ${x0 + r} ${y0}Z`;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><path fill-rule="evenodd" d="M0 0H${w}V${h}H0Z${hole}"/></svg>`;
    const url = `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
    smoke.style.webkitMaskImage = url;
    smoke.style.maskImage = url;
  };
  layoutSmoke();
  addEventListener("resize", () => {
    layoutSmoke();
    refresh();
  });

  const switches = [...document.querySelectorAll("[data-glass-switch]")];
  const toggles = [...document.querySelectorAll("[data-glass-toggle]")];
  if (switches.length || toggles.length) {
    const setLook = (next, remember) => {
      if (next === "glass") root.dataset.look = "glass"; else delete root.dataset.look;
      switches.forEach(s => s.setAttribute("aria-checked", String(next === "glass")));
      toggles.forEach(t => t.setAttribute("aria-pressed", String(next === "glass")));
      if (remember) { try { localStorage.setItem("nihil-look", next); } catch (e) {} }
      refresh();
    };
    [...switches, ...toggles].forEach(control => control.addEventListener("click", () => setLook(look() === "glass" ? "plain" : "glass", true)));
    setLook(look(), false);
  }

  const mark = document.getElementById("wordmark");
  const logo = mark && mark.querySelector("img");
  if (logo) {
    fetch(logo.src).then(r => r.ok ? r.text() : Promise.reject()).then(text => {
      const svg = new DOMParser().parseFromString(text, "image/svg+xml").documentElement;
      if (svg.nodeName !== "svg") return;
      svg.setAttribute("role", "img");
      svg.setAttribute("aria-label", "NIHIL");
      svg.removeAttribute("width");
      svg.removeAttribute("height");
      mark.replaceChildren(document.importNode(svg, true));
      if (reduce) return;
      const live = mark.querySelector("svg");
      const ink = [...live.querySelectorAll('g[fill="#F2F2F2"] circle, g[fill="#8A8A8A"] circle')];
      const height = live.viewBox.baseVal.height;
      const width = +live.getAttribute("data-mark") || height;
      const x = c => +c.getAttribute("cx");
      const y = c => +c.getAttribute("cy");
      const symbol = ink.filter(c => x(c) < width);
      const letters = ink.filter(c => x(c) >= width);
      if (live.hasAttribute("data-mark")) {
        symbol.sort((a, b) => (y(b) - y(a)) || (Math.abs(x(a) - width / 2) - Math.abs(x(b) - width / 2)));
      } else {
        const far = c => Math.hypot(x(c) - width / 2, y(c) - height / 2);
        symbol.sort((a, b) => far(a) - far(b));
      }
      const centre = live.querySelector('g[fill="#D71921"] circle');
      const on = (el, delay) => el.animate([{ opacity: 0.08 }, { opacity: 1 }], { duration: 180, delay, fill: "backwards", easing: "ease-out" });
      const step = 1100 / Math.max(1, symbol.length);
      symbol.forEach((c, i) => on(c, 120 + i * step));
      const lit = 120 + symbol.length * step;
      if (centre) on(centre, lit + 60);
      letters.forEach(c => on(c, lit + 220 + (x(c) - width) * 2.2));
    }).catch(() => {});
  }

  document.querySelectorAll(".code").forEach(block => {
    if (!navigator.clipboard) return;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "key small copy";
    button.textContent = "Copy";
    button.addEventListener("click", () => {
      navigator.clipboard.writeText(block.querySelector("code").innerText).then(() => {
        button.textContent = "Copied";
        setTimeout(() => { button.textContent = "Copy"; }, 1600);
      });
    });
    block.append(button);
  });

  const leds = [...document.querySelectorAll(".leds a")];
  const targets = leds.map(a => document.querySelector(a.getAttribute("href")));
  const seen = new Map();
  const observer = new IntersectionObserver(entries => {
    entries.forEach(e => seen.set(e.target, e.intersectionRatio));
    let best = 0, ratio = -1;
    targets.forEach((t, i) => {
      const v = seen.get(t) ?? 0;
      if (v > ratio) { ratio = v; best = i; }
    });
    leds.forEach((a, i) => a.setAttribute("aria-current", String(i === best)));
  }, { threshold: [0, 0.1, 0.25, 0.5, 0.75, 1] });
  targets.forEach(t => t && observer.observe(t));
})();
