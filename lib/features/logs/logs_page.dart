import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:furtive/core/logs.dart';
import 'package:furtive/core/theme.dart';
import 'package:furtive/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<String> _logs = [];
  bool _loading = true;
  DateTime? _startDate;
  DateTime? _endDate;
  int _logsSizeKb = 0;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final loadedLogs = await logs.readLogs();
      // Compute size once on load, not on every rebuild
      final sizeKb = utf8.encode(loadedLogs.join('\n')).length ~/ 1000;
      // Sort newest-first once here, not on every rebuild in _filteredLogs.
      loadedLogs.sort((a, b) {
        final tsA = a.split('\t').first;
        final tsB = b.split('\t').first;
        return tsB.compareTo(tsA);
      });
      if (!mounted) return;
      setState(() {
        _logs = loadedLogs;
        _logsSizeKb = sizeKb;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).logsLoadError(e.toString()),
            ),
          ),
        );
      }
    }
  }

  List<String> get _filteredLogs {
    // _logs is already sorted newest-first in _loadLogs.
    if (_startDate == null && _endDate == null) return _logs;

    return _logs.where((log) {
      final parts = log.split('\t');
      if (parts.isEmpty) return false;

      try {
        final timestamp = DateTime.parse(parts[0]);
        if (_startDate != null && timestamp.isBefore(_startDate!)) return false;
        if (_endDate != null) {
          final endOfDay = DateTime(
            _endDate!.year,
            _endDate!.month,
            _endDate!.day,
            23,
            59,
            59,
            999,
          );
          if (timestamp.isAfter(endOfDay)) return false;
        }
        return true;
      } catch (e) {
        return false;
      }
    }).toList();
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
  }

  Future<void> _deleteLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.dlgDeleteLogsTitle),
          content: Text(l10n.dlgDeleteLogsConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.btnCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.btnDelete),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await logs.deleteLogs();
      await _loadLogs();
    }
  }

  Future<void> _shareLogs() async {
    if (_filteredLogs.isEmpty) return;

    final logsToShare = _filteredLogs.join('\n');
    await Clipboard.setData(ClipboardData(text: logsToShare));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).logsCopiedMsg(_filteredLogs.length),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDate(BuildContext context, DateTime date) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMd(locale).format(date);
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _filteredLogs;

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.logsTitle),
        actions: [
          Text(
            '$_logsSizeKb kB',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: kDestructive),
            onPressed: _logs.isEmpty ? null : _deleteLogs,
            tooltip: l10n.logsTooltipClear,
          ),
          IconButton(
            icon: const Icon(Icons.date_range_rounded),
            onPressed: _selectDateRange,
            tooltip: l10n.logsTooltipFilterDate,
          ),
          if (_startDate != null || _endDate != null)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              onPressed: _clearDateRange,
              tooltip: l10n.logsTooltipClearFilter,
            ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: _logs.isEmpty ? null : _shareLogs,
            tooltip: l10n.logsTooltipShare,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Container(
                color: Colors.black,
                child: Column(
                  children: [
                    if (_startDate != null && _endDate != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          children: [
                            Text(
                              l10n.logsFiltered(
                                _formatDate(context, _startDate!),
                                _formatDate(context, _endDate!),
                              ),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              l10n.logsShowingCount(
                                filteredLogs.length,
                                _logs.length,
                              ),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child:
                          filteredLogs.isEmpty
                              ? Center(
                                child: Text(
                                  AppLocalizations.of(context).logsEmpty,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                ),
                              )
                              : Scrollbar(
                                thumbVisibility: true,
                                child: ListView.builder(
                                  itemCount: filteredLogs.length,
                                  itemBuilder: (context, index) {
                                    final logLine = filteredLogs[index];
                                    final parts = logLine.split('\t');
                                    Color textColor = Colors.white;

                                    if (parts.length > 1) {
                                      textColor = switch (parts[1]) {
                                        'FINEST' => Colors.lightGreenAccent,
                                        'FINER' => Colors.lightGreen,
                                        'FINE' => Colors.green,
                                        'CONFIG' => Colors.brown,
                                        'INFO' => Colors.blue,
                                        'WARNING' => Colors.orange,
                                        'SEVERE' => Colors.red,
                                        'SHOUT' => Colors.purple,
                                        _ => Colors.white,
                                      };
                                    }

                                    final displayParts = parts.toList();
                                    if (displayParts.isNotEmpty &&
                                        displayParts[0].length > 7) {
                                      try {
                                        displayParts[0] = displayParts[0]
                                            .substring(
                                              0,
                                              displayParts[0].length - 7,
                                            );
                                      } catch (_) {}
                                    }

                                    final displayText = displayParts
                                        .where((part) => part.isNotEmpty)
                                        .join(' | ');

                                    return GestureDetector(
                                      onLongPress: () {
                                        Clipboard.setData(
                                          ClipboardData(text: logLine),
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              AppLocalizations.of(
                                                context,
                                              ).logCopiedMsg,
                                            ),
                                            duration: const Duration(
                                              seconds: 1,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 1,
                                          horizontal: 8,
                                        ),
                                        child: SelectableText(
                                          displayText,
                                          style: TextStyle(
                                            color: textColor,
                                            fontFamily: 'monospace',
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                    ),
                  ],
                ),
              ),
    );
  }
}
