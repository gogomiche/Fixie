// Shared helpers injected into every editor page. Each page calls
// QAInstall({...}) with a small adapter around its editor's API; the
// harness then drives copy/paste through real (synthetic) clipboard events,
// replaying the browser's sequence: paste → beforeinput(insertFromPaste) →
// default insertion, each step only if the previous one wasn't handled.
window.addEventListener('error', e => { window.QAError = String(e.message || e); });
window.addEventListener('unhandledrejection', e => {
  const r = e.reason;
  window.QAError = String((r && (r.stack || r.message)) || r);
});

window.QAUtil = {
  sleep: ms => new Promise(r => setTimeout(r, ms)),
  dataTransfer(data) {
    const dt = new DataTransfer();
    for (const [type, value] of Object.entries(data || {})) {
      if (value != null) dt.setData(type, value);
    }
    return dt;
  },
  clipboardEvent(type, dt) {
    let ev;
    try { ev = new ClipboardEvent(type, { clipboardData: dt, bubbles: true, cancelable: true }); }
    catch (e) { ev = new Event(type, { bubbles: true, cancelable: true }); }
    if (!ev.clipboardData) Object.defineProperty(ev, 'clipboardData', { value: dt });
    return ev;
  },
  beforeInputPaste(dt) {
    let ev;
    try { ev = new InputEvent('beforeinput', { inputType: 'insertFromPaste', dataTransfer: dt, bubbles: true, cancelable: true }); }
    catch (e) { return null; }
    if (!ev.dataTransfer) Object.defineProperty(ev, 'dataTransfer', { value: dt });
    return ev;
  },
};

window.QAInstall = function (ed) {
  const target = () => {
    const a = document.activeElement;
    return a && ed.root().contains(a) ? a : ed.root();
  };

  ed.paste = async function (data) {
    await ed.clear(); await QAUtil.sleep(60);
    await ed.focusEnd(); await QAUtil.sleep(60);
    const el = target();
    const paste = QAUtil.clipboardEvent('paste', QAUtil.dataTransfer(data));
    el.dispatchEvent(paste);
    let handledBy = 'paste-event';
    if (!paste.defaultPrevented) {
      const bi = QAUtil.beforeInputPaste(QAUtil.dataTransfer(data));
      if (bi) el.dispatchEvent(bi);
      handledBy = 'beforeinput';
      if (!bi || !bi.defaultPrevented) {
        // Browser default insertion (what Chromium/WebKit do when no JS handles it)
        handledBy = 'browser-default';
        const active = document.activeElement;
        if (active && (active.tagName === 'TEXTAREA' || active.tagName === 'INPUT')) {
          document.execCommand('insertText', false, data['text/plain'] || '');
        } else if (data['text/html']) {
          document.execCommand('insertHTML', false, data['text/html']);
        } else {
          document.execCommand('insertText', false, data['text/plain'] || '');
        }
      }
    }
    await QAUtil.sleep(300);
    return { handledBy };
  };

  ed.copyAll = async function () {
    await ed.selectAll(); await QAUtil.sleep(150);
    if (ed.customCopy) return ed.customCopy();
    const dt = new DataTransfer();
    const copy = QAUtil.clipboardEvent('copy', dt);
    target().dispatchEvent(copy);
    let html = dt.getData('text/html');
    let text = dt.getData('text/plain');
    let source = 'editor';
    if (!html && !copy.defaultPrevented) {
      // Browser default copy: serialize the DOM selection
      source = 'browser-selection';
      const sel = window.getSelection();
      if (sel && sel.rangeCount) {
        const div = document.createElement('div');
        div.appendChild(sel.getRangeAt(0).cloneContents());
        html = div.innerHTML;
        text = text || sel.toString();
      }
    }
    return { html, text, source };
  };

  window.QA = ed;
  window.QAReady = true;
};
