const test = require('node:test');
const assert = require('node:assert/strict');
const publish = require('../../tools/mutation_alerts.cjs');

function harness(issues = [], overrides = {}) {
  const calls = [];
  const context = {repo: {owner: 'owner', repo: 'hotkit'}, payload: {
    repository: {default_branch: 'main', full_name: 'owner/hotkit', owner: {login: 'owner'}},
    workflow_run: {id: 100, workflow_id: 5, run_attempt: 1, status: 'completed', conclusion: 'success',
      head_sha: 'abc', head_branch: 'main', head_repository: {full_name: 'owner/hotkit'},
      event: 'push', html_url: 'https://example.test/runs/100', ...overrides}}};
  const github = {paginate: async (fn, params) => {
    if (fn === github.rest.actions.listWorkflowRuns) return [];
    assert.equal(params.state, 'all'); assert.equal(params.per_page, 100); return issues;
  }, rest: {actions: {listWorkflowRuns() {}}, issues: {listForRepo() {}, create: async p => {calls.push(['create', p]); return {data: {number: 1}};},
    update: async p => {calls.push(['update', p]);}}}};
  const summary = {addHeading() {return this;}, addRaw() {return this;}, async write() {}};
  return {calls, github, context, core: {info() {}, summary}};
}

function report(overrides = {}) {
  return {schema: 1, status: 'healthy', full_scope: true, available: 10, selected: 10,
    executed: 10, killed: 10, survived: 0, invalid: 0, errors: 0, threshold: 90, score: 100,
    commit: 'abc', run_id: '100', attempt: '1', ...overrides};
}

const issue = (kind, state = 'open', run = 99, attempt = 1) => ({number: 7, state,
  body: `<!-- hotkit-mutation:${kind} -->\n<!-- mutation-evidence run=${run} attempt=${attempt} -->`});

test('score below configured threshold creates one assigned tracker with commit/run evidence', async () => {
  const h = harness();
  await publish({...h, report: report({status: 'findings', killed: 8, survived: 2, score: 80})});
  assert.equal(h.calls.length, 1);
  const p = h.calls[0][1];
  assert.deepEqual(p.assignees, ['owner']);
  assert.match(p.body, /hotkit-mutation:findings/);
  assert.match(p.body, /https:\/\/example.test\/runs\/100/);
  assert.match(p.body, /abc/);
});

test('existing closed tracker reopens; repeated run and stale attempts do nothing', async () => {
  const findings = report({status: 'findings', killed: 8, survived: 2, score: 80});
  const h = harness([issue('findings', 'closed')]);
  await publish({...h, report: findings});
  assert.equal(h.calls[0][0], 'update'); assert.equal(h.calls[0][1].state, 'open');
  for (const prior of [issue('findings', 'open', 100), issue('findings', 'open', 101), issue('findings', 'open', 100, 2)]) {
    const repeat = harness([prior]);
    await publish({...repeat, report: findings});
    assert.equal(repeat.calls.length, 0);
  }
});

test('missing, malformed, cancelled, skipped, stale artifact and runner errors never close findings', async () => {
  for (const [data, conclusion] of [[null, 'failure'], [{}, 'success'], [report(), 'cancelled'],
    [report(), 'skipped'], [report({commit: 'old'}), 'success'], [report({attempt: '0'}), 'success'],
    [report({errors: 1}), 'success'], [report({score: 99}), 'success'],
    [report({threshold: undefined}), 'success'], [report({threshold: '90'}), 'success']]) {
    const h = harness([issue('findings')], {conclusion});
    await publish({...h, report: data});
    assert.equal(h.calls.length, 1);
    assert.equal(h.calls[0][0], 'create');
    assert.match(h.calls[0][1].body, /hotkit-mutation:execution/);
  }
});

test('healthy sample recovers execution only; full healthy run recovers both', async () => {
  const h = harness([issue('findings'), issue('execution')]);
  await publish({...h, report: report({full_scope: false, available: 100})});
  assert.equal(h.calls.length, 1);
  assert.match(h.calls[0][1].body, /hotkit-mutation:execution/);
  assert.equal(h.calls[0][1].state, 'closed');
  const full = harness([issue('findings'), issue('execution')]);
  await publish({...full, report: report({killed: 9, survived: 1, score: 90})});
  assert.equal(full.calls.length, 2);
  assert.ok(full.calls.every(c => c[1].state === 'closed'));
});

test('below-floor test failure is findings, unexplained workflow failure is incomplete', async () => {
  assert.equal(publish.classify(report({killed: 5, survived: 5, score: 50}), 'failure'), 'findings');
  assert.equal(publish.classify(report(), 'failure'), 'incomplete');
});

test('PR, fork, nondefault and unfinished events cannot write issues', async () => {
  for (const override of [{event: 'pull_request'}, {head_branch: 'feature'},
    {head_repository: {full_name: 'fork/hotkit'}}, {status: 'in_progress'}]) {
    const h = harness([], override);
    await publish({...h, report: report()});
    assert.equal(h.calls.length, 0);
  }
});

test('unmarked issues and PRs are never commandeered', async () => {
  const h = harness([{number: 9, body: 'Mutation testing: survivors'}, {...issue('findings'), pull_request: {}}]);
  await publish({...h, report: report({killed: 8, survived: 2, score: 80})});
  assert.equal(h.calls[0][0], 'create');
});

test('publisher API failures remain failures for visible Actions retry', async () => {
  const h = harness();
  h.github.rest.issues.create = async () => {throw new Error('forbidden');};
  await assert.rejects(publish({...h, report: null}), /forbidden/);
});

test('newer completed run prevents old findings even without an existing tracker', async () => {
  const h = harness();
  h.github.paginate = async fn => fn === h.github.rest.actions.listWorkflowRuns ?
    [{id: 101, event: 'push', head_repository: {full_name: 'owner/hotkit'}}] : [];
  await publish({...h, report: report({killed: 8, survived: 2, score: 80})});
  assert.equal(h.calls.length, 0);
});

test('newer execution evidence prevents older healthy run from closing findings', async () => {
  const h = harness([issue('findings'), issue('execution', 'open', 101)]);
  await publish({...h, report: report()});
  assert.equal(h.calls.length, 0);
});

test('survivors at equality or above threshold do not create issues and remain in summary', async () => {
  for (const threshold of [90, 80]) {
    const h = harness();
    let summary = '';
    h.core.summary.addRaw = text => {summary = text; return h.core.summary;};
    await publish({...h, report: report({killed: 9, survived: 1, score: 90, threshold,
      survivors: [{file: 'src/logic.ahk', line: 5, operator: 'gt->ge'}]})});
    assert.equal(h.calls.length, 0);
    assert.match(summary, /src\/logic.ahk:5/);
    assert.match(summary, /healthy/);
  }
});

test('sampled below-floor result cannot create full-scope findings', async () => {
  const h = harness();
  await publish({...h, report: report({killed: 8, survived: 2, score: 80, full_scope: false, available: 100})});
  assert.equal(h.calls.length, 0);
});
