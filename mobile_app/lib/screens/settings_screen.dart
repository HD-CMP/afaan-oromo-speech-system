import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../providers/theme_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/localization_provider.dart';
import '../providers/transcription_provider.dart';
import '../providers/subtitle_provider.dart';
import '../config/app_colors.dart';
import '../config/app_constants.dart';
import '../config/api_config.dart';
import '../widgets/custom_snackbar.dart';
import '../services/server_control_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _ipController;
  late TextEditingController _portController;
  int _cacheSize = 0;
  final ServerControlService _serverControl = ServerControlService();
  ServerStatus _serverStatus = ServerStatus.unknown;
  bool _isCheckingServer = false;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: ApiConfig.serverIp);
    _portController = TextEditingController(text: ApiConfig.serverPort.toString());
    _calculateCacheSize();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _calculateCacheSize() async {
    final cacheManager = DefaultCacheManager();
    final files = await cacheManager.getFileFromCache('cache_key');
    setState(() {
      _cacheSize = 0;
    });
  }

  Future<void> _clearCache() async {
    final cacheManager = DefaultCacheManager();
    await cacheManager.emptyCache();
    setState(() {
      _cacheSize = 0;
    });
    if (mounted) {
      final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
      CustomSnackBar.show(
        context,
        message: localizationProvider.getString('cache_cleared'),
        type: SnackBarType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localizationProvider = Provider.of<LocalizationProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizationProvider.getString('settings')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        children: [
          _buildSectionTitle(localizationProvider.getString('language')),
          _buildLanguageCard(localizationProvider),
          const SizedBox(height: AppConstants.paddingXL),

          _buildSectionTitle(localizationProvider.getString('appearance')),
          _buildThemeCard(themeProvider, localizationProvider),
          const SizedBox(height: AppConstants.paddingXL),
          
          _buildSectionTitle(localizationProvider.getString('server_configuration')),
          _buildServerConfigCard(localizationProvider),
          const SizedBox(height: AppConstants.paddingMD),
          
          _buildServerControlCard(localizationProvider),
          const SizedBox(height: AppConstants.paddingXL),
          
          _buildSectionTitle(localizationProvider.getString('storage')),
          _buildStorageCard(localizationProvider),
          const SizedBox(height: AppConstants.paddingXL),
          
          _buildSectionTitle(localizationProvider.getString('about')),
          _buildAboutCard(localizationProvider),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildLanguageCard(LocalizationProvider localizationProvider) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accentIndigo.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.language_rounded, color: AppColors.accentIndigo, size: 20),
        ),
        title: Text(localizationProvider.getString('select_language'),
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(localizationProvider.languageName,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
        onTap: () => _showLanguageDialog(localizationProvider),
      ),
    ).animate().fadeIn().slideX(begin: -0.1, end: 0);
  }

  Widget _buildThemeCard(ThemeProvider themeProvider, LocalizationProvider localizationProvider) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.dark_mode_rounded, color: AppColors.primary, size: 20),
        ),
        title: Text(localizationProvider.getString('dark_mode'),
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(localizationProvider.getString('switch_theme_desc'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: Switch(
          value: themeProvider.isDarkMode,
          onChanged: (v) => themeProvider.toggleTheme(),
          activeColor: AppColors.primary,
        ),
      ),
    ).animate().fadeIn().slideX(begin: -0.1, end: 0);
  }

  Widget _buildServerConfigCard(LocalizationProvider localizationProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppConstants.paddingSM),
                  decoration: BoxDecoration(
                    gradient: AppColors.successGradient,
                    borderRadius: BorderRadius.circular(
                      AppConstants.borderRadiusSmall,
                    ),
                  ),
                  child: const Icon(
                    Icons.dns,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppConstants.paddingMD),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizationProvider.getString('server_address'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        localizationProvider.getString('configure_backend'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.paddingLG),
            TextField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: localizationProvider.getString('ip_address'),
                hintText: localizationProvider.getString('ip_hint'),
                prefixIcon: const Icon(Icons.computer),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppConstants.paddingMD),
            TextField(
              controller: _portController,
              decoration: InputDecoration(
                labelText: localizationProvider.getString('port'),
                hintText: localizationProvider.getString('port_hint'),
                prefixIcon: const Icon(Icons.settings_ethernet),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppConstants.paddingLG),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _testConnection,
                    icon: const Icon(Icons.wifi_find),
                    label: Text(localizationProvider.getString('test_connection')),
                  ),
                ),
                const SizedBox(width: AppConstants.paddingSM),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saveServerConfig,
                    icon: const Icon(Icons.save),
                    label: Text(localizationProvider.getString('save')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.paddingSM),
            Container(
              padding: const EdgeInsets.all(AppConstants.paddingMD),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(
                  AppConstants.borderRadiusSmall,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppColors.primaryColor,
                  ),
                  const SizedBox(width: AppConstants.paddingSM),
                  Expanded(
                    child: Text(
                      localizationProvider.getString('ensure_same_network'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.primaryColor,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.2, end: 0);
  }

  Widget _buildServerControlCard(LocalizationProvider localizationProvider) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (_serverStatus) {
      case ServerStatus.running:
        statusColor = AppColors.successColor;
        statusIcon = Icons.check_circle;
        statusText = 'Running';
        break;
      case ServerStatus.stopped:
        statusColor = AppColors.errorColor;
        statusIcon = Icons.cancel;
        statusText = 'Stopped';
        break;
      case ServerStatus.unknown:
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
        statusText = 'Unknown';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppConstants.paddingSM),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(
                      AppConstants.borderRadiusSmall,
                    ),
                  ),
                  child: const Icon(
                    Icons.power_settings_new,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppConstants.paddingMD),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Remote Server Control',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(statusIcon, size: 16, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 14,
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: _isCheckingServer
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: _isCheckingServer ? null : _checkServerStatus,
                  tooltip: 'Refresh Status',
                ),
              ],
            ),
            const SizedBox(height: AppConstants.paddingMD),
            const Divider(height: 1),
            const SizedBox(height: AppConstants.paddingMD),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _serverStatus == ServerStatus.stopped
                        ? _startServer
                        : null,
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: Text(localizationProvider.getString('start_server')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.successColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: AppConstants.paddingMD),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _serverStatus == ServerStatus.running
                        ? _stopServer
                        : null,
                    icon: const Icon(Icons.stop, size: 20),
                    label: Text(localizationProvider.getString('stop_server')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.errorColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: AppConstants.paddingMD),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _serverStatus == ServerStatus.running
                        ? _restartServer
                        : null,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: Text(localizationProvider.getString('restart_server')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warningColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.paddingSM),
            Text(
              'Control the API server remotely. Server must be running server_control.py',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 150.ms).slideX(begin: -0.2, end: 0);
  }

  Widget _buildStorageCard(LocalizationProvider localizationProvider) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(AppConstants.paddingSM),
              decoration: BoxDecoration(
                gradient: AppColors.warningGradient,
                borderRadius: BorderRadius.circular(
                  AppConstants.borderRadiusSmall,
                ),
              ),
              child: const Icon(
                Icons.storage,
                color: Colors.white,
              ),
            ),
            title: Text(localizationProvider.getString('cache_size')),
            subtitle: Text(_formatBytes(_cacheSize)),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _calculateCacheSize,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.errorColor),
            title: Text(localizationProvider.getString('clear_cache')),
            subtitle: Text(localizationProvider.getString('free_up_storage')),
            trailing: ElevatedButton(
              onPressed: _clearCache,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.errorColor,
              ),
              child: Text(localizationProvider.getString('clear')),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.2, end: 0);
  }

  Widget _buildAboutCard(LocalizationProvider localizationProvider) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(AppConstants.paddingSM),
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(
                  AppConstants.borderRadiusSmall,
                ),
              ),
              child: const Icon(
                Icons.info,
                color: Colors.white,
              ),
            ),
            title: Text(localizationProvider.getString('version')),
            subtitle: const Text('1.0.0'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(localizationProvider.getString('developer')),
            subtitle: Text(localizationProvider.getString('app_team')),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.description),
            title: Text(localizationProvider.getString('license')),
            subtitle: Text(localizationProvider.getString('mit_license')),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.2, end: 0);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _checkServerStatus() async {
    setState(() {
      _isCheckingServer = true;
    });

    try {
      _serverControl.updateBaseUrl();
      final info = await _serverControl.getStatus();
      
      if (mounted) {
        setState(() {
          _serverStatus = info.status;
          _isCheckingServer = false;
        });
      }
    } catch (e) {
      debugPrint('[Settings] Error checking server status: $e');
      if (mounted) {
        setState(() {
          _serverStatus = ServerStatus.unknown;
          _isCheckingServer = false;
        });
      }
    }
  }

  Future<void> _startServer() async {
    try {
      CustomSnackBar.show(
        context,
        message: 'Starting API server...',
        type: SnackBarType.info,
      );

      _serverControl.updateBaseUrl();
      final result = await _serverControl.startServer();
      
      if (mounted) {
        await _checkServerStatus();
        
        CustomSnackBar.show(
          context,
          message: result['message'] ?? 'Server started',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Failed to start server: ${e.toString()}',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _stopServer() async {
    try {
      CustomSnackBar.show(
        context,
        message: 'Stopping API server...',
        type: SnackBarType.info,
      );

      _serverControl.updateBaseUrl();
      final result = await _serverControl.stopServer();
      
      if (mounted) {
        await _checkServerStatus();
        
        CustomSnackBar.show(
          context,
          message: result['message'] ?? 'Server stopped',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Failed to stop server: ${e.toString()}',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _restartServer() async {
    try {
      CustomSnackBar.show(
        context,
        message: 'Restarting API server...',
        type: SnackBarType.info,
      );

      _serverControl.updateBaseUrl();
      final result = await _serverControl.restartServer();
      
      if (mounted) {
        await _checkServerStatus();
        
        CustomSnackBar.show(
          context,
          message: result['message'] ?? 'Server restarted',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Failed to restart server: ${e.toString()}',
          type: SnackBarType.error,
        );
      }
    }
  }

  bool _isValidIpAddress(String ip) {
    // Allow localhost
    if (ip == 'localhost') return true;
    
    // Validate IPv4 format
    final ipv4Pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (!ipv4Pattern.hasMatch(ip)) return false;
    
    // Check each octet is 0-255
    final parts = ip.split('.');
    return parts.every((part) {
      final num = int.tryParse(part);
      return num != null && num >= 0 && num <= 255;
    });
  }

  Future<void> _testConnection() async {
    final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
    
    // Validate IP and port first
    final ip = _ipController.text.trim();
    final portText = _portController.text.trim();
    
    if (ip.isEmpty || portText.isEmpty) {
      CustomSnackBar.show(
        context,
        message: localizationProvider.getString('invalid_ip_port'),
        type: SnackBarType.error,
      );
      return;
    }
    
    if (!_isValidIpAddress(ip)) {
      CustomSnackBar.show(
        context,
        message: 'Invalid IP address format. Use format: xxx.xxx.xxx.xxx',
        type: SnackBarType.error,
      );
      return;
    }
    
    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) {
      CustomSnackBar.show(
        context,
        message: localizationProvider.getString('invalid_port'),
        type: SnackBarType.error,
      );
      return;
    }
    
    CustomSnackBar.show(
      context,
      message: 'Testing connection to $ip:$port...',
      type: SnackBarType.info,
    );
    
    // Store original config to restore if test fails
    final originalIp = ApiConfig.serverIp;
    final originalPort = ApiConfig.serverPort;
    
    // Temporarily update config for test (without saving to SharedPreferences)
    ApiConfig.updateConfigTemporarily(ip, port);
    
    try {
      // Update all providers' API services with new config
      final connectionProvider = Provider.of<ConnectionProvider>(context, listen: false);
      final transcriptionProvider = Provider.of<TranscriptionProvider>(context, listen: false);
      final subtitleProvider = Provider.of<SubtitleProvider>(context, listen: false);
      
      transcriptionProvider.updateConfiguration();
      subtitleProvider.updateConfiguration();
      await connectionProvider.updateConfiguration();
      
      if (mounted) {
        if (connectionProvider.isConnected) {
          CustomSnackBar.show(
            context,
            message: localizationProvider.getString('connection_successful'),
            type: SnackBarType.success,
          );
        } else {
          // Revert to original config if connection failed
          ApiConfig.updateConfigTemporarily(originalIp, originalPort);
          transcriptionProvider.updateConfiguration();
          subtitleProvider.updateConfiguration();
          await connectionProvider.updateConfiguration();
          
          CustomSnackBar.show(
            context,
            message: localizationProvider.getString('connection_failed'),
            type: SnackBarType.error,
          );
          
          // Reset controllers to original values
          _ipController.text = originalIp;
          _portController.text = originalPort.toString();
        }
      }
    } catch (e) {
      // Revert to original config on error
      ApiConfig.updateConfigTemporarily(originalIp, originalPort);
      
      if (mounted) {
        final connectionProvider = Provider.of<ConnectionProvider>(context, listen: false);
        final transcriptionProvider = Provider.of<TranscriptionProvider>(context, listen: false);
        final subtitleProvider = Provider.of<SubtitleProvider>(context, listen: false);
        
        transcriptionProvider.updateConfiguration();
        subtitleProvider.updateConfiguration();
        await connectionProvider.updateConfiguration();
        
        CustomSnackBar.show(
          context,
          message: '✗ Connection failed: ${e.toString()}',
          type: SnackBarType.error,
        );
        
        // Reset controllers to original values
        _ipController.text = originalIp;
        _portController.text = originalPort.toString();
      }
    }
  }

  Future<void> _saveServerConfig() async {
    final localizationProvider = Provider.of<LocalizationProvider>(context, listen: false);
    
    final ip = _ipController.text.trim();
    final portText = _portController.text.trim();
    
    if (ip.isEmpty || portText.isEmpty) {
      CustomSnackBar.show(
        context,
        message: localizationProvider.getString('invalid_ip_port'),
        type: SnackBarType.error,
      );
      return;
    }
    
    if (!_isValidIpAddress(ip)) {
      CustomSnackBar.show(
        context,
        message: 'Invalid IP address format. Use format: xxx.xxx.xxx.xxx',
        type: SnackBarType.error,
      );
      return;
    }
    
    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) {
      CustomSnackBar.show(
        context,
        message: localizationProvider.getString('invalid_port'),
        type: SnackBarType.error,
      );
      return;
    }
    
    await ApiConfig.updateConfig(ip, port);
    
    if (mounted) {
      CustomSnackBar.show(
        context,
        message: localizationProvider.getString('config_saved'),
        type: SnackBarType.success,
      );
      
      // Update all providers' API services with new configuration and test connection
      final connectionProvider = Provider.of<ConnectionProvider>(context, listen: false);
      final transcriptionProvider = Provider.of<TranscriptionProvider>(context, listen: false);
      final subtitleProvider = Provider.of<SubtitleProvider>(context, listen: false);
      
      transcriptionProvider.updateConfiguration();
      subtitleProvider.updateConfiguration();
      await connectionProvider.updateConfiguration();
    }
  }

  void _showLanguageDialog(LocalizationProvider localizationProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizationProvider.getString('select_language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<AppLanguage>(
              title: Text(localizationProvider.getString('english')),
              subtitle: const Text('English'),
              value: AppLanguage.english,
              groupValue: localizationProvider.currentLanguage,
              onChanged: (value) async {
                if (value != null) {
                  await localizationProvider.setLanguage(value);
                  if (context.mounted) {
                    Navigator.pop(context);
                    CustomSnackBar.show(
                      context,
                      message: localizationProvider.getString('language_changed'),
                      type: SnackBarType.success,
                    );
                  }
                }
              },
            ),
            RadioListTile<AppLanguage>(
              title: Text(localizationProvider.getString('afaan_oromo')),
              subtitle: const Text('Afaan Oromoo'),
              value: AppLanguage.afaanOromo,
              groupValue: localizationProvider.currentLanguage,
              onChanged: (value) async {
                if (value != null) {
                  await localizationProvider.setLanguage(value);
                  if (context.mounted) {
                    Navigator.pop(context);
                    CustomSnackBar.show(
                      context,
                      message: localizationProvider.getString('language_changed'),
                      type: SnackBarType.success,
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
