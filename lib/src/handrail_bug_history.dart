import 'package:flutter/material.dart';

import 'handrail_bug_reporter_config.dart';
import 'handrail_bug_reporter_submission.dart';

class HandrailBugHistory extends StatefulWidget {
  const HandrailBugHistory(
      {super.key, required this.config, required this.client});
  final HandrailBugReporterConfig config;
  final HandrailBugReportClient client;

  @override
  State<HandrailBugHistory> createState() => _HistoryState();
}

class _HistoryState extends State<HandrailBugHistory> {
  List<Map> bugs = [];
  String? cursor, session, error;
  bool loading = false;
  bool allUsers = false;

  Map<String, String> get scope => {
        if (widget.config.projectId.isNotEmpty)
          'project_id': widget.config.projectId
        else if (widget.config.projectSlug.isNotEmpty)
          'project_slug': widget.config.projectSlug,
        'environment': widget.config.environment,
        'reporter_surface': 'mobile',
      };

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    widget.client.close();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final token = await widget.config.resolveApplicationSessionToken();
      if (token == null || token.isEmpty)
        throw StateError('Sign in to view report history.');
      final policy = await widget.client.loadPolicy(
          projectId: widget.config.projectId,
          projectSlug: widget.config.projectSlug,
          environment: widget.config.environment,
          applicationSessionToken: token);
      if (policy?.identityVerified != true)
        throw StateError('Sign in to view report history.');
      final append =
          more && token == session && policy!.allUsersHistory == allUsers;
      final result =
          await widget.client.readHistory(sessionToken: token, query: {
        ...scope,
        'audience': policy!.allUsersHistory ? 'all' : 'mine',
        if (append && cursor != null) 'cursor': cursor!
      });
      if (token != await widget.config.resolveApplicationSessionToken())
        throw StateError('Your session changed. Refresh report history.');
      if (!mounted) return;
      final rows = (result['bugs'] as List).whereType<Map>();
      setState(() {
        bugs = [if (append) ...bugs, ...rows];
        session = token;
        allUsers = policy.allUsersHistory;
        cursor = result['pagination']?['next_cursor'] as String?;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          bugs = [];
          session = null;
          cursor = null;
          error = e.toString();
        });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(
          18, 16, 18, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
              child: Text('Report history',
                  style: Theme.of(context).textTheme.titleLarge)),
          TextButton(
              onPressed: loading ? null : load, child: const Text('Refresh')),
          TextButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Close')),
        ]),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (!loading && error == null && bugs.isEmpty)
          const Text('No reports yet.'),
        Flexible(
            child: ListView(shrinkWrap: true, children: [
          for (final bug in bugs)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(bug['title'] as String? ?? 'Bug report',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(bug['status_rollup']?['label'] as String? ?? ''),
                          for (final question in questions(bug))
                            _Question(
                                key: ValueKey([
                                  session,
                                  bug['id'],
                                  question['id']
                                ].join('/')),
                                question: question,
                                owner: bug['is_owner'] != false,
                                submit: (option, answer) async {
                                  final token = await widget.config
                                      .resolveApplicationSessionToken();
                                  if (token == null || token != session)
                                    throw StateError(
                                        'Your session changed. Refresh report history.');
                                  await widget.client.answerQuestion(
                                      query: scope,
                                      sessionToken: token,
                                      bugId: bug['id'],
                                      requestId: question['id'],
                                      option: option,
                                      answer: answer);
                                  if (mounted) await load();
                                }),
                        ]))),
          if (cursor != null)
            TextButton(
                onPressed: loading ? null : () => load(more: true),
                child: const Text('Show more')),
        ]))
      ]));

  Iterable<Map> questions(Map bug) {
    final entries = <String, Map>{};
    for (final q in [
      if (bug['information_requests'] is List) ...bug['information_requests'],
      bug['information_request']
    ]) {
      if (q is Map && q['id'] is String && q['question'] is String)
        entries[q['id']] = q;
    }
    return entries.values;
  }
}

class _Question extends StatefulWidget {
  const _Question(
      {super.key,
      required this.question,
      required this.owner,
      required this.submit});
  final Map question;
  final bool owner;
  final Future<void> Function(String?, String) submit;
  @override
  State<_Question> createState() => _QuestionState();
}

class _QuestionState extends State<_Question> {
  String? option, error;
  String answer = '';
  bool sending = false, sent = false;
  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final reply = q['answer'];
    final allowed = reply == null &&
        (q['status'] == null || q['status'] == 'open') &&
        (q.containsKey('response_allowed')
            ? q['response_allowed'] == true
            : widget.owner);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      Text(q['question'], style: Theme.of(context).textTheme.titleSmall),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final choice
            in (q['options'] is List ? q['options'] as List : const [])
                .whereType<String>())
          ChoiceChip(
            label: Text(choice),
            selected:
                reply is Map ? reply['option'] == choice : option == choice,
            onSelected: allowed && !sent && !sending
                ? (selected) =>
                    setState(() => option = selected ? choice : null)
                : null,
          ),
      ]),
      if (reply is Map)
        Text([reply['option'], reply['text']].whereType<String>().join(' · '))
      else if (!allowed)
        const Text('The reporter has been asked.')
      else if (sent)
        const Text('Answer sent.')
      else ...[
        if (q['allows_written_answer'] != false)
          TextField(
              enabled: !sending,
              maxLength: 4000,
              maxLines: null,
              decoration: const InputDecoration(labelText: 'Your answer'),
              onChanged: (v) => setState(() => answer = v)),
        if (error != null)
          Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        FilledButton(
            onPressed: sending || (option == null && answer.trim().isEmpty)
                ? null
                : () async {
                    if (sending) return;
                    setState(() {
                      sending = true;
                      error = null;
                    });
                    try {
                      await widget.submit(option, answer);
                      if (mounted) setState(() => sent = true);
                    } catch (e) {
                      if (mounted) setState(() => error = e.toString());
                    } finally {
                      if (mounted) setState(() => sending = false);
                    }
                  },
            child: Text(sending ? 'Sending…' : 'Send answer')),
      ]
    ]);
  }
}
