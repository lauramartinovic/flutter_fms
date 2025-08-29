// lib/screens/history/history_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_fms/services/firestore_service.dart';
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:flutter_fms/screens/video_player/video_player.dart'; // <--- ADD THIS IMPORT

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('FMS Session History'),
        centerTitle: true,
      ),
      body: StreamBuilder<List<FMSSessionModel>>(
        stream: firestoreService.getFMSSessionsForCurrentUser(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            print("Error loading FMS sessions: ${snapshot.error}"); // For debugging
            return Center(
              child: Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No FMS sessions recorded yet.\nStart by recording a new session!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final List<FMSSessionModel> sessions = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final FMSSessionModel session = sessions[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                elevation: 4.0,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Session Date
                      Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(session.timestamp),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      // FMS Rating
                      Text(
                        'Rating: ${session.rating}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4.0),
                      // Notes
                      Text(
                        'Notes: ${session.notes.isEmpty ? 'No notes' : session.notes}',
                        style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 12.0),
                      // Video Link/Button (MODIFIED)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VideoPlayerScreen(videoUrl: session.videoUrl),
                              ),
                            );
                          },
                          icon: const Icon(Icons.play_circle_fill),
                          label: const Text('View Video'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
