import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'stations_page.dart';

final FlutterLocalNotificationsPlugin _notif =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _notif.initialize(
      settings: const InitializationSettings(android: android));

  await _notif
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  await _notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
}

Future<void> _scheduleNotif(
    int id, DateTime when, String title, String body) async {
  if (when.isBefore(DateTime.now())) return;
  await _notif.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: tz.TZDateTime.from(when, tz.local),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'ttareungi_channel',
        '따릉이 반납 알림',
        channelDescription: '따릉이 반납 시간 알림',
        importance: Importance.max,
        priority: Priority.high,
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.alarmClock,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  runApp(const TtareungiApp());
}

class TtareungiApp extends StatelessWidget {
  const TtareungiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '따릉이 도우미',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const TimerPage(),
    );
  }
}

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  DateTime? _startTime;
  Duration _limit = Duration.zero;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  // 자전거를 빌린 뒤 앱을 늦게 켜면 타이머가 그만큼 어긋난다. 대여 시각을 소급 보정.
  int _startedAgoMin = 0;

  static const _kStart = 'start_ms';
  static const _kLimit = 'limit_sec';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final startMs = prefs.getInt(_kStart);
    final limitSec = prefs.getInt(_kLimit);
    if (startMs != null && limitSec != null) {
      setState(() {
        _startTime = DateTime.fromMillisecondsSinceEpoch(startMs);
        _limit = Duration(seconds: limitSec);
      });
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    final deadline = _startTime!.add(_limit);
    setState(() => _remaining = deadline.difference(DateTime.now()));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _remaining = deadline.difference(DateTime.now()));
    });
  }

  Future<void> _startRental(Duration limit) async {
    final start =
        DateTime.now().subtract(Duration(minutes: _startedAgoMin));
    final deadline = start.add(limit);
    setState(() {
      _startTime = start;
      _limit = limit;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kStart, start.millisecondsSinceEpoch);
    await prefs.setInt(_kLimit, limit.inSeconds);

    await _notif.cancelAll();
    final before30 = deadline.subtract(const Duration(minutes: 30));
    await _scheduleNotif(1, before30, '반납 30분 전', '반납까지 30분 남았어요');
    await _scheduleNotif(2, deadline, '반납 시간', '지금 반납하세요');

    _startTicker();
  }

  Future<void> _returnBike() async {
    _ticker?.cancel();
    setState(() {
      _startTime = null;
      _remaining = Duration.zero;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStart);
    await prefs.remove(_kLimit);
    await _notif.cancelAll();
    setState(() => _startedAgoMin = 0);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  String _formatRemaining(Duration d) {
    final a = d.abs();
    final h = _two(a.inHours);
    final m = _two(a.inMinutes % 60);
    final s = _two(a.inSeconds % 60);
    final text = '$h:$m:$s';
    return d.isNegative ? '+$text' : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('따릉이 도우미'),
        actions: [
          IconButton(
            icon: const Icon(Icons.pedal_bike),
            tooltip: '내 주변 대여소',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StationsPage()),
            ),
          ),
        ],
      ),
      body: Center(
        child: _startTime == null ? _idleView() : _rentingView(),
      ),
    );
  }

  Widget _agoChips() {
    Widget chip(int min, String label) => ChoiceChip(
          label: Text(label),
          selected: _startedAgoMin == min,
          onSelected: (_) => setState(() => _startedAgoMin = min),
        );

    return Column(
      children: [
        const Text('언제 빌렸나요?', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            chip(0, '지금'),
            chip(5, '5분 전'),
            chip(10, '10분 전'),
            chip(15, '15분 전'),
            chip(20, '20분 전'),
            chip(30, '30분 전'),
          ],
        ),
        if (_startedAgoMin > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '대여 시각을 ${_clock(DateTime.now().subtract(Duration(minutes: _startedAgoMin)))}로 계산해요',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
      ],
    );
  }

  Widget _idleView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _agoChips(),
        const SizedBox(height: 28),
        const Text('이용권을 선택하세요', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _startRental(const Duration(hours: 1)),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            child: Text('1시간권 대여 시작', style: TextStyle(fontSize: 18)),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () => _startRental(const Duration(hours: 2)),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            child: Text('2시간권 대여 시작', style: TextStyle(fontSize: 18)),
          ),
        ),
      ],
    );
  }

  Widget _rentingView() {
    final deadline = _startTime!.add(_limit);
    final isOver = _remaining.isNegative;
    final color = isOver
        ? Colors.red
        : (_remaining.inMinutes < 10 ? Colors.orange : Colors.green);
    final label = isOver ? '반납 시간 초과!' : '반납까지 남은 시간';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('대여 ${_clock(_startTime!)}  →  반납 ${_clock(deadline)}',
            style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 24),
        Text(label, style: TextStyle(fontSize: 18, color: color)),
        const SizedBox(height: 8),
        Text(
          _formatRemaining(_remaining),
          style: TextStyle(
              fontSize: 56, fontWeight: FontWeight.bold, color: color),
        ),
        if (isOver)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('추가요금이 부과될 수 있어요',
                style: TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 32),
        OutlinedButton(
          onPressed: _returnBike,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text('반납하기', style: TextStyle(fontSize: 18)),
          ),
        ),
      ],
    );
  }
}