# Secret handling

Store credentials in a password manager or deployment secret store. For local development, inject environment variables or use an ignored `.env` file. Commit only empty or placeholder values in `.env.example`; never paste credentials into local permission settings, source, scripts, or documentation.

Install Gitleaks (`brew install gitleaks` on macOS), then enable the staged secret check for this clone:

```sh
git config core.hooksPath .githooks
```

Scan all reachable Git history before pushing:

```sh
gitleaks git --redact=100 --log-opts="--all" .
```

The scanner allows only SHA-1 dependency checksums in the iOS CocoaPods lockfile. Do not add broad secret-scan exclusions.

If a credential is exposed, revoke it at its provider, replace it in the secret store and affected deployments, and inspect usage. Deleting it or rewriting Git history does not revoke it. After a history rewrite, use a fresh clone or carefully migrate local work; never merge the old history back. GitHub cached commits, pull requests, forks, and other clones may need separate cleanup.
