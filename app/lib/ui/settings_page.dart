import 'package:flutter/material.dart';

import '../services/server_api.dart';
import 'app_scope.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _filled = false;
  String? _status;
  bool _ok = false;
  bool _testing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final settings = AppScope.of(context).settings;
    _url.text = settings.serverUrl;
    _token.text = settings.token;
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final scope = AppScope.of(context);
    setState(() {
      _testing = true;
      _status = null;
    });
    await scope.settings.save(serverUrl: _url.text, token: _token.text);
    try {
      final version = await scope.downloads.api.health();
      setState(() {
        _ok = true;
        _status = 'Connesso. yt-dlp $version';
      });
    } on ServerException catch (e) {
      setState(() {
        _ok = false;
        _status = e.message;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar(title: Text('Impostazioni'), pinned: true),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: [
              const Text('SERVER DI DOWNLOAD', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Indirizzo', hintText: 'http://IP-DEL-PC:8000'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _token,
                obscureText: true,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Token (facoltativo)'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _testing ? null : _saveAndTest,
                child: Text(_testing ? 'Verifica in corso…' : 'Salva e prova la connessione'),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      _ok ? Icons.check_circle : Icons.error_outline,
                      color: _ok ? Colors.greenAccent : AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_status!)),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Il server è il programma Python nella cartella "server" del progetto: tienilo acceso su un PC '
                'o un Raspberry Pi. I brani già scaricati si ascoltano anche senza server.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
