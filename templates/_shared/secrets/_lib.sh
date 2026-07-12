#!/usr/bin/env bash
# Gemeinsame Helfer — NICHT direkt ausführen, nur via source.
#
# GPG-Passphrase-Auflösung (PER-APP-Modell):
#   Jede App hat ihre EIGENE Passphrase. Sie kommt vorrangig aus der Umgebung
#   ($GPG_PASSPHRASE) — genau die injiziert der Deploy-Orchestrator (dev-gui) beim
#   `docker run -e GPG_PASSPHRASE=…`, gelesen aus dem Bitwarden-Item `deploy-gpg-<app>`.
#   Der Laufzeit-Entrypoint nutzt AUSSCHLIESSLICH $GPG_PASSPHRASE; diese lokalen
#   Scripts richten sich daran aus.
#
#   Auflösungs-Reihenfolge (encrypt/decrypt/load-env, identisch):
#     $GPG_PASSPHRASE  >  $GPG_PASS_FILE (explizit, app-eigen)  >  interaktiver Prompt
#
#   BEWUSST ENTFERNT (Breaking Change): die früher automatisch bevorzugten GETEILTEN
#   Dateien /etc/softwareschmiede/gpg.pass und ~/.config/softwareschmiede/gpg.pass.
#   Sie hatten Vorrang vor $GPG_PASSPHRASE und führten dazu, dass eine App
#   versehentlich mit der FALSCHEN (geteilten) Passphrase statt ihrer eigenen
#   ver-/entschlüsselt wurde. Wer wirklich eine Datei nutzen will, setzt $GPG_PASS_FILE
#   explizit auf eine APP-eigene Datei (keine Auto-Erkennung geteilter Org-Dateien mehr).

# Liefert einen explizit gesetzten, lesbaren Passphrase-DATEIPFAD ($GPG_PASS_FILE)
# oder schlägt fehl (return 1). KEINE Auto-Erkennung geteilter Org-Dateien.
resolve_pass_file() {
  local f="${GPG_PASS_FILE:-}"
  [[ -n "$f" && -r "$f" ]] && { printf '%s' "$f"; return 0; }
  return 1
}
