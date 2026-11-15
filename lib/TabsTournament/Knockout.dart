import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gamesphere/TheProvider.dart';
import 'package:provider/provider.dart';

class KnockoutTab extends StatefulWidget {
  final Map<String, dynamic> tournamentData;

  const KnockoutTab({super.key, required this.tournamentData});

  @override
  State<KnockoutTab> createState() => _KnockoutTabState();
}

class _KnockoutTabState extends State<KnockoutTab> with SingleTickerProviderStateMixin{
  late int qualifies;
  late int totalRounds;
  late String tournamentId;
  bool _isLoading = false;
  bool _isStarted = false;
  final TransformationController _transformationController = TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _zoomAnimation;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    tournamentId = widget.tournamentData['tournament_id'];
    qualifies = widget.tournamentData['qualifies_to_KO'] ?? 8;
    if (qualifies < 2) qualifies = 2;
    totalRounds = (log(qualifies) / log(2)).ceil();
    _isStarted = widget.tournamentData['is_ko_started'] ?? false;

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(() {
      _transformationController.value = _zoomAnimation!.value;
    });

    _initializeBracketIfNeeded();
  }

  @override
  void dispose(){
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details){
    _doubleTapDetails = details;
  }

  void _handleDoubleTap(){
    final Matrix4 currentMatrix = _transformationController.value;
    final double currentScale = currentMatrix.getMaxScaleOnAxis();

    Matrix4 targetMatrix;

    if(currentScale > 1.2) {
      targetMatrix = Matrix4.identity();
    }
    else{
      final position = _doubleTapDetails!.localPosition;
      const double targetScale = 1.8;

      final double x = -position.dx * (targetScale - 1);
      final double y = -position.dy * (targetScale - 1);

      targetMatrix = Matrix4.identity()
        ..translate(x, y)
        ..scale(targetScale);
    }

    _zoomAnimation = Matrix4Tween(
      begin: currentMatrix,
      end: targetMatrix,
    ).animate(CurveTween(curve: Curves.easeInOut).animate(_animationController));

    _animationController.forward(from: 0);
  }

  Future<void> _initializeBracketIfNeeded() async {
    var snap = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(tournamentId)
        .collection('ko_matches')
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      int initialMatches = qualifies ~/ 2;

      for (int r = 0; r < totalRounds; r++) {
        int matchesInRound = initialMatches ~/ pow(2, r);
        for (int m = 0; m < matchesInRound; m++) {
          DocumentReference docRef = FirebaseFirestore.instance
              .collection('tournaments')
              .doc(tournamentId)
              .collection('ko_matches')
              .doc('ko_r${r}_m${m}');

          batch.set(docRef, {
            'round': r,
            'match_index': m,
            'home_placeholder': null,
            'away_placeholder': null,
            'home_team_id': null,
            'away_team_id': null,
            'home_score': null,
            'away_score': null,
            // NEW: Two-Legged Tracking Fields
            'home_score_leg1': null,
            'away_score_leg1': null,
            'home_score_leg2': null,
            'away_score_leg2': null,
            'status_leg1': 'pending',
            'status_leg2': 'pending',
            'winner_id': null,
            'status': 'pending',
          });
        }
      }
      await batch.commit();
    }
  }

  String _getRoundName(int roundIndex) {
    if (roundIndex == totalRounds - 1) return "FINAL";
    if (roundIndex == totalRounds - 2) return "SEMI-FINALS";
    if (roundIndex == totalRounds - 3) return "QUARTER-FINALS";
    return "ROUND OF ${pow(2, totalRounds - roundIndex)}";
  }

  Future<void> _attemptStartPlayoffs() async {
    setState(() => _isLoading = true);
    
    try {
      var r0Snap = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId)
          .collection('ko_matches')
          .where('round', isEqualTo: 0)
          .get();

      bool allDefined = true;
      for (var doc in r0Snap.docs) {
        var data = doc.data();
        if (data['home_placeholder'] == null || data['away_placeholder'] == null) {
          allDefined = false;
          break;
        }
      }

      if (!allDefined) {
        setState(() => _isLoading = false);
        _showMissingPlaceholdersDialog();
        return;
      }
      
      int format = widget.tournamentData['format_index'] ?? 0;
      
      if (format != 2) {
        var pendingMatches = await FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('matches')
          .where('status', isEqualTo: 'pending').limit(1).get();

        if (pendingMatches.docs.isNotEmpty) {
          setState(() => _isLoading = false);
          _showWarningDialog();
          return;
        }
      }

      setState(() => _isLoading = false);
      await _executeStartPlayoffs();

    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar("Something went wrong.");
    }
  }

  Future<void> _undoBrackets() async {
    setState(() => _isLoading = true);
    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      var koMatches = await FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('ko_matches').get();

      for (var doc in koMatches.docs) {
        batch.update(doc.reference, {
          'home_team_id': null, 'away_team_id': null,
          'home_score': null, 'away_score': null,
          // NEW: Reset leg states
          'home_score_leg1': null, 'away_score_leg1': null,
          'home_score_leg2': null, 'away_score_leg2': null,
          'status_leg1': 'pending', 'status_leg2': 'pending',
          'winner_id': null, 'status': 'pending',
        });
      }

      batch.update(FirebaseFirestore.instance.collection('tournaments').doc(tournamentId), {'is_ko_started': false});
      await batch.commit();
      setState(() => _isStarted = false);
      _showSnackBar("Play-offs reset.");
    } catch (e) {
      _showSnackBar("Error resetting: something went wrong.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showMissingPlaceholdersDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Setup Incomplete", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          "You cannot start the play-offs yet. Please assign all placeholders (or BYEs) for every match in the first round.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(color: Color(0xFF00E5FF))),
          ),
        ],
      ),
    );
  }

  Future<void> _executeStartPlayoffs() async {
    setState(() => _isLoading = true);
    try {
      var partsSnap = await FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('participants').get();

      Map<String, List<Map<String, dynamic>>> standings = {};
      for (var doc in partsSnap.docs) {
        var d = doc.data();
        standings.putIfAbsent(d['group'], () => []).add(d);
      }

      standings.forEach((group, list) {
        list.sort((a, b) {
          int cmp = (b['points'] ?? 0).compareTo(a['points'] ?? 0);
          if (cmp != 0) return cmp;
          cmp = (b['difference'] ?? 0).compareTo(a['difference'] ?? 0);
          if (cmp != 0) return cmp;
          cmp = (b['scored'] ?? 0).compareTo(a['scored'] ?? 0);
          if (cmp != 0) return cmp;
          return (a['slot_index'] ?? 0).compareTo(b['slot_index'] ?? 0);
        });
      });

      // Helper to resolve placeholders including the new format 2 direct assignments
      String? resolvePlaceholder(String? placeholder) {
        if (placeholder == null || placeholder == "BYE") return placeholder;
        if (placeholder.startsWith("TEAM_")) return placeholder.substring(5); // Knockout Only format direct extraction

        List<String> parts = placeholder.split('_');
        if (parts.length != 2) return null;
        
        int posIndex = int.parse(parts[0]) - 1;
        String group = parts[1];
        
        if (standings.containsKey(group) && standings[group]!.length > posIndex) {
          return standings[group]![posIndex]['team_id'];
        }
        return null;
      }

      var r0Snap = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId)
          .collection('ko_matches')
          .where('round', isEqualTo: 0)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (var doc in r0Snap.docs) {
        var match = doc.data();
        int mIndex = match['match_index'];
        String? hTeam = resolvePlaceholder(match['home_placeholder']);
        String? aTeam = resolvePlaceholder(match['away_placeholder']);

        bool hIsBye = hTeam == "BYE";
        bool aIsBye = aTeam == "BYE";

        if (hIsBye || aIsBye) {
          String? advancingTeam = (hIsBye && aIsBye) ? null : (hIsBye ? aTeam : hTeam);
          
          batch.update(doc.reference, {
            'home_team_id': hIsBye ? null : hTeam,
            'away_team_id': aIsBye ? null : aTeam,
            'status': 'completed',
            // NEW: Automatically complete legs for BYE assignments
            'status_leg1': 'completed', 'status_leg2': 'completed',
            'home_score_leg1': 0, 'away_score_leg1': 0,
            'home_score_leg2': 0, 'away_score_leg2': 0,
            'home_score': 0, 'away_score': 0,
            'winner_id': advancingTeam,
          });

          if (totalRounds > 1) {
            String nextMatchId = 'ko_r1_m${mIndex ~/ 2}';
            DocumentReference nextRef = FirebaseFirestore.instance
                .collection('tournaments')
                .doc(tournamentId)
                .collection('ko_matches')
                .doc(nextMatchId);
            
            if (mIndex % 2 == 0) {
              batch.update(nextRef, {'home_team_id': advancingTeam});
            } else {
              batch.update(nextRef, {'away_team_id': advancingTeam});
            }
          }
        } else {
          batch.update(doc.reference, {
            'home_team_id': hTeam,
            'away_team_id': aTeam,
          });
        }
      }

      batch.update(FirebaseFirestore.instance.collection('tournaments').doc(tournamentId), {
        'is_ko_started': true
      });

      await batch.commit();

      setState(() {
        _isStarted = true;
      });
      
    } catch (e) {
      if (mounted) {
        _showSnackBar("Something went wrong.");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showWarningDialog({bool undoCall = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text("Warning", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
        content: Text(
          undoCall? "Are you sure you want to undo this phase? All teams and match results will be removed from the phase."
            : "Not all matches in the group phase have been played. "
            "Are you sure you want to lock the standings and start the Play-offs now?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              if (undoCall) {
                _undoBrackets();
              } else {
                _executeStartPlayoffs();
              }
            },
            child: Text(undoCall? "Undo" : "Start Anyway", style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    bool isAdmin = (widget.tournamentData['admins'] as List).contains(userProvider.uid);
    int format = widget.tournamentData['format_index'] ?? 0;

    int initialMatches = qualifies ~/ 2;
    double requiredHeight = max(initialMatches * 100.0, MediaQuery.of(context).size.height * 0.7);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tournaments')
            .doc(tournamentId)
            .collection('ko_matches')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          Map<String, Map<String, dynamic>> matchMap = {};
          for (var doc in snapshot.data!.docs) {
            matchMap[doc.id] = doc.data() as Map<String, dynamic>;
          }

          return Column(
            children: [
              if (isAdmin)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.transparent,
                  child: Center(
                    child: _isLoading 
                        ? const CircularProgressIndicator(color: Color(0xFF00E5FF))
                        : ElevatedButton.icon(
                            onPressed: () {_isStarted? _showWarningDialog(undoCall: true) :_attemptStartPlayoffs();},
                            icon: _isStarted? null: const Icon(Icons.play_arrow),
                            label: Text(_isStarted? "UNDO PLAY-OFFS" : "START PLAY-OFFS", style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isStarted? Theme.of(context).colorScheme.primary :const Color(0xFF00E5FF),
                              foregroundColor: _isStarted? Colors.white :const Color(0xFF0E0E12),
                              padding: EdgeInsets.symmetric(horizontal: _isStarted? 20:24, vertical: _isStarted? 7:10),
                            ),
                          ),
                  ),
                ),

              Expanded(
                child: GestureDetector(
                  onDoubleTapDown: _handleDoubleTapDown,
                  onDoubleTap: _handleDoubleTap,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    constrained: false,
                    boundaryMargin: EdgeInsets.all(context.isMobile? 0: 100),
                    minScale: 0.4,
                    maxScale: 2.0,
                    child: Container(
                      height: requiredHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: List.generate(totalRounds * 2 - 1, (index) {
                              if (index % 2 != 0) return const SizedBox(width: 50);
                              return SizedBox(
                                width: 220,
                                child: Center(
                                  child: Text(
                                    _getRoundName(index ~/ 2),
                                    style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 14),
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 20),
                          
                          Expanded(
                            child: Row(
                              children: List.generate(totalRounds * 2 - 1, (index) {
                                int roundIndex = index ~/ 2;
                                if (index % 2 != 0) {
                                  int prevRoundMatches = initialMatches ~/ pow(2, roundIndex);
                                  return _buildConnectorColumn(prevRoundMatches, roundIndex, matchMap);
                                } else {
                                  int matchCount = initialMatches ~/ pow(2, roundIndex);
                                  return _buildMatchColumn(matchCount, roundIndex, matchMap, isAdmin, format);
                                }
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildMatchColumn(int matchCount, int roundIndex, Map<String, Map<String, dynamic>> matchMap, bool isAdmin, int format) {
    return SizedBox(
      width: 230, // MODIFIED: slightly wider for 3-score columns
      child: Column(
        children: List.generate(matchCount, (index) {
          String docId = 'ko_r${roundIndex}_m$index';
          var matchData = matchMap[docId];

          return Expanded(
            child: Center(
              child: _MatchCard(
                matchData: matchData,
                roundIndex: roundIndex,
                matchIndex: index,
                isStarted: _isStarted,
                isAdmin: isAdmin,
                tournamentId: tournamentId,
                totalRounds: totalRounds, // NEW
                isTwoLegged: widget.tournamentData['two_legged_knockout'] ?? false, // NEW
                groupCount: widget.tournamentData['no_of_groups'] ?? 1,
                teamsPerGroup: widget.tournamentData['teams_per_group'] ?? 1,
                format: format,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildConnectorColumn(int prevRoundMatches, int prevRoundIndex, Map<String, Map<String, dynamic>> matchMap) {

    // here, for the connector paths, we are just keeping boolean count of KO matches that are already completed
    List<bool> completedMatches = [];
    for(int i=0; i<prevRoundMatches; i++){
      String docId = 'ko_r${prevRoundIndex}_m$i';
      bool isCompleted = matchMap[docId]?['status'] == 'completed';
      completedMatches.add(isCompleted);
    }

    return SizedBox(
      width: 50,
      child: CustomPaint(
        painter: BracketConnectorPainter(prevRoundMatches: prevRoundMatches, isStarted: _isStarted, completedMatches: completedMatches),
        child: Container(),
      ),
    );
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1E1E24))
    );
  }
}

class _MatchCard extends StatelessWidget {
  final Map<String, dynamic>? matchData;
  final int roundIndex;
  final int matchIndex;
  final bool isStarted;
  final bool isAdmin;
  final String tournamentId;
  final int totalRounds; // NEW
  final bool isTwoLegged; // NEW
  final int groupCount;
  final int teamsPerGroup;
  final int format;

  const _MatchCard({
    required this.matchData,
    required this.roundIndex,
    required this.matchIndex,
    required this.isStarted,
    required this.isAdmin,
    required this.tournamentId,
    required this.totalRounds,
    required this.isTwoLegged,
    required this.groupCount,
    required this.teamsPerGroup,
    required this.format,
  });

  void _showSetupDialog(BuildContext context, bool isHome) {
    if (roundIndex != 0) return;

    int selectedPosition = 1;
    String selectedGroup = "A";
    bool isBye = false;
    String? selectedTeamId;

    Future<List<Map<String, dynamic>>>? teamsFuture;
    
    // if Knockout Only
    if (format == 2) {
      teamsFuture = FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId)
          .collection('participants')
          .get()
          .then((snap) async {
            List<Map<String, dynamic>> teams = [];
            for (var doc in snap.docs) {
              if (doc['team_id'] != null) {
                var tDoc = await FirebaseFirestore.instance.collection('teams').doc(doc['team_id']).get();
                if (tDoc.exists) {
                  teams.add({'id': doc['team_id'], 'name': tDoc['name']});
                }
              }
            }
            return teams;
          });
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E24),
            title: const Text("Assign Placeholder", style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text("Set as BYE", style: TextStyle(color: Colors.white)),
                  activeColor: const Color(0xFF00E5FF),
                  value: isBye,
                  onChanged: (val) => setState(() => isBye = val),
                ),
                if (!isBye) ...[
                  const Divider(color: Colors.white10),
                  
                  if (format == 2)
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: teamsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty){
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text("No teams registered yet. Please add participants.", style: TextStyle(color: Colors.redAccent)),
                          );
                        }
                        List<Map<String, dynamic>> teams = snapshot.data!;
                        if (selectedTeamId == null) selectedTeamId = teams.first['id'];

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Select Team:", style: TextStyle(color: Colors.grey)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: selectedTeamId,
                                  dropdownColor: const Color(0xFF1E1E24),
                                  style: const TextStyle(color: Colors.white),
                                  items: teams.map((t) => DropdownMenuItem<String>(
                                    value: t['id'],
                                    child: Text(t['name'], overflow: TextOverflow.ellipsis, maxLines: 1)
                                  )).toList(),
                                  onChanged: (val) => setState(() => selectedTeamId = val),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Position:", style: TextStyle(color: Colors.grey)),
                        DropdownButton<int>(
                          value: selectedPosition,
                          dropdownColor: const Color(0xFF1E1E24),
                          style: const TextStyle(color: Colors.white),
                          items: List.generate(teamsPerGroup, (i) => i + 1)
                              .map((e) => DropdownMenuItem(value: e, child: Text("$e"))).toList(),
                          onChanged: (val) => setState(() => selectedPosition = val!),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Group:", style: TextStyle(color: Colors.grey)),
                        DropdownButton<String>(
                          value: selectedGroup,
                          dropdownColor: const Color(0xFF1E1E24),
                          style: const TextStyle(color: Colors.white),
                          items: List.generate(groupCount, (i) => String.fromCharCode(65 + i))
                              .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (val) => setState(() => selectedGroup = val!),
                        ),
                      ],
                    ),
                  ]
                ]
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
                onPressed: () async {
                  String value;
                  if (isBye) {
                    value = "BYE";
                  } else if (format == 2) {
                    value = "TEAM_$selectedTeamId";
                  } else {
                    value = "${selectedPosition}_$selectedGroup";
                  }

                  await FirebaseFirestore.instance
                      .collection('tournaments')
                      .doc(tournamentId)
                      .collection('ko_matches')
                      .doc('ko_r${roundIndex}_m$matchIndex')
                      .update({
                        isHome ? 'home_placeholder' : 'away_placeholder': value
                      });
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text("Save"),
              )
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (matchData == null) return const SizedBox();

    bool isCompleted = matchData!['status'] == 'completed';
    bool isHomeBye = matchData!['home_placeholder'] == "BYE";
    bool isAwayBye = matchData!['away_placeholder'] == "BYE";
    if(isHomeBye && isAwayBye) isCompleted = false;

    bool homeWinner = isCompleted? (matchData!['winner_id'] == matchData!['home_team_id'] ? true: false) : false;
    bool isSet = matchData!['away_team_id'] != null && matchData!['away_team_id'].toString().isNotEmpty
                 && matchData!['home_team_id'] != null && matchData!['away_team_id'].toString().isNotEmpty;
 
    bool showLegs = isTwoLegged && (roundIndex != totalRounds - 1);

    return Container(
      width: showLegs ? 250 : 230, // MODIFIED: Expand card to fit Leg1/Leg2/Agg safely
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(!isSet? 0.3 : 1.0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 5, offset: const Offset(0, 3))]
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: InkWell(
              onTap: (!isStarted && isAdmin) ? () => _showSetupDialog(context, true) : null,
              child: _TeamRowLive(
                teamId: matchData!['home_team_id'],
                rawPlaceholder: matchData!['home_placeholder'],
                matchData: matchData, // NEW: Pass map directly for all scores
                isHome: true, // NEW
                showLegs: showLegs, // NEW
                isWinner: isCompleted? homeWinner : false,
                isAnyBye: isAwayBye || isHomeBye,
              ),
            ),
          ),
          Divider(height: 2, color: const Color(0xFF00E5FF).withOpacity(!isSet? 0.3 : 1.0)),
          Expanded(
            child: InkWell(
              onTap: (!isStarted && isAdmin) ? () => _showSetupDialog(context, false) : null,
              child: _TeamRowLive(
                teamId: matchData!['away_team_id'],
                rawPlaceholder: matchData!['away_placeholder'],
                matchData: matchData,
                isHome: false,
                showLegs: showLegs,
                isWinner: isCompleted? !homeWinner : false,
                isAnyBye: isAwayBye || isHomeBye,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamRowLive extends StatelessWidget {
  final String? teamId;
  final String? rawPlaceholder;
  final Map<String, dynamic>? matchData; // NEW
  final bool isHome; // NEW
  final bool showLegs; // NEW
  final bool isWinner;
  final bool isAnyBye;

  const _TeamRowLive({
    required this.teamId,
    required this.rawPlaceholder,
    required this.matchData,
    required this.isHome,
    required this.showLegs,
    required this.isWinner,
    required this.isAnyBye
  });

  String _getDisplayName() {
    if (rawPlaceholder == null) return "TBD";
    if (rawPlaceholder == "BYE") return "BYE";
    var parts = rawPlaceholder!.split('_');
    
    // Display Group Placeholder naturally
    if (parts.length == 2 && parts[0] != "TEAM") {
      String pos = parts[0];
      String suffix = pos == "1" ? "st" : pos == "2" ? "nd" : pos == "3" ? "rd" : "th";
      return "$pos$suffix Group ${parts[1]}";
    }
    return "TBD";
  }

  Future<Map<String, dynamic>> _fetchTeamDetails() async {
    String? targetId = teamId;
    
    // Fallback: If not locked yet, extract direct assignment from placeholder
    if ((targetId == null || targetId.isEmpty) && rawPlaceholder != null && rawPlaceholder!.startsWith("TEAM_")) {
      targetId = rawPlaceholder!.substring(5);
    }
    
    if (targetId == null || targetId.isEmpty) return {};
    
    var doc = await FirebaseFirestore.instance.collection('teams').doc(targetId).get();
    return doc.exists ? doc.data() as Map<String, dynamic> : {};
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchTeamDetails(),
      builder: (context, snapshot) {
        String displayName = _getDisplayName();
        String? logoUrl;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          displayName = snapshot.data!['name'] ?? "Unknown";
          logoUrl = snapshot.data!['logo_url'];
        }

        // NEW: Retrieve granular scores
        String l1 = isAnyBye ? "-" : (isHome ? "${matchData!['home_score_leg1'] ?? '-'}" : "${matchData!['away_score_leg1'] ?? '-'}");
        String l2 = isAnyBye ? "-" : (isHome ? "${matchData!['home_score_leg2'] ?? '-'}" : "${matchData!['away_score_leg2'] ?? '-'}");
        String agg = isAnyBye ? "-" : (isHome ? "${matchData!['home_score'] ?? '-'}" : "${matchData!['away_score'] ?? '-'}");

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(width: 24, height: 24, child: (logoUrl != null && logoUrl.isNotEmpty) ? Image.network(logoUrl, fit: BoxFit.contain) : const Icon(Icons.shield, size: 18, color: Colors.white24)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 12, fontStyle: displayName == "BYE"? FontStyle.italic: null)),
              ),
              // MODIFIED: Inject three-column split if two-legged
              if (showLegs)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 20, child: Text(l1, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 11))),
                    SizedBox(width: 20, child: Text(l2, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 11))),
                    SizedBox(width: 16, child: Text(agg, textAlign: TextAlign.center, style: TextStyle(color: isWinner && !isAnyBye ? Colors.blueAccent : Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                  ]
                )
              else
                Text(agg, style: TextStyle(color:isWinner && !isAnyBye? Colors.blueAccent : Colors.white54, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        );
      }
    );
  }
}

class BracketConnectorPainter extends CustomPainter {
  final int prevRoundMatches;
  final bool isStarted;
  final List<bool> completedMatches;
  final Color color;

  BracketConnectorPainter({
    required this.prevRoundMatches,
    required this.isStarted,
    required this.completedMatches,
    this.color = const Color(0xFF00E5FF)
  });

  @override
  void paint(Canvas canvas, Size size) {
    double w = size.width;
    double h = size.height;

    double getCenterY(int prevRoundMatches, int index) {
      return h / (prevRoundMatches * 2) * (index * 2 + 1);
    }

    for (int i = 0; i < prevRoundMatches; i += 2) {
      double y1 = getCenterY(prevRoundMatches, i);
      double y2 = getCenterY(prevRoundMatches, i + 1);
      double midY = (y1 + y2) / 2;

      bool topCompleted = isStarted && completedMatches[i];
      bool bottomCompleted = isStarted && (i+1 < completedMatches.length? completedMatches[i+1] : false);

      final topPaint = Paint()
      ..color = color.withOpacity(topCompleted? 1.0: 0.3)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

      Path topPath = Path()
        ..moveTo(0, y1)
        ..lineTo(w / 2, y1)
        ..lineTo(w / 2, midY);
      canvas.drawPath(topPath, topPaint);

      final bottomPaint = Paint()
      ..color = color.withOpacity(bottomCompleted? 1.0: 0.3)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

      Path bottomPath = Path()
        ..moveTo(0, y2)
        ..lineTo(w / 2, y2)
        ..lineTo(w / 2, midY);
      canvas.drawPath(bottomPath, bottomPaint);


      bool middlejoint = topCompleted || bottomCompleted;
      final middlePaint = Paint()
      ..color = color.withOpacity(middlejoint? 1.0: 0.3)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

      Path middlePath = Path()
        ..moveTo(w / 2, midY)
        ..lineTo(w, midY);
      canvas.drawPath(middlePath, middlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}