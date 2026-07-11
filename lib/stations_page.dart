import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _apiKey = String.fromEnvironment('BIKE_KEY');

// OSM 타일의 공원/산이 초록이라 초록 마커가 묻힌다. 자전거=파랑, 빈 거치대=주황, 없음=회색.
const _cBike = Color(0xFF1565C0);
const _cEmpty = Color(0xFFE65100);
const _cNone = Color(0xFF9E9E9E);

class Station {
  final String name;
  final double lat, lng;
  final int racks, bikes;
  double dist = 0;
  Station(this.name, this.lat, this.lng, this.racks, this.bikes);
  int get empty => racks - bikes < 0 ? 0 : racks - bikes;
}

class StationsPage extends StatefulWidget {
  const StationsPage({super.key});
  @override
  State<StationsPage> createState() => _StationsPageState();
}

class _StationsPageState extends State<StationsPage> {
  bool _loading = true;
  bool _showMap = false;
  String _filter = 'all';
  String? _error;
  bool _needsSettings = false; // 위치 권한 영구 거부 → 앱 설정으로 보내야 함
  bool _outOfArea = false; // 서울 밖. 따릉이는 서울시 전용 서비스.
  List<Station> _stations = [];
  Set<String> _favorites = {};
  Station? _selected; // 지도에서 탭한 대여소 (하단 카드로 표시)
  double _userLat = 37.5665, _userLng = 126.9780;

  // '반납 가능' 필터일 때는 자전거 수가 아니라 빈 거치대 수가 관심사다.
  bool get _returnMode => _filter == 'return';

  bool get _ready => !_loading && _error == null && !_outOfArea;

  static String _distText(double m) =>
      m < 1000 ? '${m.round()}m' : '${(m / 1000).toStringAsFixed(1)}km';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<Station>> _fetchPage(int start, int end) async {
    final url = Uri.parse(
        'http://openapi.seoul.go.kr:8088/$_apiKey/json/bikeList/$start/$end/');
    final res = await http.get(url);
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final rows = (data['rentBikeStatus']?['row'] ?? []) as List;
    return rows.map((r) {
      return Station(
        (r['stationName'] ?? '').toString(),
        double.tryParse('${r['stationLatitude']}') ?? 0,
        double.tryParse('${r['stationLongitude']}') ?? 0,
        int.tryParse('${r['rackTotCnt']}') ?? 0,
        int.tryParse('${r['parkingBikeTotCnt']}') ?? 0,
      );
    }).toList();
  }

  // 가장 가까운 대여소가 이보다 멀면 서울권 밖으로 본다(서울 대각 폭이 대략 30km).
  static const _kOutOfAreaMeters = 30000.0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _needsSettings = false;
      _outOfArea = false;
      _selected = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      _favorites = (prefs.getStringList('fav_stations') ?? []).toSet();

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() {
          _needsSettings = true;
          _error = '위치 권한이 꺼져 있어요.\n설정에서 허용해 주세요.';
          _loading = false;
        });
        return;
      }
      if (perm == LocationPermission.denied) {
        throw '내 주변 대여소를 찾으려면 위치 권한이 필요해요';
      }
      final pos = await Geolocator.getCurrentPosition();
      _userLat = pos.latitude;
      _userLng = pos.longitude;

      final all = <Station>[];
      for (final s in [1, 1001, 2001]) {
        all.addAll(await _fetchPage(s, s + 999));
      }

      for (final st in all) {
        st.dist =
            Geolocator.distanceBetween(_userLat, _userLng, st.lat, st.lng);
      }
      all.sort((a, b) => a.dist.compareTo(b.dist));

      if (all.isEmpty || all.first.dist > _kOutOfAreaMeters) {
        setState(() {
          _outOfArea = true;
          _loading = false;
        });
        return;
      }

      setState(() {
        _stations = all.take(40).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<Station> _filtered() {
    Iterable<Station> list = _stations;
    if (_filter == 'rent') {
      list = list.where((s) => s.bikes > 0);
    } else if (_filter == 'return') {
      list = list.where((s) => s.empty > 0);
    } else if (_filter == 'fav') {
      list = list.where((s) => _favorites.contains(s.name));
    }
    return list.toList();
  }

  Future<void> _toggleFav(String name) async {
    setState(() {
      if (_favorites.contains(name)) {
        _favorites.remove(name);
      } else {
        _favorites.add(name);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('fav_stations', _favorites.toList());
  }

  // 네이버지도 → 카카오맵 → 구글맵 순으로 시도. 설치 여부 감지는 AndroidManifest의
  // <queries> 패키지 선언이 있어야 동작한다(Android 11+ 패키지 가시성).
  Future<void> _navigate(Station s) async {
    final name = Uri.encodeComponent(s.name);
    final candidates = <Uri>[
      Uri.parse('nmap://route/walk?dlat=${s.lat}&dlng=${s.lng}'
          '&dname=$name&appname=com.sooya8922.ttareungi'),
      Uri.parse('kakaomap://route?ep=${s.lat},${s.lng}&by=FOOT'),
      Uri.parse('https://www.google.com/maps/dir/?api=1'
          '&destination=${s.lat},${s.lng}&travelmode=walking'),
    ];
    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri) &&
            await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {
        // 다음 후보로
      }
    }
    await launchUrl(
      Uri.parse('geo:${s.lat},${s.lng}?q=${s.lat},${s.lng}($name)'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('내 주변 따릉이'),
        actions: [
          IconButton(
            onPressed: () => setState(() => _showMap = !_showMap),
            icon: Icon(_showMap ? Icons.list : Icons.map),
            tooltip: _showMap ? '목록' : '지도',
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (_ready) _filterBar(),
          if (_ready && _showMap) _legend(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _filterBar() {
    Widget chip(String key, String label) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == key,
          onSelected: (_) => setState(() {
            _filter = key;
            _selected = null;
          }),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          chip('all', '전체'),
          chip('rent', '빌릴 수 있음'),
          chip('return', '반납 가능'),
          chip('fav', '⭐ 즐겨찾기'),
        ],
      ),
    );
  }

  Widget _legend() {
    final items = _splitPin
        ? [
            (_cBike, '위 = 자전거 수'),
            (_cEmpty, '아래 = 빈 거치대'),
            (_cNone, '0'),
          ]
        : [
            (_returnMode ? _cEmpty : _cBike,
                _returnMode ? '빈 거치대 수' : '자전거 수'),
            (_cNone, '없음'),
          ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: Colors.black.withValues(alpha: 0.04),
      child: Row(
        children: [
          for (final (c, label) in items) ...[
            _dot(c),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 14),
          ],
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      );

  Widget _notice(IconData icon, String text, List<Widget> actions) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade500),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            Wrap(spacing: 10, children: actions),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_outOfArea) {
      return _notice(
        Icons.location_off,
        '주변에 따릉이 대여소가 없어요.\n\n따릉이는 서울시에서만 운영해요.\n서울에서 다시 시도해 주세요.',
        [FilledButton(onPressed: _load, child: const Text('다시 시도'))],
      );
    }
    if (_error != null) {
      return _notice(Icons.error_outline, _error!, [
        if (_needsSettings)
          FilledButton(
            onPressed: Geolocator.openAppSettings,
            child: const Text('설정 열기'),
          ),
        OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
      ]);
    }
    return _showMap ? _buildMap() : _buildList();
  }

  Widget _buildList() {
    final list = _filtered();
    if (list.isEmpty) {
      return const Center(child: Text('해당하는 대여소가 없어요'));
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final s = list[i];
        final fav = _favorites.contains(s.name);
        return ListTile(
          title: Text(s.name),
          subtitle: Text(
              '🚲 ${s.bikes}대   🅿️ ${s.empty}자리   ·   ${_distText(s.dist)}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(fav ? Icons.star : Icons.star_border,
                    color: fav ? Colors.amber : null),
                onPressed: () => _toggleFav(s.name),
              ),
              IconButton(
                icon: const Icon(Icons.directions),
                onPressed: () => _navigate(s),
              ),
            ],
          ),
        );
      },
    );
  }

  // '빌릴 수 있음'/'반납 가능' 필터는 관심 숫자가 하나뿐이라 단색 원.
  // '전체'/'즐겨찾기'는 자전거 수와 빈 거치대 수를 둘 다 알아야 하므로 위아래 2단.
  bool get _splitPin => _filter == 'all' || _filter == 'fav';

  static const _numStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.bold,
    fontSize: 12,
  );

  BoxBorder _pinBorder(Station s) {
    final fav = _favorites.contains(s.name);
    final sel = _selected?.name == s.name;
    return Border.all(
      color: sel ? Colors.black87 : (fav ? Colors.amber : Colors.white),
      width: sel ? 3 : (fav ? 2.5 : 2),
    );
  }

  static const _pinShadow = [
    BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
  ];

  Widget _half(int n, Color on) => Container(
        color: n == 0 ? _cNone : on,
        alignment: Alignment.center,
        child: Text('$n', style: _numStyle),
      );

  Widget _pin(Station s) {
    if (!_splitPin) {
      final n = _returnMode ? s.empty : s.bikes;
      final bg = n == 0 ? _cNone : (_returnMode ? _cEmpty : _cBike);
      return Container(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: _pinBorder(s),
          boxShadow: _pinShadow,
        ),
        alignment: Alignment.center,
        child: Text('${_returnMode ? s.empty : s.bikes}', style: _numStyle),
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: _pinBorder(s),
        boxShadow: _pinShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(child: _half(s.bikes, _cBike)),
          Expanded(child: _half(s.empty, _cEmpty)),
        ],
      ),
    );
  }

  // SnackBar는 하나가 떠 있으면 다음 것을 큐에 쌓아둬서, 다른 대여소를 눌러도
  // 정보가 안 바뀌는 것처럼 보였다. 하단 카드로 교체.
  Widget _infoCard(Station s) {
    final fav = _favorites.contains(s.name);
    return Card(
      margin: const EdgeInsets.all(10),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _stat(_cBike, '자전거 ${s.bikes}대'),
                      const SizedBox(width: 10),
                      _stat(_cEmpty, '빈 거치대 ${s.empty}자리'),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_distText(s.dist),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(fav ? Icons.star : Icons.star_border,
                  color: fav ? Colors.amber : null),
              onPressed: () => _toggleFav(s.name),
            ),
            IconButton(
              icon: const Icon(Icons.directions),
              tooltip: '길찾기',
              onPressed: () => _navigate(s),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _selected = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(Color c, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dot(c),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      );

  Widget _buildMap() {
    final list = _filtered();
    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(_userLat, _userLng),
            initialZoom: 15,
            onTap: (_, _) => setState(() => _selected = null),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sooya8922.ttareungi',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(_userLat, _userLng),
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.my_location,
                      color: Colors.blue, size: 28),
                ),
                ...list.map((s) {
                  return Marker(
                    point: LatLng(s.lat, s.lng),
                    width: _splitPin ? 32 : 34,
                    height: _splitPin ? 42 : 34,
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = s),
                      child: _pin(s),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
        if (_selected != null)
          Align(
            alignment: Alignment.bottomCenter,
            // Android 15부터 화면이 내비게이션 바 아래까지 확장돼서, SafeArea가 없으면
            // 카드가 '뒤로가기/홈' 바에 가린다.
            child: SafeArea(child: _infoCard(_selected!)),
          ),
      ],
    );
  }
}
