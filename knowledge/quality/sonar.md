# Knowledge Pack — Static Analysis (SonarQube Cloud / SonarQube Server)

> Wie die Fabrik statische Code-Analyse **scant** und die Behebung **steuert**. Optional pro Projekt (`profile.sonar.edition`). Referenziert von `new-project`, `adopt`, `flow` + den `sonar.yml`-Templates.

last_trained: 2026-06-15

## 0. Grundprinzip — „Clean as You Code"
Sonar wird NICHT benutzt, um die gesamte Alt-Last zu fixen (das ist der Anfänger-Fehler: bei einem 5k-LOC-Repo zeigt Sonar schnell 400+ Findings, davon ~98 % Code Smells). Stattdessen:
- **Neuer Code muss sauber sein** — das Quality Gate misst nur das **New-Code-Window**. Durchgesetzt wird das primär durch den `reviewer` (Pack-Regeln) pro PR; Sonar selbst läuft periodisch (§1a, kein per-PR-Blockgate by default) und macht New-Code-Regressionen sichtbar.
- **Alt-Last bleibt getrackte Schuld** (im Sonar-Dashboard sichtbar), wird NICHT massenhaft in Board-Items gewandelt. Behebung opportunistisch (wenn man die Datei eh anfasst) — und Framework-Migrationen (z.B. Spring-Boot/Angular-Major) räumen Smells ohnehin großflächig weg.
- **Beim `adopt` nur die Spitze als Backlog:** nur `BLOCKER`/`CRITICAL` vom Typ `BUG` und `VULNERABILITY` als **gedeckelte** Board-Items (Cap z.B. 15) ziehen — KEINE Code-Smells als Issues.

## 1. Free-Plan-Grenzen (prägen die Edition-Wahl)

> **sonar/R01** — Offizielle Produkt-Umbenennung (Okt 2024): **SonarCloud** → **SonarQube Cloud**, **SonarQube Community Edition** → **SonarQube Community Build**, SonarQube (self-hosted) → **SonarQube Server**, SonarLint → SonarQube for IDE. Docs, API-URLs und GitHub-Actions-Namen verwenden die neuen Bezeichnungen. Quelle: [Sonar Press Release (2024-10-29)](https://www.sonarsource.com/company/press-releases/sonar-streamlines-product-naming-to-reflect-core-mission-of-code-quality-and-security/)

| Edition | Kosten | Sichtbarkeit | Branch/PR-Analyse |
|---|---|---|---|
| **SonarQube Cloud (Free)** | gratis | **nur PUBLIC Repos** | ja (PR-Decoration + Branch) |
| SonarQube Cloud (paid) | $/LOC | privat ok | ja |
| **SonarQube Community Build (self-host)** | gratis | beliebig (auch privat) | **nein — nur Main-Branch**, keine PR-Decoration |
| SonarQube Server Developer+ | $ | beliebig | ja |

**Auto-Wahl nach Repo-Sichtbarkeit (Fabrik-Default):**
- Repo **public** → `edition: sonarqube-cloud` (bisher `sonarcloud`).
- Repo **private** → `edition: sonarqube-ce` (self-host) **oder** `edition: none`, wenn keine SonarQube-Instanz da ist.
- Unklar/kein Setup → `edition: none` (nichts bricht).

Die *Edition* bestimmt **wo** analysiert wird; die *Kadenz* (wann) ist davon entkoppelt — siehe §1a. Der Fabrik-Default ist monatlich + manuell für **beide** Editionen (kein PR-Trigger), daher spielt die CE-Einschränkung „nur Main-Branch" praktisch keine Rolle mehr.

## 1a. Trigger-Kadenz (Fabrik-Default: monatlich + manuell)
**Bewusst KEIN `push`/`pull_request`-Trigger.** Der re-analysiert bei jedem Push auf einen offenen PR-Branch (`synchronize`-Event) plus jedem Merge → brennt GitHub-Actions-Minuten (Org-Budget) und erzeugt Analyse-Rauschen, bei mehreren Repos überbordend. Stattdessen:
- **`schedule` (cron `0 4 1 * *`)** — 1× pro Monat eine Baseline-Analyse des Default-Branch.
- **`workflow_dispatch`** — Handstart jederzeit: Actions-Tab → „Run workflow", oder `gh workflow run "SonarQube Analysis"`.
- **`concurrency: cancel-in-progress`** — überlappender Schedule+Handstart → nur der letzte Lauf zählt.

**Konsequenzen (bewusst akzeptiert):**
- **Kein per-PR-Blockgate.** Die Pre-Merge-Qualität trägt der `reviewer` über die Sprach-/Framework-Pack-Regeln (dort leben die destillierten Sonar-Lessons, z.B. `java/R11–R15`). Sonar ist **periodischer Monitor**, nicht Teil des Hot-Path jeder Änderung.
- **Futter für den Lern-Loop.** Die monatliche Baseline ist genau die Quelle, die `/retro --sonar` (②) erntet → Findings fließen in die Packs zurück (`agents/retro.md` Sonar-Harvest-Modus).
- **Vor einem kritischen Merge** kann man Sonar manuell anstoßen (`workflow_dispatch`) und das Ergebnis prüfen — opt-in statt erzwungen.
- **Opt-in strenger:** Ein Repo, das ein echtes per-PR-Gate will und die Kosten akzeptiert, ergänzt `pull_request: { branches: [main, master] }` im `on:`-Block (dann greift §4 wieder als Blockgate). Nicht der Default.
- Scheduled-Workflows laufen nur auf dem Default-Branch; GitHub pausiert sie nach 60 Tagen Repo-Inaktivität automatisch (einmal manuell re-aktivieren).

## 2. profile.sonar — Schema
```yaml
sonar:
  edition: none            # none | sonarqube-cloud | sonarqube-ce
  organization: ""         # SonarQube-Cloud-Org (nur sonarqube-cloud)
  project_key: ""          # z.B. <Org>_<repo>
  host_url: ""             # sonarqube-cloud: https://sonarqube.io · ce: https://<deine-instanz>
```
Token kommt NIE ins Profil/Repo → **GitHub-Org-Secret `SONAR_TOKEN`** (org-weit, ein Token für alle Repos). Workflow-Guard überspringt sauber, wenn das Secret fehlt (Forks/Contributor brechen nicht).

## 3. Scanner-Runtime ≠ App-Runtime (häufige Falle!)

> **sonar/R02** — **sonar-maven-plugin 5.x ersetzt 3.11.x** (neueste Version: 5.7.0.6970, 2026-05-27). Ab v5.0 enthält das Plugin **JRE Auto-Provisioning**: bei Verbindung zu SonarQube Server ≥ 10.6 oder SonarQube Cloud lädt der Scanner automatisch ein JDK 17 herunter — `setup-java 17` als separater Step entfällt. Kein Breaking Change für bestehende Setups (auto-provisioning default-aktiv, abschaltbar via `-Dsonar.scanner.skipJreProvisioning=true`). Quellen: [SonarSource Maven Scanner Releases](https://github.com/SonarSource/sonar-scanner-maven/releases) · [JRE Auto-Provisioning Announcement](https://community.sonarsource.com/t/sonarscanner-for-maven-5-0-automatic-jre-provisioning/130002)

> **sonar/R03** — **Scanner-Java-Anforderung: Java 17 deprecated, Java 21 wird Pflicht.** Java 17 als Scanner-Runtime ist ab SonarQube Server 2026.1 LTA deprecated; Support endet mit 2026.3. Ab 2026.4 (Juli 2026) ist **Java 21** Pflicht, wenn Auto-Provisioning deaktiviert ist. Mit Auto-Provisioning (sonar-maven-plugin ≥ 5.0, §R02) wird der JDK automatisch verwaltet — kein manuelles Upgrade nötig. Quelle: [General Requirements — SonarQube Server](https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/scanners/scanner-environment/general-requirements)

**SonarQube Cloud / SonarQube Server erwartet einen Java-Scanner** — auch wenn die App auf Java 11/8 läuft. Der Scanner-Schritt muss daher ggf. auf einem ANDEREN JDK laufen als Build/Test:
- **Java-Projekt (Maven):** Build+Test auf `profile.java.version` (z.B. 11), dann `sonar-maven-plugin:5.7.0.6970:sonar` (NICHT 3.9.x/3.11.x; v5.0+ mit JRE-Auto-Provisioning benötigt keinen separaten `setup-java 17`-Step mehr). Reuse von `target/` aus dem verify-Step.
- **JS/Angular/Flutter/HTML:** kein Maven-Plugin → **`sonar-scanner` CLI** (offizielle `SonarSource/sonarqube-scan-action`) + `sonar-project.properties` mit `sonar.sources`, `sonar.projectKey`, `sonar.organization`. Coverage via lcov (`sonar.javascript.lcov.reportPaths`).
Die `EnvironmentInformation class file version 61.0`-Meldung = Scanner braucht Java 17 (mit Auto-Provisioning automatisch bereitgestellt).

## 4. Sonar in `/flow` — periodischer Monitor, kein per-PR-Blockgate
Beim Fabrik-Default (monatlich + manuell, §1a) gibt es **keinen** per-PR-`sonar.yml`-Run, auf den `/flow` warten könnte. Daher:
- **`/flow` wartet NICHT auf Sonar und blockiert nicht darauf.** Die Pre-Merge-Qualität trägt der `reviewer` (Pack-Regeln) + `tester`. Sonar misst die Qualität periodisch und füttert `/retro --sonar`.
- **Informativ vor einem kritischen Merge** (optional, best-effort): den letzten Default-Branch-Status abrufen `GET {host}/api/qualitygates/project_status?projectKey=<key>` (`projectStatus.status` OK/ERROR) und im PR vermerken — NICHT blockierend. Token: `SONAR_TOKEN` aus dem env (read-scope), für public-SonarQube-Cloud auch ohne Token lesbar.

**Opt-in per-PR-Blockgate** (nur Repos, die den `pull_request`-Trigger explizit ergänzt haben, §1a): Nach `Test-Gate: PASS` + PR-Öffnen auf den PR-Run warten (`gh run watch`, kurzes Timeout) → `GET …project_status?projectKey=<key>&pullRequest=<n>` → bei `ERROR` (New-Code-Gate gerissen) als `FINDINGS` zurück an den `coder` (zählt zum Schleifenschutz), sonst landen. Best-effort: Gate nicht abrufbar → nicht blockieren, melden.

## 5. Reviewer/Tester-Hinweise
- Der `tester` ersetzt NICHT die Sonar-Analyse (Funktion vs. statische Qualität sind getrennt).
- `sonar.yml` darf den restlichen CI-Flow NIE blockieren, wenn `SONAR_TOKEN` fehlt (Guard).
- Coverage: ohne Coverage-Report sieht Sonar **0 %**. Wenn Coverage zählen soll: Java→jacoco (`jacoco-maven-plugin` + `sonar.coverage.jacoco.xmlReportPaths`), JS→lcov. Sonst bleibt Coverage blind (akzeptabel, aber dokumentieren).

## Reviewer-Checklist (sonar)
- [ ] `profile.sonar.edition` gesetzt + passend zur Repo-Sichtbarkeit (public→`sonarqube-cloud`, private→`sonarqube-ce`/`none`)? (`sonarcloud` = alter Name, Ablösung durch `sonarqube-cloud` — sonar/R01)
- [ ] Token NUR als Org-Secret `SONAR_TOKEN`, nirgends im Repo/Profil?
- [ ] `sonar.yml` hat Non-blocking-Token-Guard?
- [ ] Java-Projekt: `sonar-maven-plugin` ≥ 5.0.x (mit JRE-Auto-Provisioning, kein separater `setup-java 17`-Step nötig)? Veraltete 3.9.x/3.11.x-Koordinaten aktualisieren. (sonar/R02)
- [ ] Keine Massen-Issue-Generierung aus Smells (nur Blocker/Critical Bug+Vuln, gedeckelt)?
- [ ] Trigger = `schedule` (monatlich) + `workflow_dispatch`, KEIN roher `push`/`pull_request` (§1a)? `concurrency: cancel-in-progress` gesetzt?
- [ ] `/flow` blockiert NICHT auf Sonar (kein per-PR-Gate by default); Pre-Merge-Qualität via reviewer-Pack-Regeln?
