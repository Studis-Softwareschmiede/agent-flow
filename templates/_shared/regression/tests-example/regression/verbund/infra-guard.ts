/**
 * @file infra-guard.ts — Infra-Leitplanken fuer ephemeral-infra-Regressions-Suiten.
 *
 * Spec: docs/specs/regression-runner.md — deckt AC7, AC8 (im Zusammenspiel mit
 * dem Fixture-/Teardown-Muster aus regression-playwright-conventions.md AC4).
 *
 * AC7 — Test-Ressourcen folgen ausnahmslos dem `rtest-*`-Namensschema;
 *   produktive Ressourcen sind per Allowlist unantastbar. `guardInfraResourceName`
 *   MUSS vor JEDER Provisionierung UND vor JEDEM Teardown eines Infra-Ressourcen-
 *   namens aufgerufen werden und bricht hart ab (wirft `InfraGuardrailError`),
 *   wenn:
 *     (a) der Name nicht mit `rtest-` beginnt, ODER
 *     (b) der Name mit einem Eintrag der uebergebenen Produktiv-Allowlist
 *         kollidiert — auch wenn er zufaellig dem `rtest-*`-Schema entspricht.
 *         Edge-Case aus der Spec: "rtest-*-Ressource kollidiert mit
 *         Allowlist-Eintrag" -> Abbruch, AC7 hat Vorrang, keine
 *         Produktiv-Beruehrung. Die Allowlist-Kollision wird deshalb VOR dem
 *         Namensschema-Check geprueft (siehe Reihenfolge unten).
 * AC8 — Garantiertes Cleanup: dieser Guard fuehrt selbst kein Cleanup aus (das
 *   ist Aufgabe des Fixture-try/finally-Musters, siehe infra.fixture.ts), aber
 *   er wird konsistent in BEIDEN Pfaden (provision + teardown) aufgerufen,
 *   damit ein Leitplanken-Verstoss niemals unbemerkt in einer der beiden
 *   Richtungen durchrutscht. Wirft der Guard beim Provisionieren, wurde noch
 *   keine Ressource angelegt (kein Teardown noetig); wirft er beim Teardown
 *   selbst (sollte praktisch nie vorkommen, da derselbe Name bereits beim
 *   Provisionieren gegengeprueft wurde), reicht der Fixture-`finally`-Block
 *   den Fehler weiter, ohne den Teardown-Versuch zu unterdruecken.
 *
 * Bewusst OHNE Fremd-Dependencies (kein `@playwright/test`-Import) — dadurch
 * sowohl aus Playwright-Fixtures als auch aus reinen Node-Smoke-Tests
 * importierbar (siehe tests/regression-runner/infra-leitplanken-smoke.sh im
 * agent-flow-Repo, das dieses Modul direkt gegenprueft).
 */

export const RTEST_PREFIX = 'rtest-';

export class InfraGuardrailError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InfraGuardrailError';
  }
}

export interface InfraGuardOptions {
  /** Namen produktiver Ressourcen, die niemals angefasst werden duerfen. */
  allowlist?: string[];
}

/**
 * Guard: vor JEDER Provisionierung/jedem Teardown einer Infra-Ressource
 * aufrufen. Wirft `InfraGuardrailError`, wenn der Ressourcenname gegen die
 * Infra-Leitplanken verstoesst (AC7). Kein Rueckgabewert bei Erfolg — der
 * Aufrufer faehrt einfach fort.
 */
export function guardInfraResourceName(name: string, options: InfraGuardOptions = {}): void {
  const allowlist = options.allowlist ?? [];

  // AC7-Edge-Case: Allowlist-Kollision hat Vorrang vor dem rtest-*-Check —
  // selbst ein Name, der (zufaellig) dem Testschema entspricht, darf niemals
  // eine produktive/allowlisted Ressource treffen.
  if (allowlist.includes(name)) {
    throw new InfraGuardrailError(
      `Leitplanken-Fehler: Ressource '${name}' kollidiert mit einem Allowlist-Eintrag ` +
        `(produktive Ressource) — AC7 hat Vorrang, keine Produktiv-Beruehrung.`
    );
  }

  if (!name.startsWith(RTEST_PREFIX)) {
    throw new InfraGuardrailError(
      `Leitplanken-Fehler: Ressourcenname '${name}' verstoesst gegen das ` +
        `verbindliche '${RTEST_PREFIX}*'-Namensschema (AC7).`
    );
  }
}
