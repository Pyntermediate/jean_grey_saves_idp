import 'dart:async';
import 'dart:io';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:path_provider/path_provider.dart';

class WifiP2pService {
  WifiP2pService._privateConstructor();
  static final WifiP2pService instance = WifiP2pService._privateConstructor();

  final FlutterP2pHost _host = FlutterP2pHost();
  final FlutterP2pClient _client = FlutterP2pClient();

  bool _isInitialized = false;
  bool isHostMode = false;
  bool isClientMode = false;

  final _connectionStatusController = StreamController<String>.broadcast();
  Stream<String> get connectionStatusStream => _connectionStatusController.stream;

  final _transferProgressController = StreamController<FileDownloadProgressUpdate>.broadcast();
  Stream<FileDownloadProgressUpdate> get transferProgressStream => _transferProgressController.stream;


  final _receivedTextController = StreamController<String>.broadcast();
  Stream<String> get receivedTextStream => _receivedTextController.stream;

  final _transferCompleteController = StreamController<String>.broadcast();

  Stream<String> get transferCompleteStream => _transferCompleteController.stream;
  
  final _sentFilesController = StreamController<List<HostedFileInfo>>.broadcast();
  Stream<List<HostedFileInfo>> get sentFilesStream => _sentFilesController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _host.initialize();
    await _client.initialize();

    if (!await _host.checkP2pPermissions()) {
      await _host.askP2pPermissions();
    }
    if (!await _host.checkWifiEnabled()) {
      await _host.enableWifiServices();
    }
    
    _client.streamReceivedFilesInfo().listen((files) async {
      if (files.isNotEmpty) {
        final file = files.last;
        if (file.state == ReceivableFileState.idle) {
          final dir = await getApplicationDocumentsDirectory();
          await _client.downloadFile(
            file.info.id,
            dir.path,
            onProgress: (progress) {
              _transferProgressController.add(progress);
            },
          );
          _transferCompleteController.add("${dir.path}/${file.info.name}");
        }
      }
    });

    _host.streamReceivedFilesInfo().listen((files) async {
      if (files.isNotEmpty) {
        final file = files.last;
        if (file.state == ReceivableFileState.idle) {
          final dir = await getApplicationDocumentsDirectory();
          await _host.downloadFile(
            file.info.id,
            dir.path,
            onProgress: (progress) {
              _transferProgressController.add(progress);
            },
          );
          _transferCompleteController.add("${dir.path}/${file.info.name}");
        }
      }
    });
    
    _host.streamSentFilesInfo().listen((files) {
      _sentFilesController.add(files);
    });
    _client.streamSentFilesInfo().listen((files) {
      _sentFilesController.add(files);
    });

    _isInitialized = true;
  }

  Future<String?> startHosting() async {
    await _client.disconnect();
    
    isClientMode = false;
    _connectionStatusController.add("Creating Wi-Fi Direct Group...");
    
    int maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _host.removeGroup(); // Tear down any stuck native state
        
        // Exponential backoff to give hardware radio time to reset
        int waitTimeMs = attempt == 1 ? 500 : (1000 * attempt);
        await Future.delayed(Duration(milliseconds: waitTimeMs));
        
        final state = await _host.createGroup(advertise: true).timeout(const Duration(seconds: 15));
        
        if (state.isActive) {
          isHostMode = true;
          _connectionStatusController.add("Waiting for receiver to connect...");
          return "WFD|${state.ssid}|${state.preSharedKey}";
        }
      } catch (e) {
        if (attempt == maxRetries) {
          return "ERROR|Exception: $e";
        }
        _connectionStatusController.add("Retrying hotspot creation (Attempt ${attempt + 1})...");
      }
    }
    
    return "ERROR|Failed to create hotspot after $maxRetries attempts";
  }

  void clearStatus() {
    _connectionStatusController.add("Disconnected.");
  }

  Future<void> connectToHost(String ssid, String password) async {
    try {
      isHostMode = false;
      isClientMode = true;
      
      _connectionStatusController.add("Connecting to high-speed transfer...");
      await _client.connectWithCredentials(ssid, password);
      _connectionStatusController.add("Connected!");
    } catch (e) {
      _connectionStatusController.add("Client Error: $e");
    }
  }

  Future<void> waitForClient() async {
    if (isHostMode) {
      try {
        await _host.streamClientList().firstWhere((clients) => clients.isNotEmpty).timeout(const Duration(seconds: 60));
        _connectionStatusController.add("Peer connected! Sending file...");
      } catch (e) {
        _connectionStatusController.add("Connection timed out: Peer took too long to connect.");
        throw Exception("Peer failed to join in time.");
      }
    }
  }

  Future<void> sendFile(File file) async {
    if (isHostMode) {
      await _host.broadcastFile(file);
    } else if (isClientMode) {
      await _client.broadcastFile(file);
    }
  }

  void sendText(String text) {
    if (isHostMode) {
      _host.broadcastText(text);
    } else if (isClientMode) {
      _client.broadcastText(text);
    }
  }

  Future<void> stop() async {
    if (isHostMode) {
      await _host.removeGroup();
    }
    if (isClientMode) {
      await _client.disconnect();
    }
    isHostMode = false;
    isClientMode = false;
    _connectionStatusController.add("Disconnected.");
  }
}

