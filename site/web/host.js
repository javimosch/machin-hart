// host.js — the GENERIC JS host (embedded into the server binary at build
// time). App-agnostic: instantiate the wasm, wire the reactive runtime's DOM
// ops, hydrate, and forward [data-action] clicks to same-named wasm exports.
// Adding components or behavior changes only the MFL — this file rarely changes.
const dec = new TextDecoder();
let mem;
const cstr = (p) => { const b = new Uint8Array(mem.buffer); let e = p; while (b[e]) e++; return dec.decode(b.subarray(p, e)); };

const env = {
  // reactive runtime → DOM
  dom_mount: (r, h) => { document.getElementById(cstr(r)).innerHTML = cstr(h); },
  dom_patch: (s, v) => { const el = document.querySelector('[data-s="' + cstr(s) + '"]'); if (el) el.textContent = cstr(v); },
  list_insert: (c, k, h) => { const li = document.createElement('li'); li.dataset.k = cstr(k); li.innerHTML = cstr(h); document.getElementById(cstr(c)).appendChild(li); },
  list_remove: (c, k) => { const el = document.querySelector('#' + cstr(c) + ' > [data-k="' + cstr(k) + '"]'); if (el) el.remove(); },
  list_order: (c, csv) => { const cont = document.getElementById(cstr(c)); for (const k of cstr(csv).split(',').filter(Boolean)) { const el = cont.querySelector('[data-k="' + k + '"]'); if (el) cont.appendChild(el); } },
  // app effects
  toast_show: (id) => { const el = document.getElementById(cstr(id)); if (!el) return; el.classList.remove('hidden'); clearTimeout(el._t); el._t = setTimeout(() => el.classList.add('hidden'), 2500); },
};
// no-op WASI shim (imported but never called)
const wasi = { fd_write: () => 0, fd_seek: () => 0, fd_close: () => 0, fd_fdstat_get: () => 0 };

const { instance } = await WebAssembly.instantiateStreaming(fetch('app.wasm'), { env, wasi_snapshot_preview1: wasi });
mem = instance.exports.memory;
instance.exports._initialize?.();
instance.exports.start();

// delegate clicks: <button data-action="bump" data-arg="0"> calls exports.bump(0n)
document.body.addEventListener('click', (e) => {
  const b = e.target.closest('[data-action]');
  if (b) instance.exports[b.dataset.action]?.(BigInt(b.dataset.arg ?? 0));
});
