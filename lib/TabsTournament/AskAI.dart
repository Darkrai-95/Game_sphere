import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String text;
  final String role; // 'user' or 'assistant'

  ChatMessage({required this.text, required this.role});
}

class AskAITab extends StatefulWidget {
  final String tournamentId;
  final Map<String, dynamic> tournamentData;

  const AskAITab({
    super.key, 
    required this.tournamentId, 
    required this.tournamentData
  });

  @override
  State<AskAITab> createState() => _AskAITabState();
}

class _AskAITabState extends State<AskAITab> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  final List<ChatMessage> _messages = [];
  String _systemContext = "";
  
  bool _isLoadingAI = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _initializeContext();
  }

  /// Fetches participants, maps team_ids to actual team names from /teams,
  /// builds match summaries, and initializes the system context.
  Future<void> _initializeContext() async {
    try {
      StringBuffer buffer = StringBuffer();
      buffer.writeln("You are the official AI assistant for a tournament app called GameSphere.");
      buffer.writeln("Answer concisely and politely based ONLY on the following tournament data. If asked something outside this data, politely state that you do not have that information.\n");
      
      buffer.writeln("--- TOURNAMENT INFO ---");
      buffer.writeln("Name: ${widget.tournamentData['title']}");
      buffer.writeln("Status: ${widget.tournamentData['status'] ?? 'Ongoing'}");
      buffer.writeln("Format: ${widget.tournamentData['format'] ?? 'Custom'}");

      Map<String, String> teamIdToName = {};
      Map<String, String> slotToTeamName = {};

      // 1. Fetch Participants & Resolve Team Names from /teams collection
      var participantsSnap = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .collection('participants')
          .get();

      List<Map<String, dynamic>> participantsList = [];

      for (var doc in participantsSnap.docs) {
        var p = doc.data();
        String? teamId = p['team_id'];
        String group = p['group'] ?? '';
        int slotIndex = p['slot_index'] ?? 0;

        String teamName = "Unknown Team";

        if (teamId != null && teamId.isNotEmpty) {
          if (!teamIdToName.containsKey(teamId)) {
            var teamDoc = await FirebaseFirestore.instance.collection('teams').doc(teamId).get();
            if (teamDoc.exists && teamDoc.data() != null) {
              teamIdToName[teamId] = teamDoc.data()?['name'] ?? "Unknown Team";
            } else {
              teamIdToName[teamId] = "Unassigned Slot";
            }
          }
          teamName = teamIdToName[teamId]!;
        }

        slotToTeamName["${group}_$slotIndex"] = teamName;

        participantsList.add({
          'name': teamName,
          'group': group,
          'points': p['points'] ?? 0,
          'played': p['played'] ?? 0,
          'won': p['won'] ?? 0,
          'drawn': p['drawn'] ?? 0,
          'lost': p['lost'] ?? 0,
          'gd': p['difference'] ?? 0,
        });
      }

      buffer.writeln("\n--- PARTICIPATING TEAMS & STANDINGS ---");
      if (participantsList.isEmpty) {
        buffer.writeln("No teams registered yet.");
      } else {
        for (var p in participantsList) {
          buffer.writeln("Team: ${p['name']} (Group ${p['group']}) | Pld: ${p['played']} | W: ${p['won']}, D: ${p['drawn']}, L: ${p['lost']} | Pts: ${p['points']} | GD: ${p['gd']}");
        }
      }

      // 2. Fetch Matches & Resolve Home/Away Team Names
      var matchSnap = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .collection('matches')
          .orderBy('order')
          .get();

      buffer.writeln("\n--- FIXTURES & RESULTS ---");
      if (matchSnap.docs.isEmpty) {
        buffer.writeln("No matches scheduled yet.");
      } else {
        for (var doc in matchSnap.docs) {
          var m = doc.data();
          String group = m['group'] ?? '';
          
          String homeName = "TBD";
          if (m['home_team_id'] != null && teamIdToName.containsKey(m['home_team_id'])) {
            homeName = teamIdToName[m['home_team_id']]!;
          } else if (m['home_slot'] != null) {
            homeName = slotToTeamName["${group}_${m['home_slot']}"] ?? "TBD";
          }

          String awayName = "TBD";
          if (m['away_team_id'] != null && teamIdToName.containsKey(m['away_team_id'])) {
            awayName = teamIdToName[m['away_team_id']]!;
          } else if (m['away_slot'] != null) {
            awayName = slotToTeamName["${group}_${m['away_slot']}"] ?? "TBD";
          }

          String scoreStr = (m['status'] == 'completed')
              ? "${m['home_score']} - ${m['away_score']}"
              : "Not Played";

          buffer.writeln("Group $group R${m['round'] ?? 1}: $homeName vs $awayName | Status: ${m['status']} | Score: $scoreStr");
        }
      }

      _systemContext = buffer.toString();
      // debugPrint("System Context Built Successfully:\n$_systemContext");

      setState(() {
        _messages.add(ChatMessage(
          text: "Connected! I've loaded all team details and match results for ${widget.tournamentData['title']}. What would you like to know?", 
          role: 'assistant'
        ));
        _isLoadingAI = false;
      });
    } catch (e) {
      debugPrint("Error building context: $e");
      setState(() {
        _messages.add(ChatMessage(
          text: "Failed to build tournament context. Error: $e", 
          role: 'assistant'
        ));
        _isLoadingAI = false;
      });
    }
  }

  // Send prompt to Groq API using 'llama-3.1-8b-instant'
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text: text, role: 'user'));
      _isSending = true;
    });
    
    _controller.clear();
    _scrollToBottom();

    final apiKey = dotenv.env['GROQ_API_KEY'] ?? '';
    
    if (apiKey.isEmpty) {
      _showError("API Key is missing. Check your .env file.");
      return;
    }

    try {
      List<Map<String, String>> apiMessages = [
        {'role': 'system', 'content': _systemContext}
      ];
      
      for (var msg in _messages) {
        apiMessages.add({'role': msg.role, 'content': msg.text});
      }

      final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'openai/gpt-oss-20b',
          'messages': apiMessages,
          'temperature': 0.3,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final aiReply = data['choices'][0]['message']['content'];
        
        setState(() {
          _messages.add(ChatMessage(text: aiReply, role: 'assistant'));
        });
      } else {
        debugPrint("Groq Error Body: ${response.body}");
        _showError("API Error ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      debugPrint("Network Exception: $e");
      _showError("Connection error: $e");
    } finally {
      setState(() {
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  void _showError(String errorMsg) {
    setState(() {
      _messages.add(ChatMessage(text: "⚠️ $errorMsg", role: 'assistant'));
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingAI) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blueAccent),
            SizedBox(height: 16),
            Text("Fetching team and fixture data...", style: TextStyle(color: Colors.white54))
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return _buildMessageBubble(_messages[index]);
            },
          ),
        ),
        if (_isSending)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(color: Colors.blueAccent),
          ),
        _buildInputArea(),
      ],
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    bool isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? Colors.blueAccent : const Color(0xFF1E1E24),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(0),
            bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(16),
          ),
          border: isUser ? null : Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: msg.text.startsWith("⚠️") ? Colors.redAccent : Colors.white, 
            fontSize: 15
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Ask about matches, standings, or teams...",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.black12,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.blueAccent,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _isSending ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}