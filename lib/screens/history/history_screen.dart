import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_fms/services/firestore_service.dart';
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:flutter_fms/utils/pose_analysis_utils.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _firestore = FirestoreService();
  ExerciseType? _exerciseFilter; // null = All
  bool _sortDesc = true; // newest first
  String _query = '';
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  String _formatTs(DateTime ts) {
    if (ts.millisecondsSinceEpoch == 0) return 'Syncing…';
    return _dateFmt.format(ts.toLocal());
  }

  List<FMSSessionModel> _applyFilters(List<FMSSessionModel> items) {
    final exName =
        _exerciseFilter == null
            ? null
            : (exerciseNames[_exerciseFilter!] ?? _exerciseFilter!.toString());

    var list =
        items.where((s) {
          final byExercise = exName == null || s.exercise == exName;
          if (!byExercise) return false;

          if (_query.trim().isEmpty) return true;
          final q = _query.toLowerCase();
          return s.exercise.toLowerCase().contains(q) ||
              s.rating.toString().contains(q) ||
              _formatTs(s.timestamp).toLowerCase().contains(q);
        }).toList();

    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (_sortDesc) list = list.reversed.toList();
    return list;
  }

  Future<bool?> _confirmDelete(BuildContext context, FMSSessionModel s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Delete session?'),
            content: const Text(
              'This will remove the session from history. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (ok == true && s.id != null) {
      await _firestore.deleteFMSSession(s.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Session deleted')));
      }
      return true;
    }
    return false;
  }

  Widget _buildHeader(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search (exercise, score, date)…',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ExerciseType?>(
                      isExpanded: true,
                      value: _exerciseFilter,
                      hint: const Text('Filter by exercise'),
                      items: <DropdownMenuItem<ExerciseType?>>[
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All exercises'),
                        ),
                        ...ExerciseType.values.map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(exerciseNames[e] ?? e.toString()),
                          ),
                        ),
                      ],
                      onChanged: (val) => setState(() => _exerciseFilter = val),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _sortDesc = !_sortDesc),
                  icon: Icon(_sortDesc ? Icons.south : Icons.north),
                  tooltip: _sortDesc ? 'Newest first' : 'Oldest first',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context, FMSSessionModel s) {
    final dateStr = _formatTs(s.timestamp);
    return Dismissible(
      key: ValueKey(
        s.id ?? '${s.userId}_${s.timestamp.millisecondsSinceEpoch}',
      ),
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context, s),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        elevation: 3,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 14,
          ),
          title: Text(
            s.exercise,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text('$dateStr  •  Score: ${s.rating}'),
          onTap: null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FMS Session History')),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: StreamBuilder<List<FMSSessionModel>>(
              stream: _firestore.getFMSSessionsForCurrentUser(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final raw = snapshot.data ?? [];
                final sessions = _applyFilters(raw);

                if (sessions.isEmpty) {
                  return const Center(
                    child: Text(
                      'No sessions match your filters.\nTry a different exercise, sort, or search.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: sessions.length,
                  itemBuilder: (context, i) => _buildTile(context, sessions[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
