# Security

## Reporting a vulnerability

Please report security issues privately, not in a public issue: use GitHub's
"Report a vulnerability" button on the Security tab of this repository, or email
the support address on the app's App Store page. Include what you found, how to
reproduce it and the version or commit. You will get a reply within a few days.

## What is checked automatically

| Check | Where | When |
| --- | --- | --- |
| Static analysis of the backend (Bandit, medium and up) | `.github/workflows/security.yml` | every PR, push to main, weekly |
| Dependency audit of `requirements.txt` (pip-audit) | `security.yml` | same |
| Secret scan of the whole git history (gitleaks) | `security.yml` | same |
| Code scanning (CodeQL: Python, JavaScript, Actions) | GitHub default setup | every PR, push |
| Dynamic scan of the running server (OWASP ZAP baseline) | `.github/workflows/dast.yml` | weekly and on demand |
| Backend tests on Python 3.10 and 3.13 | `.github/workflows/ci.yml` | every PR, push |
| Dependency update PRs (pip, Actions, Swift packages) | `.github/dependabot.yml` | weekly |

A finding is either fixed or carries a `# nosec <id>` marker on its line, with the
reason written just before it.

## What the server does and does not hold

- No accounts or passwords. Players are a random device id and a display name.
- Game Center sign-in sends only a one-way hash of the player id.
- API keys (OpenAI, ElevenLabs, Gemini) live in server environment variables and
  are never sent to the apps.
- Browser pages get `nosniff`, frame, referrer and permissions headers, and HSTS
  behind https. There is no CSP yet: the browser controller uses inline scripts.
- Production never signs web sessions with a known key: without `SECRET_KEY` it
  mints a random one at start.
