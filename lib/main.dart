import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const FocusFlowApp(),
    ),
  );
}

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────

class SessionData {
  String title;
  String status;
  String time;
  bool completed;
  DateTime date;
  int focusMinutes;

  SessionData({
    required this.title,
    required this.status,
    required this.time,
    this.completed = true,
    DateTime? date,
    this.focusMinutes = 25,
  }) : date = date ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'title': title,
        'status': status,
        'time': time,
        'completed': completed,
        'date': date.toIso8601String(),
        'focusMinutes': focusMinutes,
      };

  factory SessionData.fromJson(Map<String, dynamic> json) => SessionData(
        title: json['title'] as String,
        status: json['status'] as String,
        time: json['time'] as String,
        completed: json['completed'] as bool? ?? true,
        date: json['date'] != null
            ? DateTime.tryParse(json['date'] as String) ?? DateTime.now()
            : DateTime.now(),
        focusMinutes: json['focusMinutes'] as int? ?? 25,
      );
}

// ─────────────────────────────────────────────
// APP STATE
// ─────────────────────────────────────────────

class AppState extends ChangeNotifier {
  String _userName = 'Deepika';
  int _focusDurationMinutes = 25;
  int _shortBreakMinutes = 5;
  int _currentSeconds = 25 * 60;
  bool _isRunning = false;
  Timer? _timer;
  List<SessionData> recentSessions = [];

  bool autoStartBreak = false;
  bool sessionEndSound = true;
  bool hapticFeedback = true;
  bool smartDND = false;

  // Stats data: key = 'yyyy-MM-dd', value = total focus minutes
  Map<String, int> dailyFocusMinutes = {};

  AppState() {
    _loadPersistedData();
  }

  // ── Getters ──────────────────────────────────

  String get userName => _userName;
  String get firstName =>
      _userName.split(' ').isNotEmpty ? _userName.split(' ').first : _userName;

  String get initials {
    final names = _userName.trim().split(' ');
    if (names.isEmpty || names[0].isEmpty) return '';
    if (names.length > 1) {
      return '${names[0][0]}${names[names.length - 1][0]}'.toUpperCase();
    }
    return names[0][0].toUpperCase();
  }

  int get focusDurationMinutes => _focusDurationMinutes;
  int get shortBreakMinutes => _shortBreakMinutes;
  int get currentSeconds => _currentSeconds;
  bool get isRunning => _isRunning;
  double get progress => 1 - (_currentSeconds / (_focusDurationMinutes * 60));

  String get formattedTime {
    final minutes = _currentSeconds ~/ 60;
    final seconds = _currentSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ── Streak logic ──────────────────────────────

  int get currentStreak {
    if (dailyFocusMinutes.isEmpty) return 0;
    int streak = 0;
    final today = DateTime.now();
    // Start from today; if today has no data, allow starting from yesterday
    // (streak stays alive until end of today)
    DateTime checkDay = today;
    final todayKey = _dateKey(today);
    final todayHasData = (dailyFocusMinutes[todayKey] ?? 0) > 0;
    if (!todayHasData) {
      // Try starting streak from yesterday
      checkDay = today.subtract(const Duration(days: 1));
    }
    // Walk backwards counting consecutive days with focus data
    for (int i = 0; i < 365; i++) {
      final key = _dateKey(checkDay);
      if ((dailyFocusMinutes[key] ?? 0) > 0) {
        streak++;
        checkDay = checkDay.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  String get streakLabel => currentStreak > 0 ? '$currentStreak Day Streak' : 'No streak yet';

  int get totalFocusMinutesToday {
    return dailyFocusMinutes[_dateKey(DateTime.now())] ?? 0;
  }

  // Returns 7-day distribution (Mon–Sun of current week)
  List<double> get weeklyDistribution {
    final now = DateTime.now();
    // Go back to Monday of this week
    final weekday = now.weekday; // Mon=1, Sun=7
    final monday = now.subtract(Duration(days: weekday - 1));
    return List.generate(7, (i) {
      final day = monday.add(Duration(days: i));
      final minutes = dailyFocusMinutes[_dateKey(day)] ?? 0;
      return minutes.toDouble();
    });
  }

  double get weeklyMax {
    final vals = weeklyDistribution;
    final max = vals.reduce((a, b) => a > b ? a : b);
    return max == 0 ? 1 : max;
  }

  int get averageDailyFocusMinutes {
    if (dailyFocusMinutes.isEmpty) return 0;
    final total = dailyFocusMinutes.values.reduce((a, b) => a + b);
    return total ~/ dailyFocusMinutes.length;
  }

  String get averageDailyFocusLabel {
    final avg = averageDailyFocusMinutes;
    if (avg == 0) return '0m';
    final h = avg ~/ 60;
    final m = avg % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Persistence ───────────────────────────────

  Future<void> _loadPersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('userName') ?? _userName;
    _focusDurationMinutes =
        prefs.getInt('focusDurationMinutes') ?? _focusDurationMinutes;
    _shortBreakMinutes =
        prefs.getInt('shortBreakMinutes') ?? _shortBreakMinutes;
    _currentSeconds = prefs.getInt('currentSeconds') ?? (_focusDurationMinutes * 60);
    autoStartBreak = prefs.getBool('autoStartBreak') ?? autoStartBreak;
    sessionEndSound = prefs.getBool('sessionEndSound') ?? sessionEndSound;
    hapticFeedback = prefs.getBool('hapticFeedback') ?? hapticFeedback;
    smartDND = prefs.getBool('smartDND') ?? smartDND;

    // Load sessions
    final sessionsJson = prefs.getString('recentSessions');
    if (sessionsJson != null) {
      final list = jsonDecode(sessionsJson) as List<dynamic>;
      recentSessions = list
          .map((e) => SessionData.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      recentSessions = [
        SessionData(
          title: 'Quarterly Report Analysis',
          status: 'Completed • 55m focus',
          time: '09:15 AM',
          completed: true,
          date: DateTime.now().subtract(const Duration(hours: 3)),
          focusMinutes: 55,
        ),
        SessionData(
          title: 'UI Design System Refactor',
          status: 'Completed • 1h 45m focus',
          time: '07:30 AM',
          completed: true,
          date: DateTime.now().subtract(const Duration(hours: 5)),
          focusMinutes: 105,
        ),
        SessionData(
          title: 'Inbox Zero Protocol',
          status: 'Stopped • 20m focus',
          time: '04:45 PM',
          completed: false,
          date: DateTime.now().subtract(const Duration(days: 1)),
          focusMinutes: 20,
        ),
      ];
    }

    // Load daily focus minutes
    final dailyJson = prefs.getString('dailyFocusMinutes');
    if (dailyJson != null) {
      final map = jsonDecode(dailyJson) as Map<String, dynamic>;
      dailyFocusMinutes = map.map((k, v) => MapEntry(k, v as int));
    } else {
      // Seed sample data from default sessions
      _rebuildDailyFromSessions();
    }

    notifyListeners();
  }

  void _rebuildDailyFromSessions() {
    dailyFocusMinutes = {};
    for (final s in recentSessions) {
      if (s.focusMinutes > 0) {
        final key = _dateKey(s.date);
        dailyFocusMinutes[key] = (dailyFocusMinutes[key] ?? 0) + s.focusMinutes;
      }
    }
  }

  Future<void> _savePersistedData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', _userName);
    await prefs.setInt('focusDurationMinutes', _focusDurationMinutes);
    await prefs.setInt('shortBreakMinutes', _shortBreakMinutes);
    await prefs.setInt('currentSeconds', _currentSeconds);
    await prefs.setBool('autoStartBreak', autoStartBreak);
    await prefs.setBool('sessionEndSound', sessionEndSound);
    await prefs.setBool('hapticFeedback', hapticFeedback);
    await prefs.setBool('smartDND', smartDND);

    final sessionsJson =
        jsonEncode(recentSessions.map((s) => s.toJson()).toList());
    await prefs.setString('recentSessions', sessionsJson);

    final dailyJson = jsonEncode(dailyFocusMinutes);
    await prefs.setString('dailyFocusMinutes', dailyJson);
  }

  // ── Session management ────────────────────────

  void addSession(SessionData session) {
    recentSessions.insert(0, session);
    // Always count focus minutes toward daily stats (completed OR stopped)
    if (session.focusMinutes > 0) {
      final key = _dateKey(session.date);
      dailyFocusMinutes[key] =
          (dailyFocusMinutes[key] ?? 0) + session.focusMinutes;
    }
    _savePersistedData();
    notifyListeners();
  }

  void updateSession(int index, String newTitle) {
    recentSessions[index].title = newTitle;
    _savePersistedData();
    notifyListeners();
  }

  void deleteSession(int index) {
    final session = recentSessions[index];
    // Subtract focus minutes from daily map (matches addSession logic)
    if (session.focusMinutes > 0) {
      final key = _dateKey(session.date);
      final current = dailyFocusMinutes[key] ?? 0;
      final updated = current - session.focusMinutes;
      if (updated <= 0) {
        dailyFocusMinutes.remove(key);
      } else {
        dailyFocusMinutes[key] = updated;
      }
    }
    recentSessions.removeAt(index);
    _savePersistedData();
    notifyListeners();
  }

  void updateUserName(String newName) {
    if (newName.trim().isNotEmpty) {
      _userName = newName.trim();
      _savePersistedData();
      notifyListeners();
    }
  }

  // ── Timer controls ────────────────────────────

  void startTimer() {
    if (_isRunning || _currentSeconds == 0) return;
    _isRunning = true;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentSeconds > 0) {
        _currentSeconds--;
        notifyListeners();
      } else {
        pauseTimer();
        final now = DateTime.now();
        final hour = now.hour;
        final ampm = hour >= 12 ? 'PM' : 'AM';
        final h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        final timeStr =
            '${h.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} $ampm';
        addSession(SessionData(
          title: 'Focus Session',
          status: 'Completed • ${_focusDurationMinutes}m focus',
          time: timeStr,
          completed: true,
          date: now,
          focusMinutes: _focusDurationMinutes,
        ));
      }
    });
  }

  void pauseTimer() {
    _isRunning = false;
    _timer?.cancel();
    _savePersistedData();
    notifyListeners();
  }

  void resetTimer() {
    pauseTimer();
    _currentSeconds = _focusDurationMinutes * 60;
    _savePersistedData();
    notifyListeners();
  }

  // ── Settings updates ──────────────────────────

  void setFocusDuration(int minutes) {
    if (minutes < 1) return;
    _focusDurationMinutes = minutes;
    if (!_isRunning) _currentSeconds = minutes * 60;
    _savePersistedData();
    notifyListeners();
  }

  void setShortBreak(int minutes) {
    if (minutes < 1) return;
    _shortBreakMinutes = minutes;
    _savePersistedData();
    notifyListeners();
  }

  void setAutoStartBreak(bool value) {
    autoStartBreak = value;
    _savePersistedData();
    notifyListeners();
  }

  void setSessionEndSound(bool value) {
    sessionEndSound = value;
    _savePersistedData();
    notifyListeners();
  }

  void setHapticFeedback(bool value) {
    hapticFeedback = value;
    _savePersistedData();
    notifyListeners();
  }

  void setSmartDND(bool value) {
    smartDND = value;
    _savePersistedData();
    notifyListeners();
  }
}

// ─────────────────────────────────────────────
// APP ROOT
// ─────────────────────────────────────────────

class FocusFlowApp extends StatelessWidget {
  const FocusFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FocusFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFAF8FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4648D4),
          primary: const Color(0xFF4648D4),
          secondary: const Color(0xFF006C49),
          surface: const Color(0xFFFAF8FF),
          onSurface: const Color(0xFF131B2E),
          error: const Color(0xFFBA1A1A),
        ),
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAF8FF),
          foregroundColor: Color(0xFF131B2E),
          elevation: 0,
        ),
      ),
      home: const MainNavigator(),
    );
  }
}

// ─────────────────────────────────────────────
// MAIN NAVIGATOR
// ─────────────────────────────────────────────

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    FocusScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        backgroundColor: Colors.white,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Focus',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// HOME SCREEN
// ─────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _greetingText() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final streak = appState.currentStreak;
    final todayMinutes = appState.totalFocusMinutesToday;
    final todayH = todayMinutes ~/ 60;
    final todayM = todayMinutes % 60;
    final todayLabel = todayMinutes == 0
        ? 'No focus sessions yet today'
        : todayH > 0
            ? '$todayH h $todayM min focused today'
            : '$todayM min focused today';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_greetingText()}, ${appState.firstName}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF131B2E),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              todayLabel,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: const Color(0xFF464554)),
            ),
            const SizedBox(height: 32),

            // Streak Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Streak',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: const Color(0xFF767586)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        appState.streakLabel,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: streak > 0
                          ? const Color(0xFF006C49)
                          : const Color(0xFF767586),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_fire_department,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          streak > 0 ? 'Active' : 'Start Today',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Sessions',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (appState.recentSessions.isNotEmpty)
                  TextButton(
                    onPressed: () => _showClearAllDialog(context, appState),
                    child: const Text('Clear All',
                        style: TextStyle(color: Color(0xFFBA1A1A))),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            Expanded(
              child: appState.recentSessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 64,
                              color: const Color(0xFF767586).withOpacity(0.4)),
                          const SizedBox(height: 16),
                          Text(
                            'No sessions yet',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: const Color(0xFF767586)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start a focus timer to log your first session',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: const Color(0xFF767586)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: appState.recentSessions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final session = appState.recentSessions[index];
                        return _SessionTile(
                          session: session,
                          index: index,
                          appState: appState,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearAllDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Sessions'),
        content: const Text(
            'This will remove all session history. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              for (int i = appState.recentSessions.length - 1; i >= 0; i--) {
                appState.deleteSession(i);
              }
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final SessionData session;
  final int index;
  final AppState appState;

  const _SessionTile({
    required this.session,
    required this.index,
    required this.appState,
  });

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Session'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter session title',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                appState.updateSession(index, controller.text.trim());
              }
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4648D4),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: session.completed
                  ? const Color(0xFFE8F5F0)
                  : const Color(0xFFFFF3E0),
              shape: BoxShape.circle,
            ),
            child: Icon(
              session.completed ? Icons.check_circle_outline : Icons.pause_circle_outline,
              color: session.completed
                  ? const Color(0xFF006C49)
                  : const Color(0xFFE65100),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  session.status,
                  style: const TextStyle(
                      color: Color(0xFF767586), fontSize: 13),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                session.time,
                style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: Color(0xFF464554)),
              ),
              const SizedBox(height: 2),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    color: Color(0xFF767586), size: 18),
                onSelected: (value) {
                  if (value == 'edit') _showEditDialog(context);
                  if (value == 'delete') appState.deleteSession(index);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: Color(0xFFBA1A1A))),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// FOCUS SCREEN
// ─────────────────────────────────────────────

class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Focus Timer',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF131B2E),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                appState.isRunning
                    ? 'Stay focused — you\'re in the zone!'
                    : 'Press start when you\'re ready',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: const Color(0xFF464554)),
              ),
              const SizedBox(height: 48),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: CircularProgressIndicator(
                      value: appState.progress,
                      strokeWidth: 14,
                      backgroundColor: const Color(0xFFE2E7FF),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF4648D4)),
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        appState.formattedTime,
                        style: Theme.of(context)
                            .textTheme
                            .displayLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF4648D4),
                              fontSize: 56,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${appState.focusDurationMinutes} min session',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF767586),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!appState.isRunning) ...[
                    ElevatedButton.icon(
                      onPressed: appState.currentSeconds == 0
                          ? null
                          : appState.startTimer,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(appState.currentSeconds == 0
                          ? 'Completed!'
                          : 'Start Focus'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4648D4),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 36, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ] else ...[
                    ElevatedButton.icon(
                      onPressed: appState.pauseTimer,
                      icon: const Icon(Icons.pause_rounded),
                      label: const Text('Pause'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006C49),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 36, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  if (appState.currentSeconds < appState.focusDurationMinutes * 60) ...[
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: appState.resetTimer,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reset'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4648D4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              // Stop and log partial session
              if (appState.isRunning ||
                  (appState.currentSeconds > 0 &&
                      appState.currentSeconds <
                          appState.focusDurationMinutes * 60))
                TextButton.icon(
                  onPressed: () => _logPartialSession(context, appState),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Stop & Log Session'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF767586)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _logPartialSession(BuildContext context, AppState appState) {
    appState.pauseTimer();
    final elapsed =
        appState.focusDurationMinutes * 60 - appState.currentSeconds;
    // Log any elapsed time (even seconds — convert to at least 1 min display)
    final focusMin = elapsed < 60 ? 1 : elapsed ~/ 60;
    final now = DateTime.now();
    final hour = now.hour;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final timeStr =
        '${h.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} $ampm';
    appState.addSession(SessionData(
      title: 'Focus Session',
      status: 'Stopped • ${focusMin}m focus',
      time: timeStr,
      completed: false,
      date: now,
      focusMinutes: focusMin,
    ));
    appState.resetTimer();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Session logged: ${focusMin}m of focus'),
        backgroundColor: const Color(0xFF006C49),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// STATS SCREEN
// ─────────────────────────────────────────────

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final distribution = appState.weeklyDistribution;
    final maxVal = appState.weeklyMax;
    final streak = appState.currentStreak;
    final todayIdx = DateTime.now().weekday - 1; // Mon=0

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text(
            'Statistics',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF131B2E),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Track your focus patterns and productivity trends.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: const Color(0xFF464554)),
          ),
          const SizedBox(height: 32),

          // Summary cards row
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Avg Daily Focus',
                  value: appState.averageDailyFocusLabel,
                  icon: Icons.access_time_rounded,
                  color: const Color(0xFF4648D4),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _StatCard(
                  title: 'Current Streak',
                  value: '$streak Day${streak == 1 ? '' : 's'}',
                  icon: Icons.local_fire_department_rounded,
                  color: const Color(0xFF006C49),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Sessions Total',
                  value: '${appState.recentSessions.length}',
                  icon: Icons.playlist_add_check_rounded,
                  color: const Color(0xFF9C27B0),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _StatCard(
                  title: 'Today',
                  value: () {
                    final m = appState.totalFocusMinutesToday;
                    if (m == 0) return '0m';
                    final h = m ~/ 60;
                    final rem = m % 60;
                    return h > 0 ? '${h}h ${rem}m' : '${rem}m';
                  }(),
                  icon: Icons.today_rounded,
                  color: const Color(0xFFE65100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Chart section
          Text(
            'This Week\'s Focus',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Minutes of focused work per day',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF767586)),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 160,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(7, (i) {
                      final mins = distribution[i];
                      final fill = mins / maxVal;
                      final isToday = i == todayIdx;
                      final hasData = mins > 0;
                      return _ChartBar(
                        fillFraction: fill,
                        label: _days[i],
                        minutes: mins.toInt(),
                        isToday: isToday,
                        hasData: hasData,
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Weekly insight
          if (appState.recentSessions.isNotEmpty) ...[
            Text(
              'Weekly Insight',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4648D4), Color(0xFF7B5EA7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insights_rounded,
                      color: Colors.white, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      streak > 3
                          ? 'Great momentum! You\'ve been consistent for $streak days. Keep it up!'
                          : streak > 0
                              ? 'You\'re building a streak! Focus every day to grow it further.'
                              : 'Start a session today to build your streak and track progress.',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartBar extends StatelessWidget {
  final double fillFraction;
  final String label;
  final int minutes;
  final bool isToday;
  final bool hasData;

  const _ChartBar({
    required this.fillFraction,
    required this.label,
    required this.minutes,
    required this.isToday,
    required this.hasData,
  });

  @override
  Widget build(BuildContext context) {
    const maxBarHeight = 110.0;
    final barHeight = (fillFraction * maxBarHeight).clamp(4.0, maxBarHeight);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (hasData)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              minutes >= 60
                  ? '${minutes ~/ 60}h${minutes % 60 > 0 ? '${minutes % 60}m' : ''}'
                  : '${minutes}m',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: isToday
                    ? const Color(0xFF4648D4)
                    : const Color(0xFF767586),
              ),
            ),
          )
        else
          const SizedBox(height: 18),
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          width: 28,
          height: barHeight,
          decoration: BoxDecoration(
            color: isToday
                ? const Color(0xFF4648D4)
                : hasData
                    ? const Color(0xFF9FA8F5)
                    : const Color(0xFFE8EAFD),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isToday
                ? const Color(0xFF4648D4)
                : const Color(0xFF767586),
            fontSize: 12,
            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF767586),
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF131B2E),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SETTINGS SCREEN
// ─────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showEditNameDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController(text: appState.userName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profile Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter your name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              appState.updateUserName(controller.text);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4648D4),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDurationPicker({
    required BuildContext context,
    required String title,
    required int currentValue,
    required int min,
    required int max,
    required void Function(int) onSave,
  }) {
    int selected = currentValue;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$selected minutes',
                style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    onPressed: selected > min
                        ? () => setState(() => selected -= 5)
                        : null,
                    icon: const Icon(Icons.remove),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF4648D4),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Slider(
                    value: selected.toDouble(),
                    min: min.toDouble(),
                    max: max.toDouble(),
                    divisions: (max - min) ~/ 5,
                    activeColor: const Color(0xFF4648D4),
                    onChanged: (v) => setState(() => selected = v.toInt()),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filled(
                    onPressed: selected < max
                        ? () => setState(() => selected += 5)
                        : null,
                    icon: const Icon(Icons.add),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF4648D4),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                onSave(selected);
                Navigator.of(ctx).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4648D4),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text(
            'Settings',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF131B2E),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tailor your focus environment to match your workflow.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: const Color(0xFF464554)),
          ),
          const SizedBox(height: 32),

          // Profile card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFE1E0FF),
                  child: Text(
                    appState.initials,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4648D4),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appState.userName,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Flow Master • ${appState.currentStreak} Day Streak',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: const Color(0xFF006C49),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: Color(0xFF767586)),
                  onPressed: () => _showEditNameDialog(context, appState),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          _SectionHeader(title: 'Timer Settings'),
          _TappableTile(
            title: 'Focus Duration',
            subtitle: 'Length of your deep work sessions',
            trailing: _ValueChip(label: '${appState.focusDurationMinutes}m'),
            onTap: () => _showDurationPicker(
              context: context,
              title: 'Focus Duration',
              currentValue: appState.focusDurationMinutes,
              min: 5,
              max: 120,
              onSave: appState.setFocusDuration,
            ),
          ),
          _TappableTile(
            title: 'Short Break',
            subtitle: 'Brief rest between sessions',
            trailing: _ValueChip(label: '${appState.shortBreakMinutes}m'),
            onTap: () => _showDurationPicker(
              context: context,
              title: 'Short Break Duration',
              currentValue: appState.shortBreakMinutes,
              min: 1,
              max: 30,
              onSave: appState.setShortBreak,
            ),
          ),
          _SwitchTile(
            title: 'Auto-start Breaks',
            subtitle: 'Begin rest period automatically after session',
            value: appState.autoStartBreak,
            onChanged: appState.setAutoStartBreak,
          ),
          const SizedBox(height: 24),

          _SectionHeader(title: 'Notifications'),
          _SwitchTile(
            title: 'Session Ending Sound',
            subtitle: 'Gentle chime when focus time ends',
            value: appState.sessionEndSound,
            onChanged: appState.setSessionEndSound,
          ),
          _SwitchTile(
            title: 'Haptic Feedback',
            subtitle: 'Vibration on timer start/stop',
            value: appState.hapticFeedback,
            onChanged: appState.setHapticFeedback,
          ),
          _SwitchTile(
            title: 'Smart DND',
            subtitle: 'Sync with device Do Not Disturb',
            value: appState.smartDND,
            onChanged: appState.setSmartDND,
          ),
          const SizedBox(height: 24),

          _SectionHeader(title: 'Data'),
          _TappableTile(
            title: 'Clear All Sessions',
            subtitle: 'Remove all session history and reset stats',
            trailing: const Icon(Icons.delete_outline,
                color: Color(0xFFBA1A1A), size: 20),
            onTap: () => _showClearDataDialog(context, appState),
          ),
          const SizedBox(height: 24),

          _SectionHeader(title: 'Account'),
          const _InfoTile(
            title: 'Email Address',
            subtitle: 'deepika@gmail.com',
          ),
          const _InfoTile(
            title: 'Subscription',
            subtitle: 'Pro Plan',
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFBA1A1A),
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.zero,
            ),
            child: const Text('Sign Out'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showClearDataDialog(BuildContext context, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
            'This will delete all sessions and reset statistics. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              for (int i = appState.recentSessions.length - 1; i >= 0; i--) {
                appState.deleteSession(i);
              }
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All data cleared')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFBA1A1A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ── Settings helper widgets ──────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF4648D4),
            ),
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  final String label;
  const _ValueChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAFD),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF4648D4),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.edit, size: 12, color: Color(0xFF4648D4)),
        ],
      ),
    );
  }
}

class _TappableTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _TappableTile({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Color(0xFF131B2E))),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xFF767586), fontSize: 14)),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ]
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Color(0xFF131B2E))),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xFF767586), fontSize: 14)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF4648D4),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String title;
  final String subtitle;

  const _InfoTile({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Color(0xFF131B2E))),
          const SizedBox(height: 3),
          Text(subtitle,
              style:
                  const TextStyle(color: Color(0xFF767586), fontSize: 14)),
        ],
      ),
    );
  }
}