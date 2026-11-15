import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gamesphere/TheProvider.dart';
import 'package:provider/provider.dart';

class FixturesTab extends StatelessWidget {
  final String tournamentId;
  final Map<String, dynamic> tournamentData;

  const FixturesTab({
    super.key, 
    required this.tournamentId, 
    required this.tournamentData
  });

  @override
  Widget build(BuildContext context) {
    int qualifies = tournamentData['qualifies_to_KO'] ?? 8;
    if (qualifies < 2) qualifies = 2;
    int totalRounds = (log(qualifies) / log(2)).ceil();
    // NEW: Check if tournament is two-legged
    bool isTwoLegged = tournamentData['two_legged_knockout'] ?? false; 

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId)
          .collection('participants')
          .snapshots(),
      builder: (context, partSnapshot) {
        if (partSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        Map<String, String> slotToTeamId = {};
        if (partSnapshot.hasData) {
          for (var doc in partSnapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            if (data['team_id'] != null) {
              slotToTeamId["${data['group']}_${data['slot_index']}"] = data['team_id'];
            }
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('matches')
              .orderBy('round').orderBy('order').snapshots(),
          builder: (context, matchSnapshot) {
            
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('ko_matches')
                  .orderBy('round').orderBy('match_index').snapshots(),
              builder: (context, koMatchSnapshot) {
                
                if (!matchSnapshot.hasData && !koMatchSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var groupMatches = matchSnapshot.data?.docs ?? [];
                var koMatches = koMatchSnapshot.data?.docs ?? [];

                if (groupMatches.isEmpty && koMatches.isEmpty) {
                  return const Center(child: Text("No fixtures generated.", style: TextStyle(color: Colors.white38)));
                }

                // MODIFIED: Flatten KO matches to accommodate multiple legs
                List<Map<String, dynamic>> flatKoMatches = [];
                for (var doc in koMatches) {
                  var koMatch = doc.data() as Map<String, dynamic>;
                  bool isFinal = koMatch['round'] == totalRounds - 1;
                  
                  if (isTwoLegged && !isFinal) {
                    flatKoMatches.add({'data': koMatch, 'leg': 1});
                    flatKoMatches.add({'data': koMatch, 'leg': 2});
                  } else {
                    flatKoMatches.add({'data': koMatch, 'leg': 0}); // 0 means single leg
                  }
                }

                int itemCount = groupMatches.length + (koMatches.isNotEmpty ? flatKoMatches.length + 1 : 0);

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: itemCount,
                  cacheExtent: max(context.screenHeight * 4, 3000),
                  itemBuilder: (context, index) {
                    
                    if (index < groupMatches.length) {
                      var match = groupMatches[index].data() as Map<String, dynamic>;
                      String homeSlotKey = "${match['group']}_${match['home_slot']}";
                      String awaySlotKey = "${match['group']}_${match['away_slot']}";

                      return _MatchCard(
                        match: match,
                        homeTeamId: slotToTeamId[homeSlotKey],
                        awayTeamId: slotToTeamId[awaySlotKey],
                        tournamentId: tournamentId,
                        tournamentData: tournamentData,
                      );
                    }
                    
                    else if (index == groupMatches.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Row(
                          children: [
                            const Expanded(child: Divider(color: Colors.white10, thickness: 1)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                "KNOCKOUT PHASE", 
                                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 2)
                              ),
                            ),
                            const Expanded(child: Divider(color: Colors.white10, thickness: 1)),
                          ],
                        ),
                      );
                    } 
                    
                    else {
                      int koIndex = index - groupMatches.length - 1;
                      var config = flatKoMatches[koIndex];
                      var koMatch = config['data'];

                      return _KOMatchCard(
                        match: koMatch,
                        leg: config['leg'], // NEW: Passed leg identifier
                        tournamentId: tournamentId,
                        totalRounds: totalRounds,
                        tournamentData: tournamentData,
                      );
                    }
                  },
                );
              }
            );
          },
        );
      }
    );
  }
}

class _MatchCard extends StatelessWidget {
  final Map<String, dynamic> match;
  final String? homeTeamId;
  final String? awayTeamId;
  final String tournamentId;
  final Map<String, dynamic> tournamentData;

  const _MatchCard({required this.match, this.homeTeamId, this.awayTeamId, required this.tournamentId, required this.tournamentData});

  Future<Map<String, dynamic>> _fetchTeams() async {
    Map<String, dynamic> result = {
      'home': {'name': "TBD (Slot ${match['home_slot'] + 1})", 'logo': null},
      'away': {'name': "TBD (Slot ${match['away_slot'] + 1})", 'logo': null},
    };

    if (homeTeamId != null && homeTeamId!.isNotEmpty) {
      var doc = await FirebaseFirestore.instance.collection('teams').doc(homeTeamId).get();
      if (doc.exists) {
        result['home'] = {'name': doc['name'], 'logo': doc['logo_url']};
      }
    }

    if (awayTeamId != null && awayTeamId!.isNotEmpty) {
      var doc = await FirebaseFirestore.instance.collection('teams').doc(awayTeamId).get();
      if (doc.exists) {
        result['away'] = {'name': doc['name'], 'logo': doc['logo_url']};
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    void _showSnackBar(String text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1E1E24))
      );
    }
    
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchTeams(),
      builder: (context, snapshot) {
        final homeData = snapshot.data?['home'] ?? {'name': "Loading...", 'logo': null};
        final awayData = snapshot.data?['away'] ?? {'name': "Loading...", 'logo': null};

        bool isCompleted = match['status'] == 'completed';
        String scoreDisplay = isCompleted ? "${match['home_score']} - ${match['away_score']}" : "VS";
        
        final List admins = tournamentData['admins'] ?? [];
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final bool amIAdmin = admins.contains(userProvider.uid) || (userProvider.role == "superAdmin");

        return Align(
          alignment: Alignment.topCenter,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E24),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Stack(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => MatchDetailsSheet(
                        homeData: homeData,
                        awayData: awayData,
                        homeTeamId: homeTeamId,
                        awayTeamId: awayTeamId,
                        scoreDisplay: scoreDisplay,
                        subtitle: "Group ${match['group']} • Round ${match['round']}",
                      )
                    );
                  },
                  child: Opacity(
                    opacity: (!isCompleted && (homeTeamId == null || awayTeamId == null)) ? 0.5 : 1.0,
                    child: Padding(
                      padding: context.isMobile 
                          ? const EdgeInsets.symmetric(vertical: 16, horizontal: 8) 
                          : const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(child: _StaticTeamBadge(name: homeData['name'], logoUrl: homeData['logo'])),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Group ${match['group']} • Round ${match['round']}", 
                                style: const TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1)
                              ),
                              const SizedBox(height: 8),
                              Text(scoreDisplay, 
                                style: TextStyle(
                                  color: isCompleted ? Colors.white : Colors.blueAccent, 
                                  fontSize: isCompleted ? 28 : 20, 
                                  fontWeight: FontWeight.bold
                                )
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                          Expanded(child: _StaticTeamBadge(name: awayData['name'], logoUrl: awayData['logo'])),
                        ],
                      ),
                    ),
                  ),
                ),
                if (amIAdmin)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white54, size: 20),
                      onPressed: () {
                        bool isHomeMissing = homeTeamId == null || homeTeamId!.isEmpty;
                        bool isAwayMissing = awayTeamId == null || awayTeamId!.isEmpty;

                        if (!isCompleted && (isHomeMissing || isAwayMissing)) {
                          _showSnackBar("Cannot enter scores until both teams are assigned.");
                          return;
                        }
                        _showScoreDialog(context, isCompleted, homeData['name'], awayData['name']);
                      },
                    ),
                  )
              ],
            ),
          ),
        );
      }
    );
  }

  void _showScoreDialog(BuildContext context, bool isCompleted, String homeName, String awayName) {
    final TextEditingController homeController = TextEditingController(text: "${match['home_score'] ?? ""}");
    final TextEditingController awayController = TextEditingController(text: "${match['away_score'] ?? ""}");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Enter Match Result", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Column(
                  spacing: 5,
                  children: [
                    Text(homeName, style: const TextStyle(color: Colors.blue, fontSize: 12, overflow: TextOverflow.ellipsis)),
                    _scoreField(homeController),
                  ],
                )),
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 20, 10, 0),
                  child: Text("-", style: TextStyle(color: Colors.white, fontSize: 24)),
                ),
                Expanded(child: Column(
                  spacing: 5,
                  children: [
                    Text(awayName, style: const TextStyle(color: Colors.blue, fontSize: 12, overflow: TextOverflow.ellipsis)),
                    _scoreField(awayController),
                  ],
                )),
              ],
            ),
          ],
        ),
        actions: [
          if(isCompleted) Padding(
            padding: EdgeInsets.all(context.isMobile? 4: 8),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 186, 14, 2)),
              onPressed: () => _clearMatchResult(context),
              child: const Text("Clear Result", style: TextStyle(color: Colors.white)),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: EdgeInsets.all(context.isMobile? 4: 8),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(context.isMobile? 4: 8),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: () async {
                    int newHomeScore = int.tryParse(homeController.text) ?? 0;
                    int newAwayScore = int.tryParse(awayController.text) ?? 0;
                    
                    bool wasCompleted = match['status'] == 'completed';
                    int? oldHomeScore = match['home_score'];
                    int? oldAwayScore = match['away_score'];
                
                    Map<String, int> getStats(int? myScore, int? oppScore, bool isDone) {
                      if (!isDone || myScore == null || oppScore == null) {
                        return {'p': 0, 'w': 0, 'd': 0, 'l': 0, 'pts': 0, 'gs': 0, 'gc': 0, 'gd': 0};
                      }
                      int w = myScore > oppScore ? 1 : 0;
                      int d = myScore == oppScore ? 1 : 0;
                      int l = myScore < oppScore ? 1 : 0;
                      return {
                        'p': 1,
                        'w': w,
                        'd': d,
                        'l': l,
                        'pts': (w * 3) + (d * 1),
                        'gs': myScore,
                        'gc': oppScore,
                        'gd': myScore - oppScore,
                      };
                    }
                
                    var oldHomeStats = getStats(oldHomeScore, oldAwayScore, wasCompleted);
                    var oldAwayStats = getStats(oldAwayScore, oldHomeScore, wasCompleted);
                
                    var newHomeStats = getStats(newHomeScore, newAwayScore, true);
                    var newAwayStats = getStats(newAwayScore, newHomeScore, true);
                
                    Map<String, dynamic> buildUpdateMap(Map<String, int> newS, Map<String, int> oldS) {
                      Map<String, dynamic> updates = {};
                      Map<String, int> differences = {
                        'played': newS['p']! - oldS['p']!,
                        'won': newS['w']! - oldS['w']!,
                        'drawn': newS['d']! - oldS['d']!,
                        'lost': newS['l']! - oldS['l']!,
                        'points': newS['pts']! - oldS['pts']!,
                        'scored': newS['gs']! - oldS['gs']!,
                        'conceded': newS['gc']! - oldS['gc']!,
                        'difference': newS['gd']! - oldS['gd']!,
                      };
                      
                      differences.forEach((key, value) {
                        if (value != 0) updates[key] = FieldValue.increment(value);
                      });
                      return updates;
                    }
                
                    var homeUpdates = buildUpdateMap(newHomeStats, oldHomeStats);
                    var awayUpdates = buildUpdateMap(newAwayStats, oldAwayStats);
                
                    WriteBatch batch = FirebaseFirestore.instance.batch();
                
                    DocumentReference matchRef = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('matches').doc(match['match_id']);
                    batch.update(matchRef, {
                      'home_score': newHomeScore,
                      'away_score': newAwayScore,
                      'status': 'completed',
                    });
                
                    String homeSlotId = "Group${match['group']}_Slot${match['home_slot']}";
                    DocumentReference homeRef = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('participants').doc(homeSlotId);
                    
                    if (homeUpdates.isNotEmpty) batch.update(homeRef, homeUpdates);
                
                    String awaySlotId = "Group${match['group']}_Slot${match['away_slot']}";
                    DocumentReference awayRef = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('participants').doc(awaySlotId);
                    
                    if (awayUpdates.isNotEmpty) batch.update(awayRef, awayUpdates);
                
                    await batch.commit();
                    
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text("Save Result", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _clearMatchResult(BuildContext context) async {
    int oldHomeScore = match['home_score'] ?? 0;
    int oldAwayScore = match['away_score'] ?? 0;

    int w = oldHomeScore > oldAwayScore ? 1 : 0;
    int d = oldHomeScore == oldAwayScore ? 1 : 0;
    int l = oldHomeScore < oldAwayScore ? 1 : 0;

    Map<String, dynamic> buildReversal(int myS, int oppS, int win, int draw, int loss) {
      return {
        'played': FieldValue.increment(-1),
        'won': FieldValue.increment(-win),
        'drawn': FieldValue.increment(-draw),
        'lost': FieldValue.increment(-loss),
        'points': FieldValue.increment(-((win * 3) + (draw * 1))),
        'scored': FieldValue.increment(-myS),
        'conceded': FieldValue.increment(-oppS),
        'difference': FieldValue.increment(-(myS - oppS)),
      };
    }

    WriteBatch batch = FirebaseFirestore.instance.batch();

    DocumentReference matchRef = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('matches').doc(match['match_id']);
        
    batch.update(matchRef, {
      'home_score': null,
      'away_score': null,
      'status': 'pending',
    });

    String homeSlotId = "Group${match['group']}_Slot${match['home_slot']}";
    DocumentReference homeRef = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('participants').doc(homeSlotId);
    
    batch.update(homeRef, buildReversal(oldHomeScore, oldAwayScore, w, d, l));

    String awaySlotId = "Group${match['group']}_Slot${match['away_slot']}";
    DocumentReference awayRef = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('participants').doc(awaySlotId);
    
    batch.update(awayRef, buildReversal(oldAwayScore, oldHomeScore, l, d, w));

    await batch.commit();
    if (context.mounted) Navigator.pop(context);
  }

  Widget _scoreField(TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      decoration: const InputDecoration(
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
      ),
    );
  }
}

class _KOMatchCard extends StatelessWidget {
  final Map<String, dynamic> match;
  final int leg;
  final String tournamentId;
  final int totalRounds;
  final Map<String, dynamic> tournamentData;

  const _KOMatchCard({required this.match, required this.leg, required this.tournamentId, required this.totalRounds, required this.tournamentData});

  String _getRoundName(int roundIndex) {
    if (roundIndex == totalRounds - 1) return "FINAL";
    if (roundIndex == totalRounds - 2) return "Semi-Finals";
    if (roundIndex == totalRounds - 3) return "Quarter-Finals";
    return "Round of ${pow(2, totalRounds - roundIndex)}";
  }

  Future<Map<String, dynamic>> _fetchTeams() async {
    String? hId = match['home_team_id'];
    String? aId = match['away_team_id'];
    String? hPh = match['home_placeholder'];
    String? aPh = match['away_placeholder'];

    // Instantly show the team if set via format 2 but play-offs haven't started yet
    if ((hId == null || hId.isEmpty) && hPh != null && hPh.startsWith("TEAM_")) hId = hPh.substring(5);
    if ((aId == null || aId.isEmpty) && aPh != null && aPh.startsWith("TEAM_")) aId = aPh.substring(5);

    String formatPh(String? ph) {
      if (ph == null) return "TBD";
      if (ph == "BYE") return "BYE";
      var parts = ph.split('_');
      if (parts.length == 2 && parts[0] != "TEAM") {
        String pos = parts[0];
        String suffix = pos == "1" ? "st" : pos == "2" ? "nd" : pos == "3" ? "rd" : "th";
        return "$pos$suffix Group ${parts[1]}";
      }
      return "TBD";
    }

    Map<String, dynamic> result = {
      'home': {'name': formatPh(hPh), 'logo': null},
      'away': {'name': formatPh(aPh), 'logo': null},
    };

    if (hId != null && hId.isNotEmpty) {
      var doc = await FirebaseFirestore.instance.collection('teams').doc(hId).get();
      if (doc.exists) result['home'] = {'name': doc['name'], 'logo': doc['logo_url']};
    }

    if (aId != null && aId.isNotEmpty) {
      var doc = await FirebaseFirestore.instance.collection('teams').doc(aId).get();
      if (doc.exists) result['away'] = {'name': doc['name'], 'logo': doc['logo_url']};
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    void _showSnackBar(String text) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1E1E24)));
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchTeams(),
      builder: (context, snapshot) {
        final homeData = snapshot.data?['home'] ?? {'name': "Loading...", 'logo': null};
        final awayData = snapshot.data?['away'] ?? {'name': "Loading...", 'logo': null};

        bool isCompleted = (leg == 1) ? match['status_leg1'] == 'completed' 
                         : (leg == 2) ? match['status_leg2'] == 'completed' 
                         : match['status'] == 'completed';

        int? hScore = (leg == 1) ? match['home_score_leg1'] : (leg == 2) ? match['home_score_leg2'] : match['home_score'];
        int? aScore = (leg == 1) ? match['away_score_leg1'] : (leg == 2) ? match['away_score_leg2'] : match['away_score'];

        String scoreDisplay = isCompleted ? "$hScore - $aScore" : "VS";
        int roundIndex = match['round'];
        String roundName = _getRoundName(roundIndex);
        
        String roundSubtitle = roundName;
        if (leg > 0) {
          roundSubtitle += " • Leg $leg";
        } else if (roundName != "FINAL") {
          roundSubtitle += " • Match ${match['match_index'] + 1}";
        }

        final List admins = tournamentData['admins'] ?? [];
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final bool amIAdmin = admins.contains(userProvider.uid) || (userProvider.role == "superAdmin");

        if(homeData['name'] == "BYE" || awayData['name'] == "BYE"){
          return const SizedBox.shrink();
        }

        return Align(
          alignment: Alignment.topCenter,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E24),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
            ),
            child: Stack(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => MatchDetailsSheet(
                        homeData: homeData,
                        awayData: awayData,
                        homeTeamId: match['home_team_id'],
                        awayTeamId: match['away_team_id'],
                        scoreDisplay: scoreDisplay,
                        subtitle: roundSubtitle,
                      )
                    );
                  },
                  child: Opacity(
                    opacity: (!isCompleted && (match['home_team_id'] == null || match['away_team_id'] == null)) ? 0.5 : 1.0,
                    child: Padding(
                      padding: context.isMobile ? const EdgeInsets.symmetric(vertical: 16, horizontal: 8) : const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(child: _StaticTeamBadge(name: homeData['name'], logoUrl: homeData['logo'])),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(roundSubtitle, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 10, letterSpacing: 1)),
                              const SizedBox(height: 8),
                              Text(scoreDisplay, style: TextStyle(color: isCompleted ? Colors.white : Colors.blueAccent, fontSize: isCompleted ? 28 : 20, fontWeight: FontWeight.bold)),
                              if (leg == 2 && isCompleted)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text("(Agg: ${match['home_score']} - ${match['away_score']})", 
                                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                ),
                              const SizedBox(height: 20),
                            ],
                          ),
                          Expanded(child: _StaticTeamBadge(name: awayData['name'], logoUrl: awayData['logo'])),
                        ],
                      ),
                    ),
                  ),
                ),
                if (amIAdmin)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white54, size: 20),
                      onPressed: () {
                        bool isHomeMissing = match['home_team_id'] == null;
                        bool isAwayMissing = match['away_team_id'] == null;

                        if (!isCompleted && (isHomeMissing || isAwayMissing)) {
                          _showSnackBar("Cannot enter scores until both teams are assigned.");
                          return;
                        }
                        _showKOScoreDialog(context, isCompleted, homeData['name'], awayData['name'], roundIndex);
                      },
                    ),
                  )
              ],
            ),
          ),
        );
      }
    );
  }

  void _showKOScoreDialog(BuildContext context, bool isCompleted, String homeName, String awayName, int roundIndex) {
    // MODIFIED: Fetch initial text based on leg
    int? initHome = (leg == 1) ? match['home_score_leg1'] : (leg == 2) ? match['home_score_leg2'] : match['home_score'];
    int? initAway = (leg == 1) ? match['away_score_leg1'] : (leg == 2) ? match['away_score_leg2'] : match['away_score'];

    final TextEditingController homeController = TextEditingController(text: initHome != null ? "$initHome" : "");
    final TextEditingController awayController = TextEditingController(text: initAway != null ? "$initAway" : "");
    String? manualWinnerId;
    bool? homeSelect = (match['winner_id'] != null)? match['winner_id'] == match['home_team_id'] : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool isTie() {
            int h = int.tryParse(homeController.text) ?? 0;
            int a = int.tryParse(awayController.text) ?? 0;
            // MODIFIED: If leg 2, we must check the aggregate for a tie, not just this match
            if (leg == 2) {
              h += (match['home_score_leg1'] ?? 0) as int;
              a += (match['away_score_leg1'] ?? 0) as int;
            }
            return h == a && (leg == 0 || leg == 2); // Ties only matter if deciding winner
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(leg > 0 ? "Enter Leg $leg Result" : "Enter Match Result", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: Column(spacing: 5, children: [Text(homeName, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, overflow: TextOverflow.ellipsis)), _scoreField(homeController, setDialogState)])),
                      const Padding(padding: EdgeInsets.fromLTRB(10, 20, 10, 0), child: Text("-", style: TextStyle(color: Colors.white, fontSize: 24))),
                      Expanded(child: Column(spacing: 5, children: [Text(awayName, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, overflow: TextOverflow.ellipsis)), _scoreField(awayController, setDialogState)])),
                    ],
                  ),
                  if (isTie()) ...[
                    const SizedBox(height: 20),
                    const Text("Aggregate is tied. Select who advances:", style: TextStyle(color: Colors.grey, fontSize: 11)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: Center(child: IconButton(onPressed: () => setDialogState(() { manualWinnerId = match['home_team_id']; homeSelect = true; }), icon: Icon((homeSelect != null && homeSelect!)? Icons.check_box :Icons.check_box_outline_blank, color: Colors.blueAccent)))),
                        const SizedBox(width: 8),
                        Expanded(child: Center(child: IconButton(onPressed: () => setDialogState(() { manualWinnerId = match['away_team_id']; homeSelect = false; }), icon: Icon((homeSelect != null && !homeSelect!)? Icons.check_box :Icons.check_box_outline_blank, color: Colors.blueAccent)))),
                      ],
                    )
                  ]
                ],
              ),
            ),
            actions: [
              if(isCompleted) Padding(
                padding: EdgeInsets.all(context.isMobile? 4: 8),
                child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 186, 14, 2)), onPressed: () => _clearKOMatchResult(context, roundIndex), child: const Text("Clear Result", style: TextStyle(color: Colors.white))),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(padding: EdgeInsets.all(context.isMobile? 4: 8), child: TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey)))),
                  Padding(
                    padding: EdgeInsets.all(context.isMobile? 4: 8),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
                      onPressed: () async {
                        int newLegHome = int.tryParse(homeController.text) ?? 0;
                        int newLegAway = int.tryParse(awayController.text) ?? 0;
                        
                        // NEW: Calculate Aggregate
                        int aggHome = newLegHome;
                        int aggAway = newLegAway;
                        if (leg == 1) {
                          aggHome += (match['home_score_leg2'] ?? 0) as int;
                          aggAway += (match['away_score_leg2'] ?? 0) as int;
                        } else if (leg == 2) {
                          aggHome += (match['home_score_leg1'] ?? 0) as int;
                          aggAway += (match['away_score_leg1'] ?? 0) as int;
                        }
                        
                        String? winnerId = aggHome > aggAway ? match['home_team_id'] : match['away_team_id'];
                        if (aggHome > aggAway) winnerId = match['home_team_id'];
                        else if (aggAway > aggHome) winnerId = match['away_team_id'];
                        else {
                          if (manualWinnerId == null && (leg == 0 || leg == 2)) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a winner for the tie-break."), backgroundColor: Colors.redAccent));
                            return;
                          }
                          winnerId = manualWinnerId;
                        }

                        int mIndex = match['match_index'];
                        WriteBatch batch = FirebaseFirestore.instance.batch();
                        DocumentReference matchRef = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('ko_matches').doc('ko_r${roundIndex}_m$mIndex');
                        
                        // MODIFIED: Update Fields based on Leg
                        Map<String, dynamic> updates = {};
                        if (leg == 1) {
                          updates = {
                            'home_score_leg1': newLegHome, 'away_score_leg1': newLegAway, 'status_leg1': 'completed',
                            'home_score': aggHome, 'away_score': aggAway, // Keep aggregate synced
                          };
                        } else if (leg == 2) {
                          updates = {
                            'home_score_leg2': newLegHome, 'away_score_leg2': newLegAway, 'status_leg2': 'completed',
                            'home_score': aggHome, 'away_score': aggAway, 'status': 'completed', 'winner_id': winnerId,
                          };
                        } else {
                          updates = {'home_score': newLegHome, 'away_score': newLegAway, 'status': 'completed', 'winner_id': winnerId};
                        }
                        batch.update(matchRef, updates);
          
                        if ((leg == 0 || leg == 2) && roundIndex + 1 < totalRounds) {
                          DocumentReference nextMatchRef = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('ko_matches').doc('ko_r${roundIndex + 1}_m${mIndex ~/ 2}');
                          String targetField = (mIndex % 2 == 0) ? 'home_team_id' : 'away_team_id';
                          batch.update(nextMatchRef, {targetField: winnerId});
                        }
          
                        await batch.commit();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text("Save Result", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _clearKOMatchResult(BuildContext context, int roundIndex) async {
    int mIndex = match['match_index'];
    WriteBatch batch = FirebaseFirestore.instance.batch();
    DocumentReference matchRef = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('ko_matches').doc('ko_r${roundIndex}_m$mIndex');
    
    // MODIFIED: Clear only specific leg data
    Map<String, dynamic> updates = {};
    if (leg == 1) {
      updates = {
        'home_score_leg1': null, 'away_score_leg1': null, 'status_leg1': 'pending',
        'home_score': match['home_score_leg2'], 'away_score': match['away_score_leg2'],
        'status': 'pending', 'winner_id': null
      };
    } else if (leg == 2) {
      updates = {
        'home_score_leg2': null, 'away_score_leg2': null, 'status_leg2': 'pending',
        'home_score': match['home_score_leg1'], 'away_score': match['away_score_leg1'],
        'status': 'pending', 'winner_id': null
      };
    } else {
      updates = {'home_score': null, 'away_score': null, 'status': 'scheduled', 'winner_id': null};
    }
    batch.update(matchRef, updates);

    if ((leg == 0 || leg == 2) && roundIndex + 1 < totalRounds) {
      DocumentReference nextMatchRef = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('ko_matches').doc('ko_r${roundIndex + 1}_m${mIndex ~/ 2}');
      String targetField = (mIndex % 2 == 0) ? 'home_team_id' : 'away_team_id';
      batch.update(nextMatchRef, {targetField: null});
    }

    await batch.commit();
    if (context.mounted) Navigator.pop(context);
  }

  Widget _scoreField(TextEditingController controller, StateSetter setDialogState) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      decoration: const InputDecoration(
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E5FF))),
      ),
      onChanged: (_) => setDialogState(() {})
    );
  }
}

class _StaticTeamBadge extends StatelessWidget {
  final String name;
  final String? logoUrl;

  const _StaticTeamBadge({required this.name, this.logoUrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 40,
          width: 40,
          child: (logoUrl != null && logoUrl!.isNotEmpty)
            ? Image.network(
                logoUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress){
                  if(loadingProgress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 3.5),
                  );
                },
                errorBuilder: (context, error, stackTrace){
                  return const Icon(Icons.shield, color: Colors.white, size: 40);
                },
              )
            : const Icon(Icons.shield, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 8),
        Text(name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)
        ),
      ],
    );
  }
}

class MatchDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> homeData;
  final Map<String, dynamic> awayData;
  final String? homeTeamId;
  final String? awayTeamId;
  final String scoreDisplay;
  final String subtitle;

  const MatchDetailsSheet({
    super.key,
    required this.homeData,
    required this.awayData,
    this.homeTeamId,
    this.awayTeamId,
    required this.scoreDisplay,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 20),
          Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          const Text("Scheduled: 15 Oct 2026, 18:00 (Dummy Data)", style: TextStyle(color: Colors.blueAccent, fontSize: 13)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(child: _StaticTeamBadge(name: homeData['name'], logoUrl: homeData['logo'])),
              Text(scoreDisplay, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              Expanded(child: _StaticTeamBadge(name: awayData['name'], logoUrl: awayData['logo'])),
            ],
          ),
          const Divider(color: Colors.white10, height: 40),
          const Text("TEAM SQUADS", style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2)),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildSquadList(homeTeamId, homeData['name'], 1)),
                const VerticalDivider(color: Colors.white10, width: 32),
                Expanded(child: _buildSquadList(awayTeamId, awayData['name'], 2)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSquadList(String? teamId, String teamName, int d) {
    if (teamId == null || teamId.isEmpty) {
      return const Center(child: Text("TBD", style: TextStyle(color: Colors.white38)));
    }
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('teams').doc(teamId).collection('players').orderBy('number').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var players = snapshot.data!.docs;
              
              if (players.isEmpty) return const Center(child: Text("No players registered", style: TextStyle(color: Colors.white24, fontSize: 12), textAlign: TextAlign.center));
              
              return ListView.builder(
                itemCount: players.length,
                itemBuilder: (context, index) {
                  var p = players[index].data() as Map<String, dynamic>;
                  bool isLinked = p['is_linked'] ?? false;

                  Widget buildPlayerRow(String playerName) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        spacing: 5,
                        children: [
                          if(d == 2) Expanded(child: Text(playerName, style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
                          Text("${p['number'] ?? '-'}", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                          if(d != 2) Expanded(child: Text(playerName, style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis, textAlign: TextAlign.left)),
                        ],
                      ),
                    );
                  }

                  if (isLinked && p['user_id'] != null) {
                    return StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(p['user_id']).snapshots(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) return buildPlayerRow("Loading...");
                        var userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                        String linkedName = "${userData?['firstname'] ?? "Unknown"} ${userData?['lastname'] ?? ""}".trim();
                        return buildPlayerRow(linkedName);
                      },
                    );
                  } else {
                    return buildPlayerRow(p['name'] ?? "Unknown Player");
                  }
                },
              );
            }
          ),
        )
      ],
    );
  }
}