import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const FocusTimerApp());
}

class FocusTimerApp extends StatelessWidget {
  const FocusTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Focus Timer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF315D4A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F5EF),
        fontFamily: 'Avenir Next',
      ),
      home: const TimerPage(),
    );
  }
}

enum TimerMode { focus, shortBreak, longBreak }

extension TimerModeDetails on TimerMode {
  String get label => switch (this) {
    TimerMode.focus => 'Focus',
    TimerMode.shortBreak => 'Short break',
    TimerMode.longBreak => 'Long break',
  };

  String get storageKey => switch (this) {
    TimerMode.focus => 'focus',
    TimerMode.shortBreak => 'shortBreak',
    TimerMode.longBreak => 'longBreak',
  };

  Color get color => switch (this) {
    TimerMode.focus => const Color(0xFF315D4A),
    TimerMode.shortBreak => const Color(0xFF507AA0),
    TimerMode.longBreak => const Color(0xFF936B48),
  };
}

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  static const _modePreference = 'timer.mode';
  static const _durationPreference = 'timer.durations';
  static const _sessionsPreference = 'sessions.today';
  static const _sessionsDatePreference = 'sessions.date';
  static const _historyPreference = 'sessions.history';

  static const _defaultDurations = <TimerMode, int>{
    TimerMode.focus: 25,
    TimerMode.shortBreak: 5,
    TimerMode.longBreak: 15,
  };

  final Map<TimerMode, int> _durations = Map.of(_defaultDurations);
  final List<Map<String, dynamic>> _history = [];
  SharedPreferences? _preferences;
  TimerMode _mode = TimerMode.focus;
  Duration _remaining = const Duration(minutes: 25);
  DateTime? _deadline;
  Timer? _ticker;
  int _sessionsToday = 0;
  String _today = _dateKey(DateTime.now());
  String? _storageError;
  bool _ready = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _loadPreferences() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final modeKey = preferences.getString(_modePreference);
      if (modeKey != null) {
        _mode = TimerMode.values.firstWhere(
          (mode) => mode.storageKey == modeKey,
          orElse: () => throw FormatException('Unknown timer mode: $modeKey'),
        );
      }

      final durationsJson = preferences.getString(_durationPreference);
      if (durationsJson != null) {
        final decoded = jsonDecode(durationsJson);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Saved timer durations are invalid.');
        }
        for (final mode in TimerMode.values) {
          final value = decoded[mode.storageKey];
          if (value != null) {
            if (value is! int || value < 1 || value > 180) {
              throw FormatException(
                'Saved duration for ${mode.label} must be 1–180 minutes.',
              );
            }
            _durations[mode] = value;
          }
        }
      }

      final historyJson = preferences.getString(_historyPreference);
      if (historyJson != null) {
        final decoded = jsonDecode(historyJson);
        if (decoded is! List<dynamic>) {
          throw const FormatException('Saved session history is invalid.');
        }
        for (final entry in decoded) {
          if (entry is! Map<String, dynamic>) {
            throw const FormatException('Saved session history is invalid.');
          }
          _history.add(entry);
        }
      }

      _preferences = preferences;
      _today = _dateKey(DateTime.now());
      final savedDate = preferences.getString(_sessionsDatePreference);
      _sessionsToday = savedDate == _today
          ? preferences.getInt(_sessionsPreference) ?? 0
          : 0;
      _remaining = _durationFor(_mode);
      if (savedDate != _today) {
        await _writePreference(
          preferences.setString(_sessionsDatePreference, _today),
          _sessionsDatePreference,
        );
        await _writePreference(
          preferences.setInt(_sessionsPreference, 0),
          _sessionsPreference,
        );
      }
    } catch (error) {
      _reportStorageError(error);
    } finally {
      if (mounted) {
        setState(() => _ready = true);
      }
    }
  }

  Duration _durationFor(TimerMode mode) =>
      Duration(minutes: _durations[mode] ?? _defaultDurations[mode]!);

  Future<void> _writePreference(Future<bool> write, String key) async {
    if (!await write) {
      throw StateError('Could not save $key.');
    }
  }

  void _reportStorageError(Object error) {
    debugPrint('Focus Timer storage error: $error');
    if (mounted) {
      setState(
        () => _storageError = 'Could not save or load your data: $error',
      );
    }
  }

  Future<void> _selectMode(TimerMode mode) async {
    if (!_ready || mode == _mode) return;
    try {
      final preferences = _preferences;
      if (preferences != null) {
        await _writePreference(
          preferences.setString(_modePreference, mode.storageKey),
          _modePreference,
        );
      }
      _ticker?.cancel();
      setState(() {
        _mode = mode;
        _remaining = _durationFor(mode);
        _running = false;
        _deadline = null;
      });
    } catch (error) {
      _reportStorageError(error);
    }
  }

  void _toggleTimer() {
    if (!_ready) return;
    if (_running) {
      _ticker?.cancel();
      setState(() {
        _remaining = _deadline!.difference(DateTime.now());
        if (_remaining.isNegative) _remaining = Duration.zero;
        _running = false;
        _deadline = null;
      });
      return;
    }

    _deadline = DateTime.now().add(_remaining);
    setState(() => _running = true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _resetTimer() {
    if (!_ready) return;
    _ticker?.cancel();
    setState(() {
      _running = false;
      _deadline = null;
      _remaining = _durationFor(_mode);
    });
  }

  void _tick() {
    final deadline = _deadline;
    if (!_running || deadline == null) return;
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _ticker?.cancel();
      _ticker = null;
      setState(() {
        _remaining = Duration.zero;
        _running = false;
      });
      _completeSession();
      return;
    }
    setState(() => _remaining = remaining);
  }

  Future<void> _completeSession() async {
    final completedMode = _mode;
    final preferences = _preferences;
    var updatedSessionsToday = _sessionsToday;
    var nextMode = TimerMode.focus;
    final updatedHistory = List<Map<String, dynamic>>.of(_history);

    if (completedMode == TimerMode.focus) {
      final currentDate = _dateKey(DateTime.now());
      updatedSessionsToday = currentDate == _today ? _sessionsToday + 1 : 1;
      updatedHistory.add({
        'mode': completedMode.storageKey,
        'completedAt': DateTime.now().toIso8601String(),
      });
      nextMode = updatedSessionsToday % 4 == 0
          ? TimerMode.longBreak
          : TimerMode.shortBreak;
      if (preferences != null) {
        try {
          await _writePreference(
            preferences.setString(_sessionsDatePreference, currentDate),
            _sessionsDatePreference,
          );
          await _writePreference(
            preferences.setInt(_sessionsPreference, updatedSessionsToday),
            _sessionsPreference,
          );
          await _writePreference(
            preferences.setString(
              _historyPreference,
              jsonEncode(updatedHistory),
            ),
            _historyPreference,
          );
          await _writePreference(
            preferences.setString(_modePreference, nextMode.storageKey),
            _modePreference,
          );
        } catch (error) {
          _reportStorageError(error);
          return;
        }
      }
      _today = currentDate;
    } else {
      updatedHistory.add({
        'mode': completedMode.storageKey,
        'completedAt': DateTime.now().toIso8601String(),
      });
      nextMode = TimerMode.focus;
      if (preferences != null) {
        try {
          await _writePreference(
            preferences.setString(
              _historyPreference,
              jsonEncode(updatedHistory),
            ),
            _historyPreference,
          );
          await _writePreference(
            preferences.setString(_modePreference, nextMode.storageKey),
            _modePreference,
          );
        } catch (error) {
          _reportStorageError(error);
          return;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _history
        ..clear()
        ..addAll(updatedHistory);
      _sessionsToday = updatedSessionsToday;
      _mode = nextMode;
      _remaining = _durationFor(nextMode);
      _running = true;
      _deadline = DateTime.now().add(_remaining);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    });
  }

  Future<void> _openSettings() async {
    if (!_ready) return;
    final formKey = GlobalKey<FormState>();
    final updatedValues = <TimerMode, int>{};

    try {
      final updatedDurations = await showDialog<Map<TimerMode, int>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Timer settings'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in TimerMode.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      initialValue: '${_durations[mode]}',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '${mode.label} (minutes)',
                        suffixText: 'min',
                      ),
                      onSaved: (value) {
                        updatedValues[mode] = int.parse(value!);
                      },
                      validator: (value) {
                        final minutes = int.tryParse(value ?? '');
                        if (minutes == null || minutes < 1 || minutes > 180) {
                          return 'Enter 1–180 minutes';
                        }
                        return null;
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                formKey.currentState!.save();
                Navigator.pop(context, updatedValues);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (updatedDurations == null) return;
      final preferences = _preferences;
      if (preferences != null) {
        await _writePreference(
          preferences.setString(
            _durationPreference,
            jsonEncode({
              for (final mode in TimerMode.values)
                mode.storageKey: updatedDurations[mode],
            }),
          ),
          _durationPreference,
        );
      }
      if (!mounted) return;
      setState(() {
        _durations.addAll(updatedDurations);
        if (!_running) _remaining = _durationFor(_mode);
      });
    } catch (error) {
      _reportStorageError(error);
    }
  }

  String get _formattedTime {
    final seconds = math.max(0, _remaining.inSeconds);
    final minutesText = (seconds ~/ 60).toString().padLeft(2, '0');
    final secondsText = (seconds % 60).toString().padLeft(2, '0');
    return '$minutesText:$secondsText';
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = _durationFor(_mode).inSeconds;
    final progress = totalSeconds == 0
        ? 0.0
        : (_remaining.inSeconds / totalSeconds).clamp(0.0, 1.0);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_storageError != null)
              MaterialBanner(
                content: Text(_storageError!),
                leading: const Icon(Icons.warning_amber_rounded),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _storageError = null),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            Expanded(
              child: !_ready
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final ringSize = math.min(
                          constraints.maxWidth * 0.72,
                          300.0,
                        );
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Column(
                                children: [
                                  _buildHeader(),
                                  const SizedBox(height: 32),
                                  _buildModeSelector(),
                                  const SizedBox(height: 36),
                                  SizedBox(
                                    width: ringSize,
                                    height: ringSize,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        SizedBox.expand(
                                          child: CircularProgressIndicator(
                                            value: progress,
                                            strokeWidth: 10,
                                            strokeCap: StrokeCap.round,
                                            backgroundColor: const Color(
                                              0xFFE7E5DC,
                                            ),
                                            color: _mode.color,
                                          ),
                                        ),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _running
                                                  ? 'TIME TO FOCUS'
                                                  : 'READY WHEN YOU ARE',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                    letterSpacing: 1.6,
                                                    color: const Color(
                                                      0xFF7C817A,
                                                    ),
                                                  ),
                                            ),
                                            const SizedBox(height: 8),
                                            FittedBox(
                                              child: Text(
                                                _formattedTime,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .displayLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                      color: const Color(
                                                        0xFF27342D,
                                                      ),
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              _mode.label,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    color: _mode.color,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  _buildSessionCount(),
                                  const SizedBox(height: 28),
                                  _buildControls(),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE5EAE1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.spa_rounded, color: Color(0xFF315D4A)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FOCUS TIMER',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.8,
                  color: const Color(0xFF727B72),
                ),
              ),
              Text(
                'Make room for deep work',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _openSettings,
          tooltip: 'Timer settings',
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<TimerMode>(
      segments: const [
        ButtonSegment(value: TimerMode.focus, label: Text('Focus')),
        ButtonSegment(value: TimerMode.shortBreak, label: Text('Short')),
        ButtonSegment(value: TimerMode.longBreak, label: Text('Long')),
      ],
      selected: {_mode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => _selectMode(selection.first),
    );
  }

  Widget _buildSessionCount() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 19,
            color: Color(0xFF63816A),
          ),
          const SizedBox(width: 9),
          Text(
            '$_sessionsToday ${_sessionsToday == 1 ? 'session' : 'sessions'} completed today',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF46564B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _resetTimer,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Reset'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
            foregroundColor: const Color(0xFF46564B),
          ),
        ),
        const SizedBox(width: 14),
        FilledButton.icon(
          onPressed: _toggleTimer,
          icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
          label: Text(_running ? 'Pause' : 'Start'),
          style: FilledButton.styleFrom(
            backgroundColor: _mode.color,
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 17),
          ),
        ),
      ],
    );
  }
}
