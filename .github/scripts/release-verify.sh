#!/usr/bin/env bash
# release.yml "verify" job (environments.md §5 step 17; ENV-1, ENV-2,
# ENV-6; security review REL-1, REL-2).
#
# Env in:
#   EVENT                 push | workflow_dispatch
#   TAG                   the tag (push) or the rehearsed tag name (dispatch)
#   SHA                   the commit being released
#   REPO                  owner/name
#   GH_TOKEN              read-only token (actions: read) for the CI check
#   PLAY_RELEASE_ENABLED  repo variable; "true" turns tag pushes into signed
#                         builds. Anything else = dry run (the default).
# Out ($GITHUB_OUTPUT): flavor, version, build_number, dry_run, ads, app_id,
#   artifact
#
# Hard errors always: tag format, X.Y.Z == pubspec, build number increases.
# On a tag push also: commit on main, CI green, prod has a beta tag on the
# same commit. A workflow_dispatch rehearsal reports those three as
# warnings, so a dry run can be tried from any commit.
set -euo pipefail

: "${EVENT:?}" "${TAG:?}" "${SHA:?}" "${REPO:?}"
out="${GITHUB_OUTPUT:-/dev/stdout}"
fail=0
err()  { echo "::error title=Release verify::$1"; fail=1; }
soft() { if [[ "$EVENT" == push ]]; then err "$1"; else echo "::warning title=Release verify (rehearsal)::$1"; fi; }

TAG_RE='^(beta-)?v([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$'

# 1. Tag format.
if [[ ! "$TAG" =~ $TAG_RE ]]; then
  echo "::error title=Release verify::tag '$TAG' must look like beta-vX.Y.Z+N or vX.Y.Z+N"
  exit 1
fi
if [[ -n "${BASH_REMATCH[1]}" ]]; then flavor=beta; else flavor=prod; fi
version="${BASH_REMATCH[2]}"
build="${BASH_REMATCH[3]}"
echo "Tag $TAG: flavor=$flavor version=$version build=$build commit=$SHA"
if [[ "$EVENT" == push && "${GITHUB_REF_TYPE:-tag}" != tag ]]; then
  err "release.yml must be triggered by a tag push"
fi

# 2. X.Y.Z matches pubspec (ENV-6).
pub=$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)
if [[ "$pub" != "$version" ]]; then
  err "tag version $version != pubspec.yaml version $pub (bump pubspec in a PR first)"
fi

# 3. Build number strictly increases over every other release tag (ENV-6).
max=0; max_tag=""
while read -r t; do
  [[ -z "$t" || "$t" == "$TAG" ]] && continue
  if [[ "$t" =~ $TAG_RE ]]; then
    n=$((10#${BASH_REMATCH[3]}))
    if (( n > max )); then max=$n; max_tag=$t; fi
  fi
done < <(git tag -l 'v*' 'beta-v*')
if (( 10#$build <= max )); then
  err "build number $build must be greater than $max (from $max_tag)"
else
  echo "Build number $build > previous max $max${max_tag:+ ($max_tag)}"
fi

# 4. Commit is on main (ENV-1).
git fetch --no-tags --quiet origin +refs/heads/main:refs/remotes/origin/main || true
if git merge-base --is-ancestor "$SHA" origin/main 2>/dev/null; then
  echo "Commit is on main."
else
  soft "commit $SHA is not on main (ENV-1)"
fi

# 5. CI green on main for this commit (ENV-1): the latest push run on main
#    of each required workflow concluded success.
if [[ -n "${GH_TOKEN:-}" ]] && command -v gh >/dev/null; then
  runs=$(gh api "repos/$REPO/actions/runs?head_sha=$SHA&branch=main&event=push&per_page=100" 2>/dev/null || echo '{}')
  for wf in "Repo rules" "Build" "Launch test"; do
    concl=$(jq -r --arg wf "$wf" \
      '[.workflow_runs[]? | select(.name == $wf)] | sort_by(.created_at) | last | if . == null then "missing" else (.conclusion // .status) end' <<<"$runs")
    if [[ "$concl" == success ]]; then
      echo "CI: $wf = success"
    else
      soft "CI: '$wf' on main for $SHA is '$concl', not success (ENV-1)"
    fi
  done
else
  soft "cannot read CI status (no gh or token)"
fi

# 6. prod needs a beta tag on the same commit (ENV-2).
if [[ "$flavor" == prod ]]; then
  if git tag --points-at "$SHA" | grep -qE '^beta-v'; then
    echo "beta tag on the same commit: $(git tag --points-at "$SHA" | grep -E '^beta-v' | tr '\n' ' ')"
  else
    soft "prod tag needs a beta-v* tag on the same commit (ENV-2)"
  fi
fi

# Mode: tag pushes are dry runs unless the owner set PLAY_RELEASE_ENABLED.
if [[ "$EVENT" == push && "${PLAY_RELEASE_ENABLED:-}" == true ]]; then dry=false; else dry=true; fi
if [[ "$flavor" == prod && "$dry" == false ]]; then ads="real"; else ads="test"; fi
app_id=com.southicarus.probe_dash
artifact="probe-dash-$flavor-$version-b$build"
[[ "$dry" == true ]] && artifact="$artifact-NOT-FOR-UPLOAD"
echo "Mode: dry_run=$dry ads=$ads artifact=$artifact"

{
  echo "flavor=$flavor"
  echo "version=$version"
  echo "build_number=$build"
  echo "dry_run=$dry"
  echo "ads=$ads"
  echo "app_id=$app_id"
  echo "artifact=$artifact"
} >> "$out"

exit "$fail"
