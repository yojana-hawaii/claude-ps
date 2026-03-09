# PowerShell & Claude to Automate 

**Programming Language**: Powershell

**AI**: Claude

**Goal 1**: Get Active Directory Users, Computers, Groups and Group Members. Insert into SQLs. 

**Goal 2**: Use Claude 

**Expectation**: Maintainable, Testable, Extensible, Production ready, Optimized, enterprise logging pattern, CI/CD Integration


**Programming Principles** : https://www.geeksforgeeks.org/blogs/7-common-programming-principles-that-every-developer-must-follow/ 
* SOLID
* YAGNI (You Aint Gonna Need It)
* KISS (Keep It Simple Stupid)
* DRY (Don't Repeat Youself)
* SOC (Separation Of Concerns)
* Avoid Premature Optimization
* Law of Demeter


**Test Driven Development**: https://martinfowler.com/bliki/TestDrivenDevelopment.html

---

## Repository Layout

```
claude-ps/
│
├── shared/                              # ← consumed by ALL modules
│   └── Infrastructure/
│       ├── Logger.psm1                  # Structured logging (CorrelationId)
│       ├── Config.psm1                  # Layered config (env > JSON > defaults)
│       └── SqlRepository.psm1           # SqlContext factory + parameter helpers
│
├── modules/
│   │
│   ├── active-directory/                # AD → SQL sync
│   │   ├── src/
│   │   │   ├── ADSync.psd1              # Module manifest
│   │   │   ├── ADSync.psm1              # Orchestrator / public API
│   │   │   ├── Readers/
│   │   │   │   ├── UserReader.psm1      # Get-fnADSyncUsers
│   │   │   │   ├── ComputerReader.psm1  # Get-fnADSyncComputers
│   │   │   │   └── GroupReader.psm1     # Get-fnADSyncGroups / Get-ADSyncGroupMembers
│   │   │   └── Writers/
│   │   │       ├── UserWriter.psm1      # Push-ADSyncUsers
│   │   │       ├── ComputerWriter.psm1  # Push-ADSyncComputers
│   │   │       └── GroupWriter.psm1     # Push-ADSyncGroups / Push-ADSyncGroupMembers
│   │   ├── tests/
│   │   │   ├── ActiveDirectory.Tests.ps1
│   │   │   └── SqlRepository.Tests.ps1
│   │   ├── config.example.json
│   │   └── Run-ADSync.ps1               # Scheduled-task entry point
│   │
│   ├── <module2>/                       # e.g. azure-ad, servicenow, hr-feed …
│   │   ├── src/
│   │   │   ├── <Module>.psd1
│   │   │   ├── <Module>.psm1            # imports from shared/Infrastructure/
│   │   │   ├── Readers/
│   │   │   └── Writers/
│   │   ├── tests/
│   │   └── Run-<Module>.ps1
│   │
│   └── <another-module>/
│       └── …
│
├── tests/
│   └── Infrastructure.Tests.ps1         # Shared layer tested once, centrally
│
├── pipeline/
│   └── ci-cd.yml                        # Lint → Unit → Integration → Deploy (all modules)
│
└── README.md
```

## Dependency flow

```
shared/Infrastructure/          (no dependencies)
        ↑
modules/active-directory/       imports Logger, Config, SqlRepository
        ↑
modules/<next-module>/          imports Logger, Config, SqlRepository
```

Each module is independently deployable. Infrastructure tests live at the repo root;
module tests live alongside their module.

---


## Design Principles Applied

| Principle | Implementation |
|-----------|----------------|
| **SRP** | Each `.psm1` does one thing: read *or* write *or* configure *or* log |
| **DRY** | `Add-SqlParameter`, `_Build-*Filter` helpers eliminate repetition |
| **Open/Closed** | Add a new entity by adding a Reader + Writer pair; orchestrator unchanged |
| **Fail-Fast Validation** | `SyncConfig.Validate()` throws immediately on bad config |
| **TDD** | Tests written against interfaces with mocked dependencies |
| **Structured Logging** | Every log line: `Timestamp | Level | CorrelationId | Caller | Message` |
| **CI/CD** | Lint → Unit → Integration → Deploy gates, exit codes propagated |

---

## CI/CD

See `pipeline/ci-cd.yml` for the full GitHub Actions pipeline:

1. **Lint** — PSScriptAnalyzer (Error + Warning rules)
2. **Unit Tests** — Pester, no external dependencies
3. **Integration Tests** — self-hosted runner with domain + SQL access (main branch only)
4. **Deploy** — copies to network share, registers hourly Scheduled Task

---
