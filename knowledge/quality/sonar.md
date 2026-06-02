# Knowledge Pack — Static Analysis (SonarCloud / SonarQube)

> Wie die Fabrik statische Code-Analyse **scant** und die Behebung **steuert**. Optional pro Projekt (`profile.sonar.edition`). Referenziert von `new-project`, `adopt`, `flow` + den `sonar.yml`-Templates.

last_trained: 2026-06-02

## 0. Grundprinzip — „Clean as You Code"
Sonar wird NICHT benutzt, um die gesamte Alt-Last zu fixen (das ist der Anfänger-Fehler: bei einem 5k-LOC-Repo zeigt Sonar schnell 400+ Findings, davon ~98 % Code Smells). Stattdessen:
- **Neuer Code muss sauber sein** — das Quality Gate misst nur das **New-Code-Window**; ein `/flow`-PR landet nicht, wenn er das Gate auf neuem Code reißt.
- **Alt-Last bleibt getrackte Schuld** (im Sonar-Dashboard sichtbar), wird NICHT massenhaft in Board-Items gewandelt. Behebung opportunistisch (wenn man die Datei eh anfasst) — und Framework-Migrationen (z.B. Spring-Boot/Angular-Major) räumen Smells ohnehin großflächig weg.
- **Beim `adopt` nur die Spitze als Backlog:** nur `BLOCKER`/`CRITICAL` vom Typ `BUG` und `VULNERABILITY` als **gedeckelte** Board-Items (Cap z.B. 15) ziehen — KEINE Code-Smells als Issues.

## 1. Free-Plan-Grenzen (prägen die Edition-Wahl)
| Edition | Kosten | Sichtbarkeit | Branch/PR-Analyse |
|---|---|---|---|
| **SonarCloud Free** | gratis | **nur PUBLIC Repos** | ja (PR-Decoration + Branch) |
| SonarCloud (paid) | $/LOC | privat ok | ja |
| **SonarQube Community (self-host)** | gratis | beliebig (auch privat) | **nein — nur Main-Branch**, keine PR-Decoration |
| SonarQube Developer+ | $ | beliebig | ja |

**Auto-Wahl nach Repo-Sichtbarkeit (Fabrik-Default):**
- Repo **public** → `edition: sonarcloud` (volle PR+Branch-Analyse, Gate auf PRs).
- Repo **private** → `edition: sonarqube-ce` (self-host, nur Default-Branch, Scan NACH Merge) **oder** `edition: none`, wenn keine SonarQube-Instanz da ist.
- Unklar/kein Setup → `edition: none` (nichts bricht).

## 2. profile.sonar — Schema
```yaml
sonar:
  edition: none            # none | sonarcloud | sonarqube-ce
  organization: ""         # SonarCloud-Org (nur sonarcloud)
  project_key: ""          # z.B. <Org>_<repo>
  host_url: ""             # sonarcloud: https://sonarcloud.io · ce: https://<deine-instanz>
```
Token kommt NIE ins Profil/Repo → **GitHub-Org-Secret `SONAR_TOKEN`** (org-weit, ein Token für alle Repos). Workflow-Guard überspringt sauber, wenn das Secret fehlt (Forks/Contributor brechen nicht).

## 3. Scanner-Runtime ≠ App-Runtime (häufige Falle!)
**SonarCloud erzwingt einen Java-17-Scanner** — auch wenn die App auf Java 11/8 läuft. Der Scanner-Schritt muss daher ggf. auf einem ANDEREN JDK laufen als Build/Test:
- **Java-Projekt (Maven):** Build+Test auf `profile.java.version` (z.B. 11), dann `setup-java 17` + `sonar-maven-plugin:3.11.0.3922:sonar` (NICHT 3.9.x — die bricht auf Java 17 mit `UnsupportedClassVersionError 61.0 vs 55.0`). Reuse von `target/` aus dem verify-Step.
- **JS/Angular/Flutter/HTML:** kein Maven-Plugin → **`sonar-scanner` CLI** (offizielle `SonarSource/sonarqube-scan-action`) + `sonar-project.properties` mit `sonar.sources`, `sonar.projectKey`, `sonar.organization`. Coverage via lcov (`sonar.javascript.lcov.reportPaths`).
Die `EnvironmentInformation class file version 61.0`-Meldung = Scanner braucht Java 17.

## 4. Gate-Integration in `/flow`
Nach `Test-Gate: PASS` und Öffnen des PR (Schritt 5, nur `merge_policy: pr`, nur wenn `profile.sonar.edition != none`):
1. Auf den `sonar.yml`-CI-Run des PR warten (best-effort, kurzes Timeout) — `gh run watch`.
2. **SonarCloud:** Quality-Gate des PR via API prüfen: `GET {host}/api/qualitygates/project_status?projectKey=<key>&pullRequest=<n>` → `projectStatus.status` (`OK`/`ERROR`). **SonarQube-CE:** kein PR-Gate → nur Default-Branch-Status `GET {host}/api/qualitygates/project_status?projectKey=<key>` (informativ, nicht PR-blockierend).
3. `ERROR` (New-Code-Gate gerissen) → als `FINDINGS` zurück an den `coder` (zählt zum Schleifenschutz), NICHT landen. `OK`/Timeout/`none` → wie gehabt landen.
- Token für die API: `SONAR_TOKEN` aus dem env (read-scope reicht). Best-effort: Gate nicht abrufbar → nicht blockieren, melden.

## 5. Reviewer/Tester-Hinweise
- Der `tester` ersetzt NICHT die Sonar-Analyse (Funktion vs. statische Qualität sind getrennt).
- `sonar.yml` darf den restlichen CI-Flow NIE blockieren, wenn `SONAR_TOKEN` fehlt (Guard).
- Coverage: ohne Coverage-Report sieht Sonar **0 %**. Wenn Coverage zählen soll: Java→jacoco (`jacoco-maven-plugin` + `sonar.coverage.jacoco.xmlReportPaths`), JS→lcov. Sonst bleibt Coverage blind (akzeptabel, aber dokumentieren).

## Reviewer-Checklist (sonar)
- [ ] `profile.sonar.edition` gesetzt + passend zur Repo-Sichtbarkeit (public→sonarcloud, private→ce/none)?
- [ ] Token NUR als Org-Secret `SONAR_TOKEN`, nirgends im Repo/Profil?
- [ ] `sonar.yml` hat Non-blocking-Token-Guard?
- [ ] Java: Scanner-Schritt auf Java 17 (getrennt vom Build-JDK), Plugin ≥ 3.11.x?
- [ ] Keine Massen-Issue-Generierung aus Smells (nur Blocker/Critical Bug+Vuln, gedeckelt)?
- [ ] CE-Edition: keine PR-Gate-Erwartung (nur Main-Branch)?
