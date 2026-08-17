// IMPORTANT : tous les appels API et l'iframe terminal utilisent des chemins
// RELATIFS (pas de "/" en tête). L'add-on est servi derrière un préfixe
// dynamique injecté par le Supervisor (ingress) ; un chemin absolu casserait
// la navigation dès qu'on n'est pas exactement à la racine du domaine.

const listEl = document.getElementById('script-list');
let cm = null;
let currentName = null;

async function api(path, opts) {
  const res = await fetch(path, opts);
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`${res.status} : ${txt}`);
  }
  return res.status === 204 ? null : res.json();
}

async function refresh() {
  const scripts = await api('api/scripts');
  listEl.innerHTML = '';
  for (const s of scripts) {
    const row = document.createElement('div');
    row.className = 'script-row';
    row.innerHTML = `
      <span class="name">${s.name}</span>
      <span class="badge ${s.running ? 'on' : 'off'}">${s.running ? 'actif' : 'arrêté'}</span>
      ${s.running && s.port ? `<a class="port-link" href="s/${s.name.replace(/\.py$/, '')}/" target="_blank">/s/${s.name.replace(/\.py$/, '')}/</a>` : ''}
      <button data-act="edit">Éditer</button>
      <button data-act="logs">Logs</button>
      <button data-act="toggle">${s.running ? 'Stop' : 'Start'}</button>
      <button data-act="delete">🗑</button>
    `;
    row.querySelector('[data-act=edit]').onclick = () => openEditor(s.name);
    row.querySelector('[data-act=logs]').onclick = () => showLogs(s.name);
    row.querySelector('[data-act=toggle]').onclick = () => toggleScript(s.name, s.running);
    row.querySelector('[data-act=delete]').onclick = () => deleteScript(s.name);
    listEl.appendChild(row);
  }
}

async function toggleScript(name, running) {
  try {
    await api(`api/scripts/${encodeURIComponent(name)}/${running ? 'stop' : 'start'}`, { method: 'POST' });
  } catch (e) {
    alert(e.message);
  }
  refresh();
}

async function deleteScript(name) {
  if (!confirm(`Supprimer ${name} ?`)) return;
  try {
    await api(`api/scripts/${encodeURIComponent(name)}`, { method: 'DELETE' });
  } catch (e) {
    alert(e.message);
  }
  refresh();
}

async function showLogs(name) {
  const logs = await fetch(`api/scripts/${encodeURIComponent(name)}/logs`).then(r => r.text());
  alert(logs || '(vide)');
}

// ---- Éditeur (modale CodeMirror) ----
const modal = document.getElementById('editor-modal');
const nameInput = document.getElementById('editor-name');
const needsPortInput = document.getElementById('editor-needs-port');
const autostartInput = document.getElementById('editor-autostart');
const statusSpan = document.getElementById('editor-status');

function initCM() {
  if (cm) return cm;
  cm = CodeMirror(document.getElementById('editor-cm'), {
    mode: 'python',
    theme: 'dracula',
    lineNumbers: true,
    indentUnit: 4,
    tabSize: 4,
  });
  return cm;
}

async function openEditor(name) {
  initCM();
  currentName = name;
  nameInput.value = name;
  nameInput.disabled = !!name;
  statusSpan.textContent = '';
  if (name) {
    const data = await api(`api/scripts/${encodeURIComponent(name)}`);
    cm.setValue(data.content);
  } else {
    cm.setValue('#!/usr/bin/env python3\n\n');
  }
  modal.classList.remove('hidden');
  setTimeout(() => cm.refresh(), 50);
}

document.getElementById('btn-new').onclick = () => openEditor(null);
document.getElementById('btn-refresh').onclick = refresh;
document.getElementById('editor-close').onclick = () => modal.classList.add('hidden');

document.getElementById('editor-save').onclick = async () => {
  const name = nameInput.value.trim();
  if (!name.endsWith('.py')) { alert('Le nom doit finir par .py'); return; }
  const content = cm.getValue();
  try {
    if (currentName) {
      await api(`api/scripts/${encodeURIComponent(currentName)}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ content }),
      });
    } else {
      await api('api/scripts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name, content,
          needs_port: needsPortInput.checked,
          autostart: autostartInput.checked,
        }),
      });
    }
    statusSpan.textContent = 'Enregistré ✓';
    refresh();
  } catch (e) {
    statusSpan.textContent = 'Erreur : ' + e.message;
  }
};

// ---- Onglets ----
document.getElementById('tab-scripts').onclick = () => switchTab('scripts');
document.getElementById('tab-terminal').onclick = () => switchTab('terminal');
function switchTab(tab) {
  for (const el of document.querySelectorAll('.tab')) el.classList.remove('active');
  for (const el of document.querySelectorAll('.view')) el.classList.remove('active');
  document.getElementById(`tab-${tab}`).classList.add('active');
  document.getElementById(`view-${tab}`).classList.add('active');
}

refresh();
setInterval(refresh, 5000);
