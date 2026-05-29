// ============================================================
// STATE
// ============================================================
const STATE = {
  user: null,
  role: null,
  password: 'password',
  errorCount: 0,
  activityLog: [],
  files: [],
  apiBase: `http://${window.location.hostname}:30080`,
};

const USERS = {
  viewer: { role: 'ROLE_VIEWER',  label: 'Viewer' },
  editor: { role: 'ROLE_EDITOR',  label: 'Editor' },
  admin:  { role: 'ROLE_ADMIN',   label: 'Admin'  },
};

// ============================================================
// LOGIN
// ============================================================
function fillLogin(username) {
  document.getElementById('loginUser').value = username;
  document.getElementById('loginPass').value = 'password';
}

function doLogin() {
  const username = document.getElementById('loginUser').value.trim().toLowerCase();
  const password = document.getElementById('loginPass').value.trim();

  if (!USERS[username]) {
    document.getElementById('loginError').textContent = 'Unknown user. Try: viewer, editor, or admin.';
    return;
  }
  if (password !== 'password') {
    document.getElementById('loginError').textContent = 'Wrong password. Use: password';
    return;
  }

  STATE.user     = username;
  STATE.password = password;
  STATE.role     = USERS[username].role;

  document.getElementById('loginOverlay').style.display = 'none';
  document.getElementById('mainContent').style.display  = 'block';

  updateUserUI();
  loadFiles();
  checkApiStatus();
  logActivity(`Signed in as ${username}`, 'blue', '200');

  if (username === 'admin') {
    document.getElementById('navAdmin').style.display = 'flex';
  }

  // Hide upload zone for viewers
  if (STATE.role === 'ROLE_VIEWER') {
    document.getElementById('uploadZone').classList.add('hidden');
  }
}

function doLogout() {
  STATE.user = null; STATE.role = null; STATE.errorCount = 0; STATE.files = [];
  document.getElementById('loginOverlay').style.display = 'flex';
  document.getElementById('mainContent').style.display  = 'none';
  document.getElementById('navAdmin').style.display     = 'none';
  document.getElementById('loginError').textContent     = '';
  document.getElementById('activityList').innerHTML     = '<div style="text-align:center;color:var(--text-muted);padding:40px;font-size:0.88rem">No activity yet.</div>';
  showPanel('overview', document.querySelector('.nav-item'));
}

function updateUserUI() {
  const info = USERS[STATE.user];
  document.getElementById('userName').textContent    = STATE.user;
  document.getElementById('userAvatar').textContent  = STATE.user[0].toUpperCase();

  const badge = document.getElementById('userRoleBadge');
  badge.textContent  = info.label;
  badge.className    = 'user-role ' + (
    STATE.user === 'admin'  ? 'role-admin'  :
    STATE.user === 'editor' ? 'role-editor' : 'role-viewer'
  );

  document.getElementById('metricRole').textContent      = STATE.user;
  document.getElementById('metricRoleBadge').textContent = info.role;
}

// ============================================================
// NAVIGATION
// ============================================================
const pageTitles = {
  overview: ['Overview',    'System metrics and status'],
  files:    ['Files (S3)',  'Manage documents in LocalStack S3'],
  admin:    ['Admin Panel', 'Restricted endpoint — ROLE_ADMIN only'],
  activity: ['Activity Log','Session requests and events'],
};

function showPanel(name, btn) {
  document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(b => b.classList.remove('active'));
  document.getElementById('panel-' + name).classList.add('active');
  if (btn) btn.classList.add('active');

  const [title, sub] = pageTitles[name] || ['Dashboard', ''];
  document.getElementById('pageTitle').textContent = title;
  document.getElementById('pageSub').textContent   = sub;

  if (name === 'files') loadFiles();
}

// ============================================================
// API HELPERS
// ============================================================
function apiHeaders() {
  return {
    'Authorization': 'Basic ' + btoa(`${STATE.user}:${STATE.password}`),
    'Content-Type': 'application/json',
  };
}

async function apiFetch(method, path, body) {
  const opts = { method, headers: apiHeaders() };
  if (body) { delete opts.headers['Content-Type']; opts.body = body; }
  try {
    const res = await fetch(STATE.apiBase + path, opts);
    return res;
  } catch {
    return null;
  }
}

// ============================================================
// API STATUS CHECK
// ============================================================
async function checkApiStatus() {
  const statusEl      = document.getElementById('metricStatus');
  const statusBadge   = document.getElementById('metricStatusBadge');

  try {
    const res = await fetch(STATE.apiBase + '/actuator/health');
    if (res.ok) {
      statusEl.textContent      = '🟢';
      statusBadge.textContent   = 'API Online';
      statusBadge.className     = 'metric-badge badge-green';
    } else {
      throw new Error();
    }
  } catch {
    statusEl.textContent    = '🔴';
    statusBadge.textContent = 'Demo Mode';
    statusBadge.className   = 'metric-badge badge-red';
  }
}

// ============================================================
// FILES
// ============================================================
async function loadFiles() {
  const tbody = document.getElementById('filesTableBody');
  tbody.innerHTML = '<tr><td colspan="3" style="text-align:center;color:var(--text-muted);padding:24px">Loading...</td></tr>';

  const res = await apiFetch('GET', '/files');

  if (!res) {
    // Demo mode — show mock files
    STATE.files = ['report-2025.pdf', 'architecture.png', 'config-backup.yml', 'audit-log.txt'];
    renderFiles(STATE.files);
    document.getElementById('metricFiles').textContent = STATE.files.length;
    return;
  }

  if (res.status === 403) {
    STATE.errorCount++;
    updateErrorCount();
    logActivity('GET /files → 403 Forbidden', 'red', '403');
    tbody.innerHTML = '<tr><td colspan="3"><div class="forbidden-banner"><span class="forbidden-icon">🚫</span><div><h4>403 Forbidden</h4><p>Your role does not have access to list files.</p></div></div></td></tr>';
    return;
  }

  const data = await res.json();
  STATE.files = data;
  document.getElementById('metricFiles').textContent = data.length;
  logActivity(`GET /files → ${data.length} files`, 'green', '200');
  renderFiles(data);
}

function renderFiles(files) {
  const tbody = document.getElementById('filesTableBody');
  if (!files.length) {
    tbody.innerHTML = '<tr><td colspan="4" style="text-align:center;color:var(--text-muted);padding:40px">No files in bucket. Upload something!</td></tr>';
    return;
  }
  const ext2icon = { pdf:'📄', png:'🖼️', jpg:'🖼️', gif:'🖼️', yml:'⚙️', yaml:'⚙️', txt:'📝', json:'🗂️', zip:'📦' };
  const viewable = ['txt', 'json', 'yml', 'yaml', 'png', 'jpg', 'gif', 'pdf'];
  tbody.innerHTML = files.map(name => {
    const ext  = name.split('.').pop().toLowerCase();
    const icon = ext2icon[ext] || '📁';
    const canView = viewable.includes(ext);
    const base = STATE.apiBase;
    const auth = btoa(`${STATE.user}:${STATE.password}`);
    return `<tr>
      <td><span class="file-icon">${icon}</span><span class="file-name">${name}</span></td>
      <td style="color:var(--text-muted)">${ext.toUpperCase()}</td>
      <td style="color:var(--text-muted)">S3</td>
      <td style="display:flex;gap:8px;align-items:center">
        ${canView ? `<button class="file-btn view-btn" onclick="viewFile('${name}')">👁 Просмотр</button>` : ''}
        <button class="file-btn download-btn" onclick="downloadFile('${name}')">⬇ Скачать</button>
      </td>
    </tr>`;
  }).join('');
}

async function downloadFile(filename) {
  logActivity(`GET /files/download/${filename}`, 'blue', '200');
  const res = await apiFetch('GET', `/files/download/${encodeURIComponent(filename)}`);
  if (!res || !res.ok) {
    showToast('❌ Ошибка скачивания', 'error');
    return;
  }
  const blob = await res.blob();
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href     = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
  showToast('⬇ Скачивается: ' + filename, 'success');
}

async function viewFile(filename) {
  const ext = filename.split('.').pop().toLowerCase();
  const res = await apiFetch('GET', `/files/view/${encodeURIComponent(filename)}`);
  if (!res || !res.ok) {
    showToast('❌ Ошибка открытия файла', 'error');
    return;
  }
  logActivity(`GET /files/view/${filename}`, 'blue', '200');

  if (['png','jpg','gif'].includes(ext)) {
    const blob = await res.blob();
    const url  = URL.createObjectURL(blob);
    openPreviewModal(filename, `<img src="${url}" style="max-width:100%;border-radius:8px">`);
  } else {
    const text = await res.text();
    openPreviewModal(filename, `<pre style="white-space:pre-wrap;word-break:break-all;color:var(--text-primary);font-size:0.85rem">${escapeHtml(text)}</pre>`);
  }
  showToast('👁 Открыт: ' + filename, 'info');
}

function escapeHtml(str) {
  return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function openPreviewModal(title, content) {
  let modal = document.getElementById('previewModal');
  if (!modal) {
    modal = document.createElement('div');
    modal.id = 'previewModal';
    modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.75);z-index:9999;display:flex;align-items:center;justify-content:center;padding:24px';
    modal.innerHTML = `
      <div style="background:var(--glass-bg);backdrop-filter:blur(20px);border:1px solid var(--glass-border);border-radius:16px;max-width:800px;width:100%;max-height:80vh;overflow:auto;padding:24px">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px">
          <span id="previewTitle" style="font-weight:600;color:var(--text-primary)"></span>
          <button onclick="document.getElementById('previewModal').remove()" style="background:var(--red);border:none;color:#fff;border-radius:8px;padding:6px 14px;cursor:pointer">✕ Закрыть</button>
        </div>
        <div id="previewContent"></div>
      </div>`;
    document.body.appendChild(modal);
    modal.addEventListener('click', e => { if (e.target === modal) modal.remove(); });
  }
  document.getElementById('previewTitle').textContent = title;
  document.getElementById('previewContent').innerHTML = content;
}

async function uploadFile(input) {
  const file = input.files[0];
  if (!file) return;

  if (STATE.role === 'ROLE_VIEWER') {
    STATE.errorCount++;
    updateErrorCount();
    logActivity(`POST /files/upload → 403 Forbidden (${file.name})`, 'red', '403');
    showToast('🚫 403 Forbidden — VIEWER cannot upload files', 'error');
    input.value = '';
    return;
  }

  const formData = new FormData();
  formData.append('file', file);

  showToast('⬆️ Uploading ' + file.name + '...', 'info');
  const res = await apiFetch('POST', '/files/upload', formData);

  if (!res) {
    // Demo mode
    STATE.files.push(file.name);
    document.getElementById('metricFiles').textContent = STATE.files.length;
    logActivity(`POST /files/upload → 200 OK (${file.name}) [demo]`, 'green', '201');
    showToast('✅ Uploaded: ' + file.name + ' (demo mode)', 'success');
    renderFiles(STATE.files);
    input.value = '';
    return;
  }

  if (res.status === 403) {
    STATE.errorCount++;
    updateErrorCount();
    logActivity(`POST /files/upload → 403 Forbidden (${file.name})`, 'red', '403');
    showToast('🚫 403 Forbidden — not enough permissions', 'error');
  } else if (res.ok) {
    logActivity(`POST /files/upload → 201 Created (${file.name})`, 'green', '201');
    showToast('✅ Uploaded: ' + file.name, 'success');
    loadFiles();
  }
  input.value = '';
}

// Drag & drop
const zone = document.getElementById('uploadZone');
if (zone) {
  zone.addEventListener('dragover', e => { e.preventDefault(); zone.classList.add('drag-over'); });
  zone.addEventListener('dragleave', () => zone.classList.remove('drag-over'));
  zone.addEventListener('drop', e => {
    e.preventDefault();
    zone.classList.remove('drag-over');
    if (e.dataTransfer.files[0]) {
      const fakeInput = { files: e.dataTransfer.files };
      uploadFile(fakeInput);
    }
  });
}

// ============================================================
// ADMIN ENDPOINT
// ============================================================
async function fetchAdminSecret() {
  const resultEl = document.getElementById('adminResult');
  const preEl    = document.getElementById('adminResultPre');

  const res = await apiFetch('GET', '/admin/secret');

  if (!res) {
    // Demo mode
    if (STATE.user === 'admin') {
      resultEl.style.display = 'block';
      preEl.textContent = JSON.stringify({ status: 'ok', secret: 'admin-only-data' }, null, 2);
      logActivity('GET /admin/secret → 200 OK [demo]', 'green', '200');
      showToast('✅ Secret data retrieved (demo mode)', 'success');
    } else {
      STATE.errorCount++;
      updateErrorCount();
      logActivity('GET /admin/secret → 403 Forbidden', 'red', '403');
      showToast('🚫 403 Forbidden — ADMIN only', 'error');
    }
    return;
  }

  if (res.status === 403) {
    STATE.errorCount++;
    updateErrorCount();
    logActivity('GET /admin/secret → 403 Forbidden', 'red', '403');
    showToast('🚫 403 Forbidden — ADMIN only', 'error');
    resultEl.style.display = 'none';
  } else {
    const data = await res.json();
    resultEl.style.display = 'block';
    preEl.textContent = JSON.stringify(data, null, 2);
    logActivity('GET /admin/secret → 200 OK', 'green', '200');
    showToast('✅ Secret data retrieved', 'success');
  }
}

// ============================================================
// RBAC QUICK TEST
// ============================================================
async function testEndpoint(method, path) {
  const resultEl = document.getElementById('testResult');
  resultEl.textContent = `→ ${method} ${path} ...`;

  let status, color;

  if (!STATE.user) return;

  // Determine expected result based on role
  const allowed = canAccess(method, path);

  const res = await apiFetch(method, path);
  if (res) {
    status = res.status;
  } else {
    // Demo mode — simulate based on RBAC rules
    status = allowed ? 200 : 403;
  }

  color = status === 403 ? 'var(--red)' : 'var(--green)';

  if (status === 403) {
    STATE.errorCount++;
    updateErrorCount();
    logActivity(`${method} ${path} → 403`, 'red', '403');
  } else {
    logActivity(`${method} ${path} → ${status}`, 'green', String(status));
  }

  resultEl.innerHTML = `<span style="color:${color}; font-weight:700">${status} ${status===403?'Forbidden':'OK'}</span>  ${method} ${path}  [user: ${STATE.user}, role: ${STATE.role}]`;
}

function canAccess(method, path) {
  if (path === '/files' && method === 'GET') return true;
  if (path === '/files/upload' && method === 'POST') return STATE.role !== 'ROLE_VIEWER';
  if (path === '/admin/secret' && method === 'GET') return STATE.role === 'ROLE_ADMIN';
  return false;
}

// ============================================================
// UTILS
// ============================================================
function updateErrorCount() {
  document.getElementById('metricErrors').textContent = STATE.errorCount;
}

function refreshData() {
  checkApiStatus();
  loadFiles();
  showToast('↻ Data refreshed', 'info');
}

function logActivity(msg, color, statusCode) {
  const dotClass = { green:'dot-green', red:'dot-red', blue:'dot-blue', yellow:'dot-yellow' }[color] || 'dot-blue';
  const statusClass = { '200':'status-200', '201':'status-201', '403':'status-403' }[statusCode] || 'status-200';

  const now = new Date().toLocaleTimeString();
  const item = { msg, dotClass, statusCode, statusClass, time: now };
  STATE.activityLog.unshift(item);

  const list = document.getElementById('activityList');
  if (list.querySelector('div[style]')) list.innerHTML = '';

  const el = document.createElement('div');
  el.className = 'activity-item';
  el.innerHTML = `
    <div class="activity-dot ${dotClass}"></div>
    <div class="activity-info">
      <div class="activity-msg">${msg}</div>
      <div class="activity-time">${now}</div>
    </div>
    <span class="activity-status ${statusClass}">${statusCode}</span>
  `;
  list.prepend(el);
}

function clearLog() {
  STATE.activityLog = [];
  document.getElementById('activityList').innerHTML =
    '<div style="text-align:center;color:var(--text-muted);padding:40px;font-size:0.88rem">Log cleared.</div>';
}

function showToast(msg, type = 'info') {
  const icons = { success:'✅', error:'🚫', info:'ℹ️' };
  const container = document.getElementById('toastContainer');
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.innerHTML = `<span>${icons[type]}</span> ${msg}`;
  container.appendChild(toast);
  setTimeout(() => toast.remove(), 3500);
}

// Enter key on login
document.getElementById('loginPass').addEventListener('keydown', e => {
  if (e.key === 'Enter') doLogin();
});
document.getElementById('loginUser').addEventListener('keydown', e => {
  if (e.key === 'Enter') doLogin();
});
