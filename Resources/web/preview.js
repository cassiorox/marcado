// Renderização do preview do Marcado.
// O lado Swift chama window.marcado.* via evaluateJavaScript/callAsyncJavaScript.
(function () {
  "use strict";

  // breaks: true = quebra simples de linha vira <br>, como o usuário escreveu. O app troca
  // isso pelo ajuste "Respeitar quebras de linha" (marcado.apply / renderHTML).
  const md = window.markdownit({ html: true, linkify: true, typographer: false, breaks: true });

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

  // Link do YouTube sozinho num parágrafo vira cartão com a thumbnail (clicar abre o vídeo).
  function youtubeID(href) {
    const m = /^(?:https?:\/\/)?(?:www\.|m\.)?(?:youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/|embed\/|live\/)|youtu\.be\/)([A-Za-z0-9_-]{11})(?:[?&#][^\s]*)?$/.exec(href);
    return m ? m[1] : null;
  }
  function escapeAttr(s) {
    return String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  md.core.ruler.push("youtube_cards", function (state) {
    const toks = state.tokens;
    for (let i = 1; i < toks.length; i++) {
      const t = toks[i];
      if (t.type !== "inline" || toks[i - 1].type !== "paragraph_open") continue;
      const c = t.children;
      if (!c) continue;
      // Um link sozinho na linha (começo/fim do parágrafo ou entre quebras) vira cartão.
      for (let j = 0; j + 2 < c.length + 0; j++) {
        if (c[j].type !== "link_open" || c[j + 1].type !== "text" || c[j + 2].type !== "link_close") continue;
        const before = j === 0 ? null : c[j - 1];
        const after = j + 3 >= c.length ? null : c[j + 3];
        const alone = (!before || before.type === "softbreak" || before.type === "hardbreak") &&
                      (!after || after.type === "softbreak" || after.type === "hardbreak");
        if (!alone) continue;
        const href = c[j].attrGet("href") || "";
        const id = youtubeID(href);
        if (!id) continue;
        const label = c[j + 1].content.trim();
        const caption = label && label !== href && label !== href.replace(/^https?:\/\//, "") ? label : "";
        const card = new state.Token("html_inline", "", 0);
        card.content =
          '<a class="yt-card" href="' + escapeAttr(href) + '" title="Abrir no YouTube">' +
          '<span class="yt-thumb"><img src="https://img.youtube.com/vi/' + id + '/hqdefault.jpg" alt="" loading="lazy">' +
          '<span class="yt-play" aria-hidden="true"></span></span>' +
          (caption ? '<span class="yt-caption">' + escapeAttr(caption) + "</span>" : "") +
          "</a>";
        c.splice(j, 3, card);
      }
    }
  });

  // Links para pasta ou arquivo do Mac (caminho absoluto ou file://): ganham ícone; clicar abre
  // no Finder (pasta) ou no app padrão (arquivo). O lado Swift decide, ao interceptar a navegação.
  const baseLinkOpen = md.renderer.rules.link_open || function (tokens, idx, options, env, self) { return self.renderToken(tokens, idx, options); };
  md.renderer.rules.link_open = function (tokens, idx, options, env, self) {
    const href = tokens[idx].attrGet("href") || "";
    if (/^(file:\/\/|\/|~\/)/.test(href)) {
      const last = decodeURIComponent(href.replace(/\/+$/, "")).split("/").pop() || "";
      tokens[idx].attrJoin("class", /\.[A-Za-z0-9]{1,8}$/.test(last) ? "file-link" : "folder-link");
    }
    return baseLinkOpen(tokens, idx, options, env, self);
  };

  // Blocos de código: cada linha vira um <span class="ln"> com a indentação em --i (em colunas),
  // para que a linha quebrada continue alinhada ao próprio recuo em vez de voltar à margem.
  function splitCodeLines(html) {
    return html.replace(/(<pre[^>]*><code[^>]*>)([\s\S]*?)(<\/code><\/pre>)/g, function (_, open, body, close) {
      const lines = body.split("\n");
      if (lines.length > 1 && lines[lines.length - 1] === "") lines.pop();
      const out = lines.map(function (l) {
        const lead = /^[ \t]*/.exec(l)[0];
        let cols = 0;
        for (const ch of lead) cols += ch === "\t" ? 4 - (cols % 4) : 1;
        return '<span class="ln" style="--i:' + cols + '">' + l + "</span>";
      });
      return open + out.join("") + close;
    });
  }
  ["fence", "code_block"].forEach(function (rule) {
    const base = md.renderer.rules[rule];
    md.renderer.rules[rule] = function () { return splitCodeLines(base.apply(this, arguments)); };
  });

  // Escolha feita no botão de um bloco (quebrar ou rolar), pela ordem do bloco no documento.
  // Sobrevive às re-renderizações enquanto se digita.
  const wrapOverride = new Map();

  function codeText(pre) {
    const lines = pre.querySelectorAll("code .ln");
    if (lines.length) return Array.from(lines, function (l) { return l.textContent; }).join("\n");
    const code = pre.querySelector("code");
    return code ? code.innerText : pre.innerText;
  }

  const content = document.getElementById("content");
  const root = document.documentElement;
  let blocks = [];
  let userScrollUntil = 0;
  let totalLines = 0;
  let lastText = "";

  function post(msg) {
    try { window.webkit.messageHandlers.marcado.postMessage(msg); } catch (e) { /* fora do app */ }
  }

  function setBase(url) {
    let base = document.querySelector("base");
    if (!url) { if (base) base.remove(); return; }
    if (!base) { base = document.createElement("base"); document.head.prepend(base); }
    base.href = url;
  }

  function isWrapped(pre) {
    if (pre.classList.contains("wrap")) return true;
    if (pre.classList.contains("nowrap")) return false;
    return root.classList.contains("wrap-code");
  }

  function wrapLabel(pre) { return isWrapped(pre) ? "Rolar para o lado" : "Quebrar linhas"; }

  function refreshWrapButtons() {
    content.querySelectorAll("pre .wrap-btn").forEach(function (b) { b.textContent = wrapLabel(b.closest("pre")); });
  }

  function addCopyButtons() {
    content.querySelectorAll("pre").forEach(function (pre, idx) {
      if (wrapOverride.has(idx)) pre.classList.add(wrapOverride.get(idx) ? "wrap" : "nowrap");
      const bar = document.createElement("div");
      bar.className = "code-tools";

      const wrap = document.createElement("button");
      wrap.className = "wrap-btn";
      wrap.textContent = wrapLabel(pre);
      wrap.addEventListener("click", function (ev) {
        ev.preventDefault();
        const next = !isWrapped(pre);
        pre.classList.remove("wrap", "nowrap");
        pre.classList.add(next ? "wrap" : "nowrap");
        wrapOverride.set(idx, next);
        wrap.textContent = wrapLabel(pre);
        collectBlocks();
      });

      const btn = document.createElement("button");
      btn.className = "copy-btn";
      btn.textContent = "Copiar";
      btn.addEventListener("click", function (ev) {
        ev.preventDefault();
        post({ type: "copy", text: codeText(pre) });
        btn.textContent = "Copiado";
        btn.classList.add("done");
        setTimeout(function () { btn.textContent = "Copiar"; btn.classList.remove("done"); }, 1400);
      });

      bar.appendChild(wrap);
      bar.appendChild(btn);
      pre.appendChild(bar);
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
    renderHTML: function (text, breaks) {
      if (typeof breaks === "boolean") md.set({ breaks: breaks });
      return md.render(text);
    },

    render: function (text, baseURL, line) {
      setBase(baseURL);
      lastText = text;
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
      if (typeof s.breaks === "boolean" && md.options.breaks !== s.breaks) {
        md.set({ breaks: s.breaks });
        if (lastText) window.marcado.render(lastText, null, -1);
      }
      root.dataset.theme = s.theme;
      root.style.setProperty("--reader-font", s.font);
      root.style.setProperty("--reader-size", s.size + "px");
      root.style.setProperty("--reader-width", s.width + "px");
      root.style.setProperty("--reader-lh", String(s.lh));
      if (root.classList.contains("wrap-code") !== !!s.wrapCode) {
        root.classList.toggle("wrap-code", !!s.wrapCode);
        wrapOverride.clear();
        content.querySelectorAll("pre").forEach(function (p) { p.classList.remove("wrap", "nowrap"); });
        refreshWrapButtons();
      }
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
