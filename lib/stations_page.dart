import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const _apiKey = String.fromEnvironment('BIKE_KEY');

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
  List<Station> _stations = [];
  Set<String> _favorites = {};
  double _userLat = 37.5665, _userLng = 126.9780;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      _favorites = (prefs.getStringList('fav_stations') ?? []).toSet();

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw '위치 권한이 필요해요';
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

  Future<void> _navigate(Station s) async {
    final uri = Uri.parse(
        'geo:${s.lat},${s.lng}?q=${s.lat},${s.lng}(${Uri.encodeComponent(s.name)})');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
          _filterBar(),
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
          onSelected: (_) => setState(() => _filter = key),
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
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
              '🚲 ${s.bikes}대   🅿️ ${s.empty}자리   ·   ${s.dist.round()}m'),
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

  Widget _buildMap() {
    final list = _filtered();
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(_userLat, _userLng),
        initialZoom: 15,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.ttareungi',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(_userLat, _userLng),
              width: 40,
              height: 40,
              child:
                  const Icon(Icons.my_location, color: Colors.blue, size: 28),
            ),
            ...list.map((s) {
              return Marker(
                point: LatLng(s.lat, s.lng),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('${s.name}\n🚲 ${s.bikes}대  🅿️ ${s.empty}자리'),
                      action: SnackBarAction(
                          label: '길찾기', onPressed: () => _navigate(s)),
                    ),
                  ),
                  child: Icon(
                    Icons.pedal_bike,
                    color: s.bikes > 0 ? Colors.green : Colors.red,
                    size: 28,
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }
}
