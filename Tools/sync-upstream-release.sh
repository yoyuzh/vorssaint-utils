#!/bin/bash
set -euo pipefail

upstream=vorssaint/vorssaint-utils
fork=yoyuzh/vorssaint-utils
test "$GH_REPO" = "$fork"

tag=$(gh api "repos/$upstream/releases/latest" --jq 'select(.immutable and .author.login == "github-actions[bot]" and (.draft or .prerelease | not)) | .tag_name')
if [[ ! "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo 'Expected an immutable upstream stable release.' >&2
    exit 1
fi
version=${tag#v}
release_commit=$(gh api "repos/$upstream/commits/$tag" --jq 'select(.commit.verification.verified) | .sha')
test -n "$release_commit"
upstream_head=$(gh api "repos/$upstream/git/ref/heads/main" --jq .object.sha)
relation=$(gh api "repos/$upstream/compare/$release_commit...$upstream_head" --jq .status)
case "$relation" in
    identical|ahead) ;;
    *) echo "$tag is not in upstream main history." >&2; exit 1 ;;
esac

mirror=$(gh api "repos/$fork/git/ref/heads/main" --jq .object.sha)
if [[ "$mirror" != "$upstream_head" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo "Would fast-forward main from $mirror to $upstream_head."
    else
        gh api "repos/$fork/git/refs/heads/main" -X PATCH -f sha="$upstream_head" -F force=false --silent
    fi
fi

custom=$(gh api "repos/$fork/git/ref/heads/custom" --jq .object.sha)
relation=$(gh api "repos/$fork/compare/$release_commit...$custom" --jq .status)
if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run: upstream $tag at $release_commit, custom comparison: $relation. No PR, merge, tag or release created."
    exit 0
fi

case "$relation" in
    identical|ahead) ;;
    *)
        branch="sync/upstream-$tag"
        pull=$(gh api --method GET "repos/$fork/pulls" -f state=all -f base=custom -f head="${fork%/*}:$branch" --jq '.[0] // empty')
        if [[ -z "$pull" ]]; then
            head=$(gh api "repos/$fork/git/matching-refs/heads/$branch" --jq ".[] | select(.ref == \"refs/heads/$branch\") | .object.sha")
            if [[ -z "$head" ]]; then
                gh api "repos/$fork/git/refs" -f ref="refs/heads/$branch" -f sha="$release_commit" --silent
            elif [[ "$head" != "$release_commit" ]]; then
                echo "$branch has been edited; open and merge the sync PR manually." >&2
                exit 1
            fi
            pull=$(gh api "repos/$fork/pulls" -f base=custom -f head="$branch" \
                -f title="chore(sync): merge upstream $tag" \
                -f body="Syncs the verified upstream [$tag](https://github.com/$upstream/releases/tag/$tag). If there are conflicts, merge custom into this branch, resolve them, and merge this PR with a merge commit. A later sync run will resume CD.")
        fi
        url=$(jq -er .html_url <<<"$pull")
        printf 'Upstream sync PR: %s\n' "$url" | tee -a "$GITHUB_STEP_SUMMARY"
        if [[ "$(jq -r .state <<<"$pull")" != open || "$(jq -r .head.sha <<<"$pull")" != "$release_commit" ]]; then
            echo "PR closed or edited; no automatic merge: $url" >&2
            exit 1
        fi
        number=$(jq -er .number <<<"$pull")
        for attempt in 1 2 3; do
            mergeable=$(gh api "repos/$fork/pulls/$number" --jq 'if .mergeable == null then "unknown" else .mergeable end')
            if [[ "$mergeable" != unknown ]]; then break; fi
            if [[ "$attempt" != 3 ]]; then sleep 2; fi
        done
        if [[ "$mergeable" == false ]]; then
            echo "Resolve conflicts in $url before CD can continue." >&2
            exit 1
        fi
        if ! merge=$(gh api "repos/$fork/pulls/$number/merge" -X PUT -f sha="$release_commit" -f merge_method=merge); then
            echo "GitHub did not merge the PR; resolve conflicts or checks before retrying: $url" >&2
            exit 1
        fi
        custom=$(jq -er 'select(.merged == true) | .sha' <<<"$merge")
        ;;
esac

latest=$(gh api --paginate "repos/$fork/releases?per_page=100" --jq '.[] | select((.draft or .prerelease) | not) | .tag_name | select(test("^custom-v[0-9]+\\.[0-9]+\\.[0-9]+$"))' | sort -V | tail -n 1)
highest=$(printf '%s\n' "custom-$tag" "$latest" | sort -V | tail -n 1)
if [[ "$highest" == "$latest" ]]; then
    echo "$tag is already covered by $latest."
    exit 0
fi

ref=$(gh api "repos/$fork/git/matching-refs/tags/custom-$tag" --jq ".[] | select(.ref == \"refs/tags/custom-$tag\") | .ref")
if [[ -n "$ref" ]]; then
    tagged=$(gh api "repos/$fork/commits/custom-$tag" --jq .sha)
    contains_release=$(gh api "repos/$fork/compare/$release_commit...$tagged" --jq .status)
    on_custom=$(gh api "repos/$fork/compare/$tagged...$custom" --jq .status)
    case "$contains_release/$on_custom" in
        identical/identical|identical/ahead|ahead/identical|ahead/ahead) custom=$tagged ;;
        *) echo "Existing custom-$tag does not match the upstream release and custom history." >&2; exit 1 ;;
    esac
fi

printf 'commit=%s\nversion=%s\n' "$custom" "$version" >> "$GITHUB_OUTPUT"
