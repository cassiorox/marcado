// Renderização do preview do Marcado.
// O lado Swift chama window.marcado.* via evaluateJavaScript/callAsyncJavaScript.
(function () {
  "use strict";

  const md = window.markdownit({ html: true, linkify: true, typographer: false, breaks: false });

  // Marca cada bloco com a linha de origem, para a rolagem sincronizada com o editor.
  md.core.ruler.push("source_lines", function (state) {
    for (const t of state.tokens) {
      if (t.map && (t.nesting === 1 || t.type === "fence" || t.type === "code_block" || t.type === "hr")) {
        t.attrSet("data-line", String(t.map[0]));
        t.attrSet("data-line-end", String(t.map[1]));
      }
    }
  });

  // Listas de tarefas no estilo GitHub: "- [ ] item" e "- [x] item".
  md.core.ruler.push("task_lists", function (state) {
    const toks = state.tokens;
    for (let i = 2; i < toks.length; i++) {
      const t = toks[i];
      if (t.type !== "inline" || toks[i - 1].type !== "paragraph_open" || toks[i - 2].type !== "list_item_open") continue;
      const m = /^\[([ xX])\][ \t]+/.exec(t.content);
      if (!m || !t.children.length) continue;
      const first = t.children[0];
      if (first.type !== "text" || !first.content.startsWith(m[0])) continue;
      first.content = first.content.slice(m[0].length);
      const cb = new state.Token("html_inline", "", 0);
      cb.content = '<input type="checkbox" disabled' + (m[1] === " " ? "" : " checked") + ">";
      t.children.unshift(cb);
      toks[i - 2].attrJoin("class", "task-list-item");
    }
  });


  const content = document.getElementById("content");
  const root = document.documentElement;
  let blocks = [];
  let userScrollUntil = 0;
  let totalLines = 0;

  function post(msg) {
    try { window.webkit.messageHandlers.marcado.postMessage(msg); } catch (e) { /* fora do app */ }
  }

  function setBase(url) {
    let base = document.querySelector("base");
    if (!url) { if (base) base.remove(); return; }
    if (!base) { base = document.createElement("base"); document.head.prepend(base); }
    base.href = url;
  }

  function addCopyButtons() {
    content.querySelectorAll("pre").forEach(function (pre) {
      const btn = document.createElement("button");
      btn.className = "copy-btn";
      btn.textContent = "Copiar";
      btn.addEventListener("click", function (ev) {
        ev.preventDefault();
        const code = pre.querySelector("code");
        post({ type: "copy", text: code ? code.innerText : pre.innerText });
        btn.textContent = "Copiado";
        btn.classList.add("done");
        setTimeout(function () { btn.textContent = "Copiar"; btn.classList.remove("done"); }, 1400);
      });
      pre.appendChild(btn);
    });
  }

  function collectBlocks() {
    const y0 = window.scrollY;
    blocks = Array.from(content.querySelectorAll("[data-line]")).map(function (el) {
      const r = el.getBoundingClientRect();
      return {
        start: +el.dataset.line,
        end: Math.max(+el.dataset.lineEnd, +el.dataset.line + 1),
        top: r.top + y0,
        bottom: r.bottom + y0,
      };
    });
  }

  function maxScroll() {
    return Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
  }

  window.marcado = {
    renderHTML: function (text) { return md.render(text); },

    render: function (text, baseURL, line) {
      setBase(baseURL);
      totalLines = text.split("\n").length;
      if (text.trim() === "") {
        content.innerHTML = '<p class="empty-state">Nada para mostrar ainda.</p>';
      } else {
        content.innerHTML = md.render(text);
        addCopyButtons();
      }
      collectBlocks();
      if (typeof line === "number" && line >= 0) window.marcado.scrollToLine(line);
    },

    apply: function (s) {
      root.dataset.theme = s.theme;
      root.style.setProperty("--reader-font", s.font);
      root.style.setProperty("--reader-size", s.size + "px");
      root.style.setProperty("--reader-width", s.width + "px");
      root.style.setProperty("--reader-lh", String(s.lh));
      collectBlocks();
    },

    scrollToLine: function (line) {
      if (!blocks.length) collectBlocks();
      let y = 0;
      if (line <= 0) {
        y = 0;
      } else if (line >= totalLines - 1) {
        y = maxScroll();
      } else {
        let inside = null, prev = null, next = null;
        for (const b of blocks) {
          if (b.start <= line && line < b.end) inside = b;
          if (b.start <= line && (!prev || b.start >= prev.start)) prev = b;
          if (b.start > line && (!next || b.start < next.start)) next = b;
        }
        if (inside) {
          y = inside.top + (line - inside.start) / (inside.end - inside.start) * (inside.bottom - inside.top);
        } else if (prev && next) {
          const f = (line - prev.end) / Math.max(1, next.start - prev.end);
          y = prev.bottom + Math.max(0, Math.min(1, f)) * (next.top - prev.bottom);
        } else if (prev) {
          y = prev.bottom;
        }
        y -= 48; // padding superior do body
      }
      window.scrollTo(0, Math.max(0, Math.min(maxScroll(), y)));
    },
  };

  // Rolagem feita pelo usuário no preview move o editor. Rolagem programática não ecoa.
  ["wheel", "mousedown", "keydown", "touchstart"].forEach(function (ev) {
    window.addEventListener(ev, function () { userScrollUntil = Date.now() + 700; }, { passive: true });
  });

  window.addEventListener("scroll", function () {
    if (Date.now() > userScrollUntil || !blocks.length) return;
    const y = window.scrollY + 48;
    let line = 0;
    if (window.scrollY <= 0) {
      line = 0;
    } else if (window.scrollY >= maxScroll() - 1) {
      line = totalLines;
    } else {
      let cur = null;
      for (const b of blocks) { if (b.top <= y && (!cur || b.top >= cur.top)) cur = b; }
      if (cur) {
        const h = Math.max(1, cur.bottom - cur.top);
        line = cur.start + Math.max(0, Math.min(1, (y - cur.top) / h)) * (cur.end - cur.start);
      }
    }
    post({ type: "scroll", line: line });
  }, { passive: true });

  window.addEventListener("resize", collectBlocks);
  // Imagens mudam a altura dos blocos depois de carregar.
  document.addEventListener("load", function (e) { if (e.target.tagName === "IMG") collectBlocks(); }, true);
})();
