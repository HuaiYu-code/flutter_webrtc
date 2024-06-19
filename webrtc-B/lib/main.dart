import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: WebRTCPage(),
    );
  }
}

class WebRTCPage extends StatefulWidget {
  @override
  _WebRTCPageState createState() => _WebRTCPageState();
}

class _WebRTCPageState extends State<WebRTCPage> {
  late RTCPeerConnection _peerConnection;
  late MediaStream _localStream;
  late RTCVideoRenderer _localRenderer;
  late RTCVideoRenderer _remoteRenderer;
  late WebSocketChannel _channel; // WebSocket channel
  String senderID = '';
  String targetID = '';

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _connectWebSocket();
    _createPeerConnection(); // 在这里初始化 _peerConnection
  }

  void _connectWebSocket() {
    final String serverUrl = 'ws://10.168.5.139:8080'; // 替换为你的 WebSocket 服务器地址和端口号
    _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
    
    // 可以添加监听器来处理 WebSocket 的消息
    _channel.stream.listen((message) {
      // 处理收到的消息
      print('Received message: $message');

      // 可以根据收到的消息类型做不同的处理
       _handleMessage(message);
    }, onDone: () {
      print('WebSocket channel closed');
    }, onError: (error) {
      print('Error: $error');
    });
  }


  void _handleMessage(dynamic message) async {
    try {
      if (message is String) {
        final data = jsonDecode(message);
        senderID = data['id'] ?? '';
        targetID = data['sender'] ?? '';

        switch (data['type']) {
          case 'offer':
            final offer = RTCSessionDescription(data['offer']['sdp'], data['offer']['type']); // 修正此处
            await _peerConnection.setRemoteDescription(offer);
            final answer = await _peerConnection.createAnswer();
            await _peerConnection.setLocalDescription(answer);

            // 通过WebSocket发送answer给发起方
            _sendSignal(jsonEncode({
              'type': 'answer',
              'answer': sessionDescriptionToJson(answer),
              'target': targetID,
              'sender': senderID
            }));
            break;
          case 'ice_candidate':
            final candidate = RTCIceCandidate(
              data['candidate']['candidate'],
              data['candidate']['sdpMid'],
              data['candidate']['sdpMLineIndex'],
            );
            await _peerConnection.addCandidate(candidate);
            break;
          // ... 处理其他消息类型，如ICE候选
        }
      } else {
        print('Received message is not a String: $message');
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }

  Map<String, dynamic> sessionDescriptionToJson(RTCSessionDescription sessionDescription) {
    return {
      'type': sessionDescription.type,
      'sdp': sessionDescription.sdp,
    };
  }

  Map<String, dynamic> iceCandidateToJson(RTCIceCandidate candidate) {
    return {
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex ?? 0, // 默认值0，以防万一sdpMLineIndex为null
    };
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peerConnection.dispose();
    _channel.sink.close(); // 关闭WebSocket连接
    super.dispose();
  }

  void _initRenderers() async {
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _createPeerConnection() async {
    final configuration = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };
    _peerConnection = await createPeerConnection(configuration);

    _peerConnection.onIceCandidate = (candidate) {
      print('has receviced candidate');

      _sendSignal(json.encode({
        'type': 'ice_candidate',
        'candidate': iceCandidateToJson(candidate),
        'target': targetID,
        'sender': senderID,
      }));
    };
    _peerConnection.onIceConnectionState = (state) {
      // Handle ICE connection state events
      print('ICE Connection State: $state');
    };

    _peerConnection.onTrack = (event) {
        print('onTrack');
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
        });
      }
    };

    if (_localStream != null) {
      for (var track in _localStream.getTracks()) {
        print('addTrack');
        _peerConnection.addTrack(track, _localStream);
      }
    }
  }

  void _createOffer() async {
    print('_createOffer');
    if (_peerConnection == null) {
      print('Error: _peerConnection is null');
      return;
    }
    try {
      final offer = await _peerConnection.createOffer({});
      await _peerConnection.setLocalDescription(offer);
      _sendSignal(json.encode({
        'type': 'offer',
        'offer': sessionDescriptionToJson(offer),
        'sender': senderID,
        'target': targetID,
      }));
    } catch (e) {
      print('Error during offer creation: $e');
    }
  }


  void _sendSignal(String message) {
    print('_sendSignal');
    _channel.sink.add(message);
  }
 
  // 请求权限方法
  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    return statuses[Permission.camera]!.isGranted && statuses[Permission.microphone]!.isGranted;
  }

  Future<void> _getUserMedia() async {
    try {

      bool permissionsGranted = await _requestPermissions();
      if (!permissionsGranted) {
        print('Permissions not granted');
        return;
      }
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': {
          'facingMode': 'user', // 使用前置摄像头
        }
      };

      final MediaStream stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      setState(() {
        _localStream = stream;
        _localRenderer.srcObject = _localStream;
      });
    } catch (e) {
      print('Error getting user media: $e');
    }
  }

  void _startListening() async {
    await _getUserMedia();
    // await _createPeerConnection();
  }
// i57x2
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('WebRTC B'),
      ),
      body: Center(
        child: Column(
          children: <Widget>[
            Expanded(child: RTCVideoView(_localRenderer)),
            Expanded(child: RTCVideoView(_remoteRenderer)),
            ElevatedButton(
              onPressed: _startListening,
              child: Text('Start Listening'),
            ),
          ],
        ),
      ),
    );
  }
}
