// dgvault — password health audit panel (real PasswordAuditor engine).
//
// Runs the pure-Dart audit over the decrypted in-memory vault (excluding the
// Recycle Bin) and renders findings grouped by severity: empty, weak, reused,
// similar, and old passwords. Read-only — it surfaces problems; fixing them is
// done by editing the entries.

import 'package:flutter/material.dart';

import 'package:dgvault/core/core.dart';

import '../state/vault_controller.dart';
import '../theme/terminal_theme.dart';

bool _auditOpen = false;

void showAudit(BuildContext context, VaultController controller) {
  if (_auditOpen) return;
  _auditOpen = true;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: TermColors.bg,
    isScrollControlled: true,
    builder: (_) => _AuditSheet(controller: controller),
  ).whenComplete(() => _auditOpen = false);
}

class _AuditSheet extends StatelessWidget {
  const _AuditSheet({required this.controller});
  final VaultController controller;

  List<Entry> get _entries {
    final root = controller.rootGroup;
    if (root == null) return const [];
    final bin = controller.recycleBinUuid;
    return (bin == null
            ? root.allEntries
            : root.entriesExcluding({bin}))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final findings = PasswordAuditor().audit(entries, now: DateTime.now());
    // Most severe first, then by issue type for stable grouping.
    findings.sort((a, b) {
      final s = b.severity.index.compareTo(a.severity.index);
      return s != 0 ? s : a.issue.index.compareTo(b.issue.index);
    });

    final clean = findings.isEmpty && entries.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '// PASSWORD AUDIT',
                    style: mono(
                      size: 12,
                      color: TermColors.textDim,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: 'Close',
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.close,
                            size: 18, color: TermColors.textDim,),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _summary(entries.length, findings),
              const SizedBox(height: 12),
              if (clean)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    '✓ no issues found across ${entries.length} entries.',
                    style: mono(size: 14, color: TermColors.green),
                  ),
                )
              else if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'no entries to audit.',
                    style: mono(size: 14, color: TermColors.textFaint),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: findings.length,
                    itemBuilder: (_, i) => _FindingRow(findings[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(int total, List<AuditFinding> findings) {
    int count(AuditIssue issue) =>
        findings.where((f) => f.issue == issue).length;
    final chips = <Widget>[
      _StatChip('entries', total, TermColors.textDim),
      if (count(AuditIssue.emptyPassword) > 0)
        _StatChip('empty', count(AuditIssue.emptyPassword), TermColors.red),
      if (count(AuditIssue.weakPassword) > 0)
        _StatChip('weak', count(AuditIssue.weakPassword), TermColors.red),
      if (count(AuditIssue.reusedPassword) > 0)
        _StatChip('reused', count(AuditIssue.reusedPassword), TermColors.amber),
      if (count(AuditIssue.similarPassword) > 0)
        _StatChip(
            'similar', count(AuditIssue.similarPassword), TermColors.amber,),
      if (count(AuditIssue.oldPassword) > 0)
        _StatChip('old', count(AuditIssue.oldPassword), TermColors.cyan),
    ];
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6)),
          color: color.withValues(alpha: 0.08),
        ),
        child: Text('$count $label',
            style: mono(size: 12, color: color, weight: FontWeight.w600),),
      );
}

class _FindingRow extends StatelessWidget {
  const _FindingRow(this.finding);
  final AuditFinding finding;

  Color get _color {
    switch (finding.severity) {
      case AuditSeverity.high:
        return TermColors.red;
      case AuditSeverity.medium:
        return TermColors.amber;
      case AuditSeverity.low:
        return TermColors.cyan;
      case AuditSeverity.info:
        return TermColors.textDim;
    }
  }

  String get _issueLabel {
    switch (finding.issue) {
      case AuditIssue.emptyPassword:
        return 'empty';
      case AuditIssue.weakPassword:
        return 'weak';
      case AuditIssue.reusedPassword:
        return 'reused';
      case AuditIssue.similarPassword:
        return 'similar';
      case AuditIssue.oldPassword:
        return 'old';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: TermColors.surfaceAlt,
        border: Border(left: BorderSide(color: _color, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: _color.withValues(alpha: 0.15)),
                child: Text(_issueLabel,
                    style: mono(
                        size: 11, color: _color, weight: FontWeight.w700,),),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  finding.entryTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(size: 13, color: TermColors.textBright),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(finding.detail,
              style: mono(size: 12, color: TermColors.textDim),),
        ],
      ),
    );
  }
}
