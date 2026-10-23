import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';

/// Titik asal = lokasi GPS pengguna saat ini. Tujuan dipilih dengan
/// mengetuk peta atau mencari nama tempat; jarak garis lurus dihitung
/// dari lokasi pengguna ke tujuan.
class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  static const _fallbackCenter = LatLng(-2.5, 118.0); // tengah Indonesia

  final MapController _map = MapController();
  final TextEditingController _search = TextEditingController();

  bool _mapReady = false;
  bool _pendingFocus = false;

  Position? _pos;
  LocationException? _error;
  bool _loading = true;

  LatLng? _dest;
  String? _destName;
  bool _naming = false;
  int _nameSeq = 0;

  List<GeoPlace> _results = const [];
  bool _searching = false;
  String? _searchError;

  LatLng? get _me =>
      _pos == null ? null : LatLng(_pos!.latitude, _pos!.longitude);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _map.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Lokasi pengguna
  // ------------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pos = await LocationService.instance.currentPosition();
      if (!mounted) return;
      setState(() {
        _pos = pos;
        _loading = false;
      });
      _focus();
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onMapReady() {
    _mapReady = true;
    if (_pendingFocus) {
      _pendingFocus = false;
      _focus();
    }
  }

  /// Menggeser kamera: ke lokasi pengguna, atau memuat pengguna dan tujuan.
  void _focus() {
    if (!_mapReady) {
      _pendingFocus = true;
      return;
    }
    final me = _me;
    final dest = _dest;
    if (me != null && dest != null) {
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([me, dest]),
          padding: const EdgeInsets.fromLTRB(48, 120, 48, 240),
          maxZoom: 15,
        ),
      );
    } else if (me != null) {
      _map.move(me, 14);
    } else if (dest != null) {
      _map.move(dest, 11);
    }
  }

  // ------------------------------------------------------------------
  // Memilih tujuan
  // ------------------------------------------------------------------

  Future<void> _selectDestination(
    LatLng point, {
    String? name,
    bool fit = false,
  }) async {
    FocusScope.of(context).unfocus();
    final seq = ++_nameSeq;
    setState(() {
      _dest = point;
      _destName = name;
      _results = const [];
      _searchError = null;
      _naming = name == null;
    });
    if (fit) _focus();
    if (name != null) return;

    String? resolved;
    try {
      resolved = await GeocodingService.instance.reverseName(
        point.latitude,
        point.longitude,
      );
    } catch (_) {
      // Nama hanya pelengkap; jarak tetap ditampilkan.
    }
    if (!mounted || seq != _nameSeq) return;
    setState(() {
      _destName = resolved;
      _naming = false;
    });
  }

  void _clearDestination() {
    _nameSeq++;
    setState(() {
      _dest = null;
      _destName = null;
      _naming = false;
    });
    _focus();
  }

  Future<void> _doSearch() async {
    final q = _search.text.trim();
    if (q.length < 2 || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
      _results = const [];
    });
    try {
      final found = await GeocodingService.instance.search(q);
      if (!mounted) return;
      setState(() {
        _results = found;
        if (found.isEmpty) _searchError = 'Tempat tidak ditemukan.';
      });
    } on GeocodingException catch (e) {
      if (mounted) setState(() => _searchError = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ------------------------------------------------------------------
  // Tampilan
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lokasi & Jarak'),
        actions: [
          IconButton(
            tooltip: 'Perbarui lokasi saya',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          _mapView(),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _searchArea(),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(top: false, child: _infoPanel()),
          ),
        ],
      ),
    );
  }

  Widget _mapView() {
    final me = _me;
    final dest = _dest;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _fallbackCenter,
        initialZoom: 5,
        minZoom: 3,
        maxZoom: 18,
        onMapReady: _onMapReady,
        onTap: (_, point) => _selectDestination(point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.noir_final_project',
        ),
        if (me != null && dest != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [me, dest],
                strokeWidth: 4,
                color: AppColors.yellow,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (me != null)
              Marker(
                point: me,
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F80ED),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            if (dest != null)
              Marker(
                point: dest,
                width: 44,
                height: 44,
                alignment: Alignment.topCenter,
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 44,
                  color: AppColors.error,
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  Widget _searchArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _doSearch(),
          decoration: InputDecoration(
            hintText: 'Cari kota atau tempat, mis. Bandung',
            filled: true,
            fillColor: AppColors.surface,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          setState(() {
                            _results = const [];
                            _searchError = null;
                          });
                        },
                      ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
        if (_searchError != null)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _searchError!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ),
        if (_results.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 6),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _results.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, i) {
                  final p = _results[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.place_outlined,
                      color: AppColors.yellow,
                    ),
                    title: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      p.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () => _selectDestination(
                      LatLng(p.latitude, p.longitude),
                      name: p.name,
                      fit: true,
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _infoPanel() {
    final pos = _pos;
    final dest = _dest;

    Widget content;
    if (pos == null) {
      content = _loading ? _loadingRow() : _errorRow();
    } else if (dest == null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pilih tujuan',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ketuk peta atau cari nama tempat untuk melihat jaraknya dari '
            'lokasi Anda.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          _meLine(pos),
        ],
      );
    } else {
      content = _distanceBlock(pos, dest);
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(16), child: content),
    );
  }

  Widget _loadingRow() => const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.yellow,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Mencari lokasi Anda...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      );

  Widget _errorRow() {
    final type = _error?.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _error?.message ?? 'Lokasi tidak tersedia.',
          style: const TextStyle(color: AppColors.error),
        ),
        const SizedBox(height: 4),
        const Text(
          'Peta tetap bisa dipakai, tetapi jarak butuh lokasi Anda.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            if (type == LocationFailure.serviceOff)
              const FilledButton(
                onPressed: Geolocator.openLocationSettings,
                child: Text('Pengaturan lokasi'),
              ),
            if (type == LocationFailure.deniedForever)
              const FilledButton(
                onPressed: Geolocator.openAppSettings,
                child: Text('Pengaturan aplikasi'),
              ),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _meLine(Position pos) {
    final taken = Formatters.dateTime(pos.timestamp.toUtc().toIso8601String());
    return Text(
      'Lokasi Anda ± ${pos.accuracy.round()} m · $taken',
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
    );
  }

  Widget _distanceBlock(Position pos, LatLng dest) {
    final meters = LocationService.haversineMeters(
      pos.latitude,
      pos.longitude,
      dest.latitude,
      dest.longitude,
    );
    final name = _naming ? 'Mencari nama...' : (_destName ?? 'Titik terpilih');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Jarak dari lokasi Anda ke $name',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            IconButton(
              tooltip: 'Hapus tujuan',
              visualDensity: VisualDensity.compact,
              onPressed: _clearDestination,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        Text(
          LocationService.formatDistance(meters),
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: AppColors.yellow,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Jarak garis lurus · ${dest.latitude.toStringAsFixed(5)}, '
          '${dest.longitude.toStringAsFixed(5)}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 6),
        _meLine(pos),
      ],
    );
  }
}
