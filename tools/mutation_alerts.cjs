const fs = require('node:fs');

function classify(report, conclusion) {
  if (!report || report.schema !== 1 || !['healthy', 'findings'].includes(report.status)) return 'incomplete';
  const counts = ['available', 'selected', 'executed', 'killed', 'survived', 'invalid', 'errors'];
  if (counts.some(k => !Number.isSafeInteger(report[k]) || report[k] < 0)) return 'incomplete';
  const valid = report.killed + report.survived;
  if (typeof report.full_scope !== 'boolean' || report.executed !== report.selected || !valid ||
      report.selected > report.available || report.errors ||
      report.killed + report.survived + report.invalid !== report.executed ||
      (report.full_scope && report.selected !== report.available) ||
      !Number.isFinite(report.score) || Math.abs(report.score - 100 * report.killed / valid) > 0.001 ||
      !Number.isFinite(report.threshold) || report.threshold < 0 || report.threshold > 100) return 'incomplete';
  const findings = report.score < report.threshold;
  // A completed below-floor run exits 1. A failed above-floor run is a tool/setup failure.
  if (conclusion !== 'success' && !(conclusion === 'failure' && report.score < report.threshold)) return 'incomplete';
  return findings ? 'findings' : 'healthy';
}

async function publish({github, context, core, report: supplied}) {
  const run = context.payload.workflow_run;
  const repo = context.payload.repository;
  if (run.head_branch !== repo.default_branch || run.head_repository?.full_name !== repo.full_name ||
      !['push', 'schedule', 'workflow_dispatch'].includes(run.event) || run.status !== 'completed') return;
  let report = supplied;
  if (report === undefined) {
    try { report = JSON.parse(fs.readFileSync('mutation-evidence/mutation-result.json', 'utf8')); }
    catch { report = null; }
  }
  let outcome = classify(report, run.conclusion);
  if (report?.commit !== run.head_sha || String(report?.run_id) !== String(run.id) ||
      String(report?.attempt) !== String(run.run_attempt || 1)) outcome = 'incomplete';
  const params = context.repo;
  const completed = await github.paginate(github.rest.actions.listWorkflowRuns, {...params,
    workflow_id: run.workflow_id, branch: repo.default_branch, status: 'completed', per_page: 100});
  if (completed.some(other => Number(other.id) > Number(run.id) &&
      other.head_repository?.full_name === repo.full_name &&
      ['push', 'schedule', 'workflow_dispatch'].includes(other.event))) {
    core.info('A newer default-branch mutation run completed; ignoring stale evidence.');
    return;
  }
  const all = await github.paginate(github.rest.issues.listForRepo, {...params, state: 'all', per_page: 100});
  const stamp = Number(run.id);
  const attempt = Number(run.run_attempt || 1);
  const identity = `run=${stamp} attempt=${attempt}`;
  if (all.some(i => !i.pull_request && /<!-- hotkit-mutation:(execution|findings) -->/.test(i.body || '') &&
      Number(i.body.match(/<!-- mutation-evidence run=(\d+) attempt=\d+ -->/)?.[1] || 0) > stamp)) return;
  const evidence = `Run: ${run.html_url}\nCommit: \`${run.head_sha}\`\nOutcome: **${outcome}**; conclusion: ${run.conclusion}.\n` +
    (report ? `Scope: ${report.full_scope ? 'full' : 'sample/partial'}; selected ${report.selected ?? '?'} / ${report.available ?? '?'}.\n` +
      `Killed ${report.killed ?? '?'}, survivors ${report.survived ?? '?'}, invalid ${report.invalid ?? '?'}, errors ${report.errors ?? '?'}.\n` +
      `Score ${report.score ?? '?'}%; floor ${report.threshold ?? '?'}%.\n` : 'Result evidence missing or unreadable.\n');
  const survivors = Array.isArray(report?.survivors) ? report.survivors.slice(0, 30).map(m =>
    `- \`${String(m.file).replaceAll('`', '').slice(0, 200)}:${Number(m.line)}\` (${String(m.operator).replaceAll('`', '').slice(0, 80)})`).join('\n') : '';
  for (const kind of ['execution', 'findings']) {
    const marker = `<!-- hotkit-mutation:${kind} -->`;
    const issues = all.filter(i => !i.pull_request && i.body?.includes(marker));
    // Never claim somebody else's issue based solely on its title.
    const issue = issues.sort((a, b) => b.number - a.number)[0];
    const prior = issue?.body?.match(/<!-- mutation-evidence run=(\d+) attempt=(\d+) -->/);
    if (prior && (Number(prior[1]) > stamp || (Number(prior[1]) === stamp && Number(prior[2]) >= attempt))) continue;
    const active = kind === 'execution' ? outcome === 'incomplete' : outcome === 'findings' && report.full_scope;
    const recovery = kind === 'execution' ? outcome !== 'incomplete' : outcome === 'healthy' && report.full_scope;
    if (!active && (!recovery || !issue || issue.state === 'closed')) continue;
    const body = `${marker}\n<!-- mutation-evidence ${identity} -->\n${evidence}\n` +
      (survivors ? `Survivor locations (up to 30; full list in artifact):\n${survivors}\n\n` : '') +
      `Owner: @${repo.owner.login}. Triage within seven days; retain this issue until verified recovery.\n\n` +
      (kind === 'execution' ? 'Inspect setup and runner logs, repair the failure, and rerun on the default branch. An incomplete run never clears score findings.\n' :
        'Inspect the survivors artifact and add missing assertions. Do not lower the configured score floor to hide findings. Only a complete, full-scope default-branch run scoring at or above the required threshold resolves this tracker; closure does not imply all survivors were fixed.\n') +
      '\nMutation testing is asynchronous and must not become a PR, merge, or release gate.\n';
    if (issue) {
      await github.rest.issues.update({...params, issue_number: issue.number, body,
        state: active ? 'open' : 'closed', state_reason: active ? 'reopened' : 'completed',
        assignees: [repo.owner.login]});
      core.info(`${active ? 'Updated/reopened' : 'Recovered'} ${kind} tracker #${issue.number}`);
    } else {
      const created = await github.rest.issues.create({...params,
        title: `Mutation testing: ${kind === 'execution' ? 'run incomplete or failed' : 'score below required threshold'}`,
        body, assignees: [repo.owner.login]});
      core.info(`Created ${kind} tracker #${created.data.number}`);
    }
  }
  await core.summary.addHeading('Asynchronous mutation evidence').addRaw(evidence +
    (survivors ? `\nSurvivor locations (up to 30; full list in artifact):\n${survivors}\n` : '')).write();
}

module.exports = publish;
module.exports.classify = classify;
