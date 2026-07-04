/**
 * jest.config.js — Softwareschmiede JS-Scaffold-Default.
 *
 * Schlanker, erweiterbarer Startpunkt. Erweitere ihn projekt-spezifisch
 * (transform/babel für JSX/TS, moduleNameMapper für CSS/Assets, coverage, …).
 *
 * PFLICHT, nicht entfernen (knowledge/js.md js/R07): die beiden
 * *IgnorePatterns für `.claude/worktrees/`. Parallele agent-flow-Worktrees
 * liegen physisch unter `.claude/worktrees/` und enthalten src/-Duplikate.
 * Ohne diesen Ausschluss zieht jest sie in Test-Auswahl UND Haste-Map, was
 * fremde (teils rote) Tests mitscannt und den geteilten Transform-Cache
 * vergiftet (dieselbe Datei mal CJS, mal ESM → "Cannot use import statement
 * outside a module" / "Test suite failed to run"). Akut-Fix: `jest --clearCache`.
 *
 * Nutzt das Projekt einen anderen Test-Runner (vitest, node:test), kann diese
 * Datei entfallen — übertrage die Worktree-Ignores dann sinngemäß in dessen Config.
 *
 * @type {import('jest').Config}
 */
const config = {
  testEnvironment: 'node',
  // Per-Datei via Docblock überschreibbar: @jest-environment jsdom

  // --- PFLICHT: parallele agent-flow-Worktrees aus Test-Auswahl UND Modul-Auflösung ausschließen (js/R07) ---
  testPathIgnorePatterns: ['/node_modules/', '/\\.claude/worktrees/'],
  modulePathIgnorePatterns: ['/\\.claude/worktrees/'],
};

export default config;
