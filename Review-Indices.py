"""
Interface web locale pour corriger les indices extraits par Claude Haiku.

Affiche chaque image avec les valeurs pré-remplies depuis le CSV,
permet de corriger nombre/lettre, marquer "pas de code", et naviguer
au clavier.

Usage:
    python Review-Indices.py <images_dir> <csv_file>

    Exemple:
    python Review-Indices.py frames_crop_400x320 indices.csv

Raccourcis clavier:
    Entrée          -> Image suivante (sauvegarde auto)
    Shift+Entrée    -> Image précédente
    Alt+N           -> Focus champ nombre
    Alt+L           -> Focus champ lettre
    Alt+X           -> Toggle case "pas de code"
"""

import csv
import http.server
import json
import os
import sys
import threading
import urllib.parse
import webbrowser

# ---------------------------------------------------------------------------
# Données globales
# ---------------------------------------------------------------------------
images: list[str] = []
images_dir: str = ""
csv_path: str = ""
data: dict[str, dict] = {}  # filename -> {number, letter, no_code, video_id, raw}

# ---------------------------------------------------------------------------
# Chargement / sauvegarde CSV
# ---------------------------------------------------------------------------

def load_csv(path: str) -> dict[str, dict]:
    """Charge le CSV existant dans un dict indexé par filename."""
    result = {}
    if not os.path.isfile(path):
        return result
    with open(path, encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            fn = row.get("filename", "")
            if fn:
                result[fn] = {
                    "video_id": row.get("video_id", ""),
                    "number": row.get("number", "?"),
                    "letter": row.get("letter", "?"),
                    "raw": row.get("raw", ""),
                    "no_code": row.get("no_code", "") == "true",
                }
    return result


def save_csv(path: str, images_list: list[str], data_dict: dict[str, dict]):
    """Sauvegarde les données dans le CSV."""
    fieldnames = ["video_id", "filename", "number", "letter", "no_code", "raw"]
    rows = []
    for fn in images_list:
        d = data_dict.get(fn, {})
        rows.append({
            "video_id": d.get("video_id", ""),
            "filename": fn,
            "number": d.get("number", "?"),
            "letter": d.get("letter", "?"),
            "no_code": "true" if d.get("no_code") else "",
            "raw": d.get("raw", ""),
        })
    # Trier par numéro
    def sort_key(r):
        try:
            return int(r["number"])
        except (ValueError, TypeError):
            return 99999
    rows.sort(key=sort_key)
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


# ---------------------------------------------------------------------------
# HTML de l'interface
# ---------------------------------------------------------------------------

HTML_PAGE = r"""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>Correction des indices</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #1a1a2e; color: #e0e0e0;
    display: flex; flex-direction: column; align-items: center;
    min-height: 100vh; padding: 20px;
  }
  h1 { font-size: 1.3em; margin-bottom: 10px; color: #8888cc; }
  .progress {
    font-size: 0.9em; color: #888; margin-bottom: 15px;
  }
  .progress-bar {
    width: 500px; height: 6px; background: #333; border-radius: 3px;
    margin-bottom: 20px; overflow: hidden;
  }
  .progress-bar-fill {
    height: 100%; background: #5c6bc0; transition: width 0.3s;
  }
  .image-container {
    border: 2px solid #333; border-radius: 8px; overflow: hidden;
    margin-bottom: 20px; background: #000;
    display: flex; align-items: center; justify-content: center;
    min-height: 200px;
  }
  .image-container img {
    max-width: 600px; max-height: 500px;
    image-rendering: pixelated;
  }
  .filename {
    font-size: 0.85em; color: #666; margin-bottom: 15px; font-family: monospace;
  }
  .form-row {
    display: flex; align-items: center; gap: 20px; margin-bottom: 15px;
  }
  .field { display: flex; align-items: center; gap: 8px; }
  .field label { font-weight: 600; font-size: 0.95em; }
  .field input[type="text"] {
    width: 80px; padding: 8px 12px; font-size: 1.2em; text-align: center;
    border: 2px solid #444; border-radius: 6px;
    background: #16213e; color: #e0e0e0;
    outline: none; transition: border-color 0.2s;
  }
  .field input[type="text"]:focus {
    border-color: #5c6bc0;
  }
  .field input[type="text"].modified {
    border-color: #ff9800;
  }
  .checkbox-field {
    display: flex; align-items: center; gap: 8px;
  }
  .checkbox-field input[type="checkbox"] {
    width: 20px; height: 20px; accent-color: #5c6bc0; cursor: pointer;
  }
  .checkbox-field label { cursor: pointer; }
  .buttons {
    display: flex; gap: 12px; margin-top: 10px;
  }
  button {
    padding: 10px 24px; font-size: 1em; border: none; border-radius: 6px;
    cursor: pointer; font-weight: 600; transition: background 0.2s;
  }
  .btn-prev { background: #333; color: #ccc; }
  .btn-prev:hover { background: #444; }
  .btn-prev:disabled { opacity: 0.3; cursor: default; }
  .btn-next { background: #5c6bc0; color: #fff; }
  .btn-next:hover { background: #7986cb; }
  .btn-save { background: #2e7d32; color: #fff; }
  .btn-save:hover { background: #388e3c; }
  .shortcuts {
    margin-top: 30px; font-size: 0.8em; color: #555; text-align: center;
    line-height: 1.8;
  }
  kbd {
    background: #2a2a3e; border: 1px solid #444; border-radius: 3px;
    padding: 2px 6px; font-family: monospace; font-size: 0.95em;
  }
  .status {
    position: fixed; bottom: 20px; right: 20px;
    background: #2e7d32; color: #fff; padding: 8px 16px;
    border-radius: 6px; font-size: 0.85em;
    opacity: 0; transition: opacity 0.3s;
    pointer-events: none;
  }
  .status.show { opacity: 1; }
  .stats {
    margin-top: 15px; font-size: 0.85em; color: #888;
  }
</style>
</head>
<body>

<h1>Correction des indices</h1>
<div class="progress" id="progress">0 / 0</div>
<div class="progress-bar"><div class="progress-bar-fill" id="progressBar"></div></div>

<div class="image-container">
  <img id="image" src="" alt="Image en cours">
</div>
<div class="filename" id="filename"></div>

<div class="form-row">
  <div class="field">
    <label for="numberInput" accesskey="n"><u>N</u>ombre :</label>
    <input type="text" id="numberInput" autocomplete="off" tabindex="1">
  </div>
  <div class="field">
    <label for="letterInput" accesskey="l"><u>L</u>ettre :</label>
    <input type="text" id="letterInput" maxlength="2" autocomplete="off" tabindex="2">
  </div>
  <div class="checkbox-field">
    <input type="checkbox" id="noCode" tabindex="3">
    <label for="noCode">Pas de code (Alt+<u>X</u>)</label>
  </div>
</div>

<div class="buttons">
  <button class="btn-prev" id="btnPrev" tabindex="4">&#9664; Precedent (Shift+Entree)</button>
  <button class="btn-next" id="btnNext" tabindex="5">Suivant &#9654; (Entree)</button>
  <button class="btn-save" id="btnSave" tabindex="6">Sauvegarder CSV</button>
</div>

<div class="stats" id="stats"></div>

<div class="shortcuts">
  <kbd>Entree</kbd> Suivant &nbsp;|&nbsp;
  <kbd>Shift+Entree</kbd> Precedent &nbsp;|&nbsp;
  <kbd>Alt+N</kbd> Nombre &nbsp;|&nbsp;
  <kbd>Alt+L</kbd> Lettre &nbsp;|&nbsp;
  <kbd>Alt+X</kbd> Pas de code &nbsp;|&nbsp;
  <kbd>Ctrl+S</kbd> Sauvegarder
</div>

<div class="status" id="status">Sauvegarde...</div>

<script>
let images = [];
let currentData = {};  // filename -> {number, letter, no_code}
let currentIndex = 0;

const img = document.getElementById('image');
const filenameEl = document.getElementById('filename');
const progressEl = document.getElementById('progress');
const progressBar = document.getElementById('progressBar');
const numberInput = document.getElementById('numberInput');
const letterInput = document.getElementById('letterInput');
const noCode = document.getElementById('noCode');
const btnPrev = document.getElementById('btnPrev');
const btnNext = document.getElementById('btnNext');
const btnSave = document.getElementById('btnSave');
const statusEl = document.getElementById('status');
const statsEl = document.getElementById('stats');

// Chargement initial
async function init() {
  const resp = await fetch('/api/data');
  const json = await resp.json();
  images = json.images;
  currentData = json.data;
  showImage(0);
}

function showImage(index) {
  if (index < 0 || index >= images.length) return;
  currentIndex = index;
  const fn = images[index];

  img.src = '/images/' + encodeURIComponent(fn) + '?t=' + Date.now();
  filenameEl.textContent = fn;
  progressEl.textContent = (index + 1) + ' / ' + images.length;
  progressBar.style.width = ((index + 1) / images.length * 100) + '%';

  const d = currentData[fn] || {};
  numberInput.value = (d.number && d.number !== '?') ? d.number : '';
  letterInput.value = (d.letter && d.letter !== '?') ? d.letter : '';
  noCode.checked = !!d.no_code;

  updateFieldStyles();
  btnPrev.disabled = (index === 0);

  // Focus sur le champ nombre
  numberInput.focus();
  numberInput.select();

  updateStats();
}

function updateFieldStyles() {
  const fn = images[currentIndex];
  const d = currentData[fn] || {};
  // Marquer en orange si la valeur a ete modifiee par rapport au raw
  numberInput.classList.toggle('modified',
    numberInput.value !== '' && d.raw && !d.raw.startsWith(numberInput.value));
  letterInput.classList.toggle('modified',
    letterInput.value !== '' && d.raw && !d.raw.endsWith(letterInput.value));
}

function saveCurrentFields() {
  const fn = images[currentIndex];
  if (!currentData[fn]) {
    currentData[fn] = { number: '?', letter: '?', no_code: false };
  }
  const num = numberInput.value.trim();
  const let_ = letterInput.value.trim().toUpperCase();
  currentData[fn].number = num || '?';
  currentData[fn].letter = let_ || '?';
  currentData[fn].no_code = noCode.checked;
}

function goNext() {
  saveCurrentFields();
  if (currentIndex < images.length - 1) {
    showImage(currentIndex + 1);
  }
}

function goPrev() {
  saveCurrentFields();
  if (currentIndex > 0) {
    showImage(currentIndex - 1);
  }
}

async function saveAll() {
  saveCurrentFields();
  statusEl.textContent = 'Sauvegarde...';
  statusEl.classList.add('show');
  try {
    await fetch('/api/save', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(currentData),
    });
    statusEl.textContent = 'CSV sauvegarde !';
  } catch (e) {
    statusEl.textContent = 'Erreur de sauvegarde !';
  }
  setTimeout(() => statusEl.classList.remove('show'), 2000);
}

function updateStats() {
  let filled = 0, noCodeCount = 0, missing = 0;
  for (const fn of images) {
    const d = currentData[fn];
    if (d && d.no_code) noCodeCount++;
    else if (d && d.number !== '?' && d.letter !== '?') filled++;
    else missing++;
  }
  statsEl.textContent =
    'Remplis : ' + filled + ' | Pas de code : ' + noCodeCount + ' | Manquants : ' + missing;
}

// Evenements
btnNext.addEventListener('click', goNext);
btnPrev.addEventListener('click', goPrev);
btnSave.addEventListener('click', saveAll);

noCode.addEventListener('change', () => {
  if (noCode.checked) {
    numberInput.value = '';
    letterInput.value = '';
  }
});

// Raccourcis clavier
document.addEventListener('keydown', (e) => {
  // Ctrl+S -> sauvegarder
  if (e.ctrlKey && e.key === 's') {
    e.preventDefault();
    saveAll();
    return;
  }
  // Alt+N -> focus nombre
  if (e.altKey && e.key === 'n') {
    e.preventDefault();
    numberInput.focus();
    numberInput.select();
    return;
  }
  // Alt+L -> focus lettre
  if (e.altKey && e.key === 'l') {
    e.preventDefault();
    letterInput.focus();
    letterInput.select();
    return;
  }
  // Alt+X -> toggle pas de code
  if (e.altKey && e.key === 'x') {
    e.preventDefault();
    noCode.checked = !noCode.checked;
    noCode.dispatchEvent(new Event('change'));
    return;
  }
  // Entree -> suivant, Shift+Entree -> precedent
  if (e.key === 'Enter') {
    e.preventDefault();
    if (e.shiftKey) goPrev();
    else goNext();
    return;
  }
});

// Auto-focus lettre apres saisie du nombre
numberInput.addEventListener('keydown', (e) => {
  if (e.key === 'Tab' && !e.shiftKey) {
    // Comportement normal du Tab
  }
});

// Forcer majuscule sur la lettre
letterInput.addEventListener('input', () => {
  letterInput.value = letterInput.value.toUpperCase();
});

init();
</script>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# Serveur HTTP
# ---------------------------------------------------------------------------

class ReviewHandler(http.server.BaseHTTPRequestHandler):
    """Gestionnaire HTTP pour l'interface de correction."""

    def log_message(self, format, *args):
        # Silencieux sauf erreurs
        if args and str(args[0]).startswith("4"):
            super().log_message(format, *args)

    def _send_json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html):
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/" or path == "/index.html":
            self._send_html(HTML_PAGE)
            return

        if path == "/api/data":
            # Renvoyer la liste d'images et les données
            api_data = {}
            for fn in images:
                d = data.get(fn, {})
                api_data[fn] = {
                    "number": d.get("number", "?"),
                    "letter": d.get("letter", "?"),
                    "no_code": d.get("no_code", False),
                    "raw": d.get("raw", ""),
                }
            self._send_json({"images": images, "data": api_data})
            return

        if path.startswith("/images/"):
            filename = urllib.parse.unquote(path[8:])
            # Nettoyer les query params
            filename = filename.split("?")[0]
            filepath = os.path.join(images_dir, filename)
            if os.path.isfile(filepath):
                with open(filepath, "rb") as f:
                    img_data = f.read()
                ext = os.path.splitext(filename)[1].lower()
                ct = "image/jpeg" if ext in (".jpg", ".jpeg") else "image/png"
                self.send_response(200)
                self.send_header("Content-Type", ct)
                self.send_header("Content-Length", str(len(img_data)))
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                self.wfile.write(img_data)
                return

        self.send_error(404)

    def do_POST(self):
        if self.path == "/api/save":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            try:
                updated = json.loads(body)
                # Mettre à jour les données
                for fn, vals in updated.items():
                    if fn not in data:
                        data[fn] = {
                            "video_id": fn.rsplit("_", 1)[0] if "_" in fn else os.path.splitext(fn)[0],
                            "raw": "",
                        }
                    data[fn]["number"] = vals.get("number", "?")
                    data[fn]["letter"] = vals.get("letter", "?")
                    data[fn]["no_code"] = vals.get("no_code", False)
                # Sauvegarder le CSV
                save_csv(csv_path, images, data)
                self._send_json({"ok": True})
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
            return

        self.send_error(404)


# ---------------------------------------------------------------------------
# Point d'entrée
# ---------------------------------------------------------------------------

def main():
    global images, images_dir, csv_path, data

    if len(sys.argv) < 3:
        print(f"Usage: python {sys.argv[0]} <images_dir> <csv_file>")
        sys.exit(1)

    images_dir = sys.argv[1]
    csv_path = sys.argv[2]

    if not os.path.isdir(images_dir):
        print(f"Erreur: le repertoire '{images_dir}' n'existe pas.")
        sys.exit(1)

    # Charger le CSV existant
    data = load_csv(csv_path)
    print(f"CSV charge: {len(data)} entree(s) depuis {csv_path}")

    # Lister les images
    images = sorted([
        f for f in os.listdir(images_dir)
        if f.lower().endswith((".jpg", ".jpeg", ".png"))
    ])

    if not images:
        print(f"Aucune image trouvee dans '{images_dir}'.")
        sys.exit(1)

    # Ajouter les images manquantes dans data
    for fn in images:
        if fn not in data:
            vid = fn.rsplit("_", 1)[0] if "_" in fn else os.path.splitext(fn)[0]
            data[fn] = {
                "video_id": vid,
                "number": "?",
                "letter": "?",
                "no_code": False,
                "raw": "",
            }

    print(f"{len(images)} image(s) trouvee(s)")

    port = 8080
    server = http.server.HTTPServer(("127.0.0.1", port), ReviewHandler)
    url = f"http://localhost:{port}"
    print(f"\nInterface disponible sur {url}")
    print("Ctrl+C pour arreter le serveur\n")

    # Ouvrir le navigateur
    threading.Timer(0.5, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServeur arrete.")
        server.server_close()


if __name__ == "__main__":
    main()
