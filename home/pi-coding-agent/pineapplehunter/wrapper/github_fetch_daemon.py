"""Run only pi-web-access's allowlisted GitHub reads on the host."""

import argparse
import asyncio
import subprocess

from dbus_next import NameFlag, RequestNameReply
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method

BUS_NAME = "io.github.pineapplehunter.GitHubFetch1"
OBJECT_PATH = "/io/github/pineapplehunter/GitHubFetch1"
VIEW_FIELDS = {
    "pr": (
        (
            "title,number,state,isDraft,author,baseRefName,headRefName,"
            "headRepositoryOwner,createdAt,mergedAt,closedAt,labels,milestone,"
            "additions,deletions,changedFiles,files,commits,reviews,"
            "statusCheckRollup,comments,body,closingIssuesReferences,url"
        ),
        (
            "title,number,state,isDraft,author,baseRefName,headRefName,"
            "headRepositoryOwner,createdAt,mergedAt,closedAt,labels,milestone,"
            "additions,deletions,changedFiles,files,commits,reviews,"
            "comments,body,url"
        ),
    ),
    "issue": (
        (
            "title,number,state,stateReason,author,createdAt,closedAt,labels,"
            "assignees,milestone,comments,body,"
            "closedByPullRequestsReferences,url"
        ),
        (
            "title,number,state,author,createdAt,closedAt,labels,assignees,"
            "milestone,comments,body,url"
        ),
    ),
}


def allowed(args):
    if len(args) == 7:
        kind, view, number, repo_flag, repo, json_flag, fields = args
        return (
            (view, repo_flag, json_flag) == ("view", "--repo", "--json")
            and number.isascii()
            and number.isdecimal()
            and repo.count("/") == 1
            and all(repo.split("/"))
            and not any(char in repo for char in ":\\%?#{}")
            and fields in VIEW_FIELDS.get(kind, ())
        )

    if len(args) not in (2, 4) or args[0] != "api":
        return False
    path, _, query = args[1].partition("?")
    parts = path.split("/")
    # Check the API route literally; don't let gh or the server reinterpret it.
    if (
        len(parts) < 3
        or parts[0] != "repos"
        or any(part in ("", ".", "..") for part in parts)
        or any(char in path for char in "%\\#{}")
    ):
        return False

    match parts[3:], args[2:]:
        case [], ["--jq", ".size" | ".default_branch"]:
            return not query
        case ["git", "trees", _, *_], ["--jq", ".tree[].path"]:
            return query == "recursive=1"
        case ["readme"] | ["contents", _, *_], ["--jq", ".content"]:
            return (
                query.startswith("ref=")
                and len(query) > 4
                and "&" not in query
                and "#" not in query
            )
        case ["pulls", number, "comments"], []:
            return number.isascii() and number.isdecimal() and query in (
                "per_page=100&page=1",
                "per_page=100&page=2",
                "per_page=100&page=3",
            )
        case ["pulls", "comments", number], []:
            return number.isascii() and number.isdecimal() and not query
    return False


def run(gh, args):
    result = subprocess.run(
        [gh, *args],
        shell=False,
        check=False,
        cwd="/",
        stdin=subprocess.DEVNULL,
        capture_output=True,
        timeout=15,
    )
    if not result.returncode:
        return [0, result.stdout, b""]
    # Keep host diagnostics private, but preserve the extension's retry signal.
    error = result.stderr.lower()
    if b"unknown field" in error or b"unknown json field" in error:
        return [result.returncode, b"", b"gh: unknown JSON field\n"]
    return [result.returncode, b"", b"gh: host request failed\n"]


class GitHubFetch(ServiceInterface):
    def __init__(self, gh):
        super().__init__(BUS_NAME)
        self.gh = gh

    @method()
    async def Run(self, args: "as") -> "iayay":  # noqa: F722, F821
        if not allowed(args):
            return [1, b"", b"gh: unsupported invocation\n"]
        try:
            return await asyncio.to_thread(run, self.gh, args)
        except (OSError, subprocess.TimeoutExpired):
            return [1, b"", b"gh: GitHub fetch failed on the host\n"]


async def serve(gh):
    connection = await MessageBus().connect()
    connection.export(OBJECT_PATH, GitHubFetch(gh))
    ownership = await connection.request_name(
        BUS_NAME, NameFlag.DO_NOT_QUEUE
    )
    if ownership != RequestNameReply.PRIMARY_OWNER:
        raise RuntimeError(f"could not own {BUS_NAME}: {ownership.name}")
    await connection.wait_for_disconnect()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("gh")
    asyncio.run(serve(parser.parse_args().gh))
