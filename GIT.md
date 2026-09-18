# Git Standards

These rules apply to every repository, regardless of language. They are absolute. When in doubt, stop and ask.

## Commands

```bash
git status                                   # always before proposing any git operation
git switch -c feature/<what-it-adds>         # only after the user has approved the branch
git switch -c bugfix/<what-it-fixes>
gh pr merge --squash <number>                # only after confirmation; the only merge strategy allowed
```

## Rules

1. **Never merge, push, rebase, reset, force-push, delete a branch, or switch branches without explicit confirmation from the user in that conversation.** Describe the exact command you intend to run and wait for a yes. A general "go ahead" earlier in the session is not confirmation for a later operation.
2. **Never commit directly to `main`.** If you are on `main` and have changes to commit, stop and ask the user to create (or approve you creating) a branch first.
3. Branch names follow `feature/<what-it-adds>` or `bugfix/<what-it-fixes>`, lowercase, words separated by hyphens, spelled out in full like every other name:
   - `feature/add-tool-thingy`
   - `bugfix/resolve-import-bug`
4. Committing to an approved feature or bugfix branch is fine without asking each time. Everything else in rule 1 is not.
5. Pull requests are merged with a squash merge only. Never use a merge commit or a rebase merge. If you are asked to merge a PR (and have confirmation per rule 1), use `gh pr merge --squash`, and if you are creating a PR, never suggest another merge strategy.
6. Before every commit, run the project's formatter and linter (see the language file) so nothing unformatted or failing lint is committed.

```text
# Wrong
git checkout main && git commit -am "fix"
git push
git merge feature/add-tool-thingy
gh pr merge --merge

# Right
"I'm on main. Should I create bugfix/resolve-import-bug for this change?"
"Ready to push feature/add-tool-thingy to origin. Confirm?"
"PR #42 is approved. Squash-merge it into main?"
```
