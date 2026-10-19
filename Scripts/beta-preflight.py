#!/usr/bin/env python3
"""Plan or apply replacement of unapproved version-only candidate PRs.

Run from a fetched repository before creating a candidate. No signing credentials needed.
"""
import argparse
import json
import plistlib
import re
import subprocess


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def gh_json(*args):
    return json.loads(command('gh', *args))


def decide(source, candidates, active_runs, is_ancestor):
    if active_runs:
        raise ValueError('发行 workflow 正在运行或排队，稍后重新执行')
    # Validate every candidate before mutating any PR.
    superseded, reusable = [], []
    for candidate in candidates:
        if 'release-approved' in candidate['labels']:
            raise ValueError(f"候选 #{candidate['number']} 已批准，不能自动取代")
        previous = candidate['source']
        if previous == source:
            reusable.append(candidate['number'])
        elif is_ancestor(previous, source):
            superseded.append(candidate['number'])
        else:
            raise ValueError(f"候选 #{candidate['number']} 的源码与目标分叉，需人工处理")
    if len(reusable) > 1:
        raise ValueError('同一源码存在多个候选，需人工处理')
    versions = {candidate['version'] for candidate in candidates}
    if len(versions) > 1:
        raise ValueError('存在多个目标版本的候选，不能自动选择版本')
    return {'reuse': reusable, 'supersede': superseded,
            'target_version': next(iter(versions), None)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, help='Exact full development commit SHA')
    parser.add_argument('--apply', action='store_true', help='Close superseded PRs; releases/tags are retained')
    args = parser.parse_args()
    source = command('git', 'rev-parse', f'{args.source}^{{commit}}')
    if source != args.source:
        raise SystemExit('--source 必须为完整 commit SHA')
    repo = gh_json('repo', 'view', '--json', 'nameWithOwner,defaultBranchRef')
    default = repo['defaultBranchRef']['name']
    command('git', 'fetch', '--no-tags', 'origin', f'+refs/heads/{default}:refs/remotes/origin/{default}')

    def ancestor(old, new):
        result = subprocess.run(['git', 'merge-base', '--is-ancestor', old, new], check=False)
        if result.returncode not in (0, 1):
            raise ValueError('无法验证候选源码祖先关系')
        return result.returncode == 0

    if not ancestor(source, f'origin/{default}'):
        raise SystemExit('目标源码尚未进入远端默认分支')
    active = []
    for workflow in ('beta.yml', 'promote.yml'):
        # API pagination avoids silently ignoring old queued/waiting runs.
        # Query all incomplete statuses, including waiting and pending environments.
        for status in ('queued', 'in_progress', 'waiting', 'pending', 'requested'):
            pages = gh_json('api', '--paginate', '--slurp',
                            f"repos/{repo['nameWithOwner']}/actions/workflows/{workflow}/runs?per_page=100&status={status}")
            active.extend(run for page in pages for run in page['workflow_runs'])
    prs = gh_json('pr', 'list', '--state', 'open', '--limit', '1000', '--json',
                  'number,headRefName,headRefOid,labels')
    candidates = []
    for pr in prs:
        if not pr['headRefName'].startswith('release/miniTools-'):
            continue
        head = pr['headRefOid']
        command('git', 'fetch', '--no-tags', 'origin', pr['headRefName'])
        parents = command('git', 'rev-list', '--parents', '-n', '1', head).split()
        if len(parents) != 2:
            raise SystemExit(f"候选 #{pr['number']} 不是单一版本提交")
        old_source = parents[1]
        files = command('git', 'diff', '--name-only', old_source, head).splitlines()
        if files != ['Support/Info.plist']:
            raise SystemExit(f"候选 #{pr['number']} 含非版本改动")
        before = plistlib.loads(subprocess.check_output(['git', 'show', f'{old_source}:Support/Info.plist']))
        after = plistlib.loads(subprocess.check_output(['git', 'show', f'{head}:Support/Info.plist']))
        if {key for key in before.keys() | after.keys() if before.get(key) != after.get(key)} != {'CFBundleShortVersionString'}:
            raise SystemExit(f"候选 #{pr['number']} 修改了非展示版本字段")
        version = after['CFBundleShortVersionString']
        if not re.fullmatch(r'[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[1-9][0-9]*', version):
            raise SystemExit(f"候选 #{pr['number']} 的展示版本无效")
        if command('git', 'ls-remote', '--tags', 'origin', f'refs/tags/v{version}'):
            raise SystemExit(f'目标版本 {version} 已有正式标签，不能继续替代')
        candidates.append({'number': pr['number'], 'source': old_source, 'version': version,
                           'labels': [label['name'] for label in pr['labels']]})
    plan = decide(source, candidates, active, ancestor)
    print(json.dumps({'source': source, **plan}, ensure_ascii=False))
    if args.apply:
        for number in plan['supersede']:
            current = gh_json('pr', 'view', str(number), '--json', 'state,headRefOid,labels')
            original = next(pr for pr in prs if pr['number'] == number)
            if (current['state'] != 'OPEN' or current['headRefOid'] != original['headRefOid']
                    or any(label['name'] == 'release-approved' for label in current['labels'])):
                raise SystemExit(f'候选 #{number} 状态已变化，停止并重新检查')
            subprocess.run(['gh', 'pr', 'close', str(number), '--comment',
                            f'Superseded by source {source}. 未批准旧候选已取代；保留不可变 Release 和标签，不再正式提升。'], check=True)
    if plan['reuse']:
        print('复用已有候选；若其 workflow 失败，可针对原准确候选提交重新派发，无需新建 PR。')


if __name__ == '__main__':
    try:
        main()
    except ValueError as error:
        raise SystemExit(str(error))
