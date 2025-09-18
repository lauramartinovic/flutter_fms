// lib/screens/history/history_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_fms/services/firestore_service.dart';
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:flutter_fms/utils/pose_analysis_utils.dart';
import 'package:flutter_fms/screens/home/edit_profile_screen.dart'; // Edit profile

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
              _formatTs(s.timestamp).toLowerCase().contains(q) ||
              s.feedback.toLowerCase().contains(q) ||
              s.notes.toLowerCase().contains(q);
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
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
                hintText: 'Search (exercise, score, date, feedback)…',
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

  // ------- FEATURES & SELF-REPORT UI HELPERS -------
  Widget _buildFeatures(Map<String, dynamic>? features) {
    if (features == null || features.isEmpty) {
      return const Text(
        'No features captured.',
        style: TextStyle(color: Colors.grey),
      );
    }

    final entries = features.entries.toList();

    // kako prikazati JEDNU stavku (key/value) bez overflowa
    Widget _featureItem(BuildContext context, MapEntry<String, dynamic> e) {
      final keyStr = e.key;
      final valStr = '${e.value}';
      final isLong = valStr.length > 24 || valStr.contains('\n');

      if (isLong) {
        // duge vrijednosti: 2 retka (key gore, value ispod)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              keyStr,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(valStr, softWrap: true),
          ],
        );
      } else {
        // kratke vrijednosti: 1 red s dvije kolone (elipse ako zafali mjesta)
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                keyStr,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                valStr,
                textAlign: TextAlign.right,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 420;

        // napravi listu widgeta (po jedan za svaki feature)
        final items =
            entries
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _featureItem(context, e),
                  ),
                )
                .toList();

        if (!isWide) {
          // usko: jedna kolona
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items,
          );
        }

        // široko: dvije kolone (prvu polovicu lijevo, drugu desno)
        final half = (items.length / 2).ceil();
        final left = items.take(half).toList();
        final right = items.skip(half).toList();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: left)),
            const SizedBox(width: 16),
            Expanded(child: Column(children: right)),
          ],
        );
      },
    );
  }

  Widget _buildPainChips(FMSSessionModel s) {
    final chips = <Widget>[];
    if (s.painLowBack) {
      chips.add(
        Chip(
          label: const Text('Bol: donja leđa'),
          avatar: const Icon(Icons.warning_amber),
          backgroundColor: Colors.orange.withOpacity(0.15),
          side: BorderSide(color: Colors.orange.shade300),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    if (s.painHamstringOrCalf) {
      chips.add(
        Chip(
          label: const Text('Bol: loža / list'),
          avatar: const Icon(Icons.warning_amber),
          backgroundColor: Colors.orange.withOpacity(0.15),
          side: BorderSide(color: Colors.orange.shade300),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    if (chips.isEmpty) {
      return const Text(
        'No pain reported.',
        style: TextStyle(color: Colors.grey),
      );
    }

    return Wrap(spacing: 8, runSpacing: 4, children: chips);
  }

  Widget _buildTile(BuildContext context, FMSSessionModel s) {
    final dateStr = _formatTs(s.timestamp);
    final hasPain = s.painLowBack || s.painHamstringOrCalf;
    final lowScore = s.rating <= 1;

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
        elevation: lowScore ? 4 : 3,
        shadowColor: lowScore ? Colors.redAccent : null,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          childrenPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 16,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  s.exercise,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (hasPain)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.health_and_safety,
                    color: Colors.orange.shade400,
                    size: 18,
                  ),
                ),
              if (lowScore)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.info, color: Colors.redAccent, size: 18),
                ),
            ],
          ),
          subtitle: Text('$dateStr  •  Score: ${s.rating}'),
          trailing: const Icon(Icons.expand_more),
          children: [
            // FEATURES
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Features',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            _buildFeatures(s.features),
            const SizedBox(height: 12),

            const Divider(),

            // SELF-REPORT & FEEDBACK
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Self-report & Feedback',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            _buildPainChips(s),
            const SizedBox(height: 8),
            if (s.feedback.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Feedback: ${s.feedback}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else if (s.notes.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Notes: ${s.notes}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No feedback recorded.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FMS Session History'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Edit Profile',
            icon: const Icon(Icons.account_circle),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),
        ],
      ),
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
