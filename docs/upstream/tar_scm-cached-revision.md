# Upstream report draft — openSUSE/obs-service-tar_scm

## Comment on issue #237

Root cause, for anyone who lands here:

`update_cache()` never calls `fetch_specific_revision()` — only `fetch_upstream_scm()` (the initial-clone path) does. So on a reused clone, a `revision` naming a branch or tag arrives only as `refs/remotes/origin/<rev>`. Two symptoms follow, depending on whether a local ref happens to exist:

1. No local ref: `_stash_and_merge()` merges `origin/<rev>` fine, then `_ref_exists(<rev>)` is false and it exits `<rev>: No such revision`.
2. Local ref exists but stale: HEAD stays on the previous branch, so `git merge origin/<rev>` advances *that* branch, the `<rev>` ref never moves, and `git reset --hard <rev>` packages an old commit — the tarball staleness in this issue.

Scope: needs no `CACHEDIRECTORY` **and** a reused `clone_dir`. That is exactly `osc service disabledrun` in a package directory, where `_calc_dir_to_clone_to()` puts the clone at `<pkgdir>/<repo>/`. With `CACHEDIRECTORY` the mirror holds `refs/heads/*` directly, so `_ref_exists` passes and neither symptom appears. Server-side OBS builds clone fresh. That likely explains why this sat open.

Reproduced against a local `git daemon` on current master (`454b4bb`):

```
$ OSC_VERSION=1 tar_scm --scm git --url git://127.0.0.1/proj.git --revision master     --outdir out   # ok
$ git push origin new-branch                                                                          # branch created after run 1
$ OSC_VERSION=1 tar_scm --scm git --url git://127.0.0.1/proj.git --revision new-branch --outdir out
Already up to date.
new-branch: No such revision
```

Patch in the PR below.

## PR description

### tar_scm: fetch revisions missing from a cached clone

`update_cache()` gets the same treatment as the initial clone: create the local ref, then check it out.

```python
if self.revision and not self._ref_exists(self.revision):
    self.fetch_specific_revision()
    if not self.repocachedir:
        self.helpers.safe_run(
            self._get_scm_cmd() + ['checkout', self.revision],
            cwd=self.clone_dir
        )
```

The checkout is load-bearing. Without it the "No such revision" abort goes away but symptom 2 of #237 remains: I tested that variant and run 3 silently packaged the previous commit. Guarded on `not self.repocachedir` because the mirror is bare and `prepare_working_copy()` already handles that path.

Verified against a local `git daemon`: the sequence master -> new branch -> new tag -> master all resolve to the right content, and a commit pushed after a cached run is picked up. Fixes #237.

## Separate one-liner, own PR

`base.py:420` in `run_and_hide()`:

```python
exc = re.sub(self.url, self.org_url, str(exc))
```

`self.org_url` is `None` unless `auth_url()` set credentials from the keyring. So any failure routed through `run_and_hide` dies with `TypeError: decoding to str: need a bytes-like object, NoneType found` instead of the real error. Hit this live — it swallowed a genuine `prepare_working_copy()` clone failure. Guard on `self.org_url` before substituting.
