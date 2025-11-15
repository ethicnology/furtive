import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:furtive/core/logs.dart';

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

  int get _logsSize => utf8.encode(_logs.join('\n')).length ~/ 1000;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final loadedLogs = await logs.readLogs();
      setState(() {
        _logs = loadedLogs;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load logs: $e')));
      }
    }
  }

  List<String> get _filteredLogs {
    final result = _logs.toList();
    result.sort((a, b) {
      final partsA = a.split('\t');
      final partsB = b.split('\t');
      return partsB[0].compareTo(partsA[0]);
    });

    if (_startDate == null && _endDate == null) return result;

    return result.where((log) {
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
      builder:
          (context) => AlertDialog(
            title: const Text('Delete logs'),
            content: const Text(
              'Are you sure you want to delete all logs? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
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
          content: Text('${_filteredLogs.length} logs copied to clipboard'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _filteredLogs;

    return Scaffold(
      appBar: AppBar(
        title: Text('Logs'),
        actions: [
          Text(
            '$_logsSize kB',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _logs.isEmpty ? null : _deleteLogs,
            tooltip: 'Clear log',
          ),
          IconButton(
            icon: const Icon(Icons.date_range, color: Colors.white),
            onPressed: _selectDateRange,
            tooltip: 'Filter by date',
          ),
          if (_startDate != null || _endDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearDateRange,
              tooltip: 'Clear filter',
            ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _logs.isEmpty ? null : _shareLogs,
            tooltip: 'Share',
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
                              'Filtered: ${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Showing ${filteredLogs.length} of ${_logs.length}',
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
                              ? const Center(
                                child: Text(
                                  'No logs found',
                                  style: TextStyle(color: Colors.white70),
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
                                          const SnackBar(
                                            content: Text(
                                              'Log copied to clipboard',
                                            ),
                                            duration: Duration(seconds: 1),
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
